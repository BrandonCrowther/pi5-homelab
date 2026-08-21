# Zigbee: Home Assistant Connect ZBT-2

Setup notes and troubleshooting for the ZBT-2 Zigbee coordinator attached to the Pi 5,
passed through to the `homeassistant` container.

**Resolved:** 2026-08-14

---

## Hardware summary

| Property | Value |
|---|---|
| Device | Home Assistant Connect ZBT-2 (Nabu Casa) |
| USB ID | `303a:831a` (Espressif) |
| Kernel driver | `cdc_acm` |
| Host node | `/dev/ttyACM0` (major 166) |
| Stable path | `/dev/serial/by-id/usb-Nabu_Casa_ZBT-2_E072A1FAAD5C-if00` |
| Convenience symlink | `/dev/zbt2` (from our udev rule) |
| Firmware | EZSP (Zigbee NCP) `7.4.4.6 build 0 (20251124171423)` |
| **Baud rate** | **460800** (not the 115200 default) |

---

## The original symptom

Enabling `devices:` in the compose file produced an error that the tty device did not
exist, and Home Assistant's ZBT-2 onboarding appeared to fail while flashing firmware.

The adapter never needed flashing. It already had current Zigbee firmware. HA's ZBT-2
onboarding flow *ends* in a firmware step, so when it could not open the serial port it
failed at that step and surfaced a flashing error. The real fault was device passthrough.

The HA log entry that gave it away:

```
FileNotFoundError: [Errno 2] No such file or directory: '/dev/ttyACM0'
```

---

## Cause 1 — wrong device class (`ttyUSB0` vs `ttyACM0`)

The compose file mapped `/dev/ttyUSB0`, which does not exist on this host.

The distinction is about **where USB-to-serial conversion happens**:

| | `ttyUSB*` | `ttyACM*` |
|---|---|---|
| Driver | `ftdi_sio`, `cp210x`, `ch341` | `cdc_acm` |
| Hardware | Separate bridge chip translating USB↔UART | Chip speaks USB natively |
| Examples | ZBT-1 / SkyConnect (CP2102N), ConBee II | **ZBT-2**, most ESP32-S3 boards |

The ZBT-2's USB ID is `303a:831a` — vendor `303a` is Espressif. The onboard ESP32
implements USB CDC-ACM in firmware and bridges to the EFR32 radio over an internal UART.
There is no bridge chip, so the kernel binds `cdc_acm` and the node is `ttyACM0`.
`/dev/ttyUSB0` was never going to appear.

Docker refuses to start a container whose `devices:` source path is missing, which is why
the container sat in `Created` state and never ran.

### Why the `by-id` path matters

`ttyACM0` is assigned by enumeration **order**, not identity. Adding any other CDC-ACM
device — a UPS, a printer, a second dongle — can silently shift the coordinator to
`ttyACM1` and break ZHA on the next reboot.

The `by-id` path is derived from the device serial number and is stable permanently.
The container-side target stays `/dev/ttyACM0` because HA's ZBT-2 integration expects
that specific path inside the container.

---

## Cause 2 — ModemManager hijacking the port

Not the cause of the original error, but it would have broken any genuine firmware update.

The host reported:

```
ID_MM_CANDIDATE=1
```

ModemManager was active and enabled. It treats every new `ttyACM` device as a possible
cellular modem — historically that is what CDC-ACM meant — and on plug-in it opens the
port and sends AT commands. A Zigbee coordinator receives that as corruption mid-stream.

This is the most common cause of genuinely failed ZBT-2 flashes. Because it is a race
against whoever opens the port first, it produces intermittent, hard-to-reproduce failures.

---

## The fix

### 1. udev rule — `/etc/udev/rules.d/99-zbt2.rules`

```udev
# Home Assistant Connect ZBT-2 (Nabu Casa) — Espressif native USB CDC-ACM
# 303a:831a enumerates as /dev/ttyACM*, NOT /dev/ttyUSB*.
#
# ModemManager flags this as a modem candidate (ID_MM_CANDIDATE=1) and probes
# it with AT commands on plug-in. That probe corrupts the serial stream and is
# the most common cause of failed Zigbee firmware flashes. Tell MM to ignore it.
SUBSYSTEM=="tty", ATTRS{idVendor}=="303a", ATTRS{idProduct}=="831a", \
  ENV{ID_MM_DEVICE_IGNORE}="1", \
  ENV{ID_MM_PORT_IGNORE}="1", \
  GROUP="dialout", MODE="0660", \
  SYMLINK+="zbt2"
```

Apply with:

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=tty --action=add
```

Scoped to this one device rather than masking ModemManager wholesale — reversible, and it
does not remove functionality. This host has no modems (`mmcli -L` returns none), so
`sudo systemctl mask ModemManager` is also safe if preferred.

### 2. `docker-compose.yaml`

```yaml
volumes:
  - ./config:/config
  - /run/dbus:/run/dbus:ro
  - /run/udev:/run/udev:ro
devices:
  - /dev/serial/by-id/usb-Nabu_Casa_ZBT-2_E072A1FAAD5C-if00:/dev/ttyACM0
```

`/run/udev` is needed because HA's `usb` integration uses pyudev. Without it, pyudev falls
back to scraping `/sys` — which is visible inside the container by default — and HA
"discovers" adapters it cannot actually open. That is the source of the phantom-discovery
reports in the HA issue tracker.

---

## Verification

```
$ docker ps --filter name=homeassistant
homeassistant   Up

$ docker exec homeassistant ls -l /dev/ttyACM0
crw-rw----  1 root  dialout  166, 0  /dev/ttyACM0

$ docker exec homeassistant python3 -c "import serial; s=serial.Serial('/dev/ttyACM0',460800,timeout=1); print('OPENED OK:', s.name, s.baudrate)"
OPENED OK: /dev/ttyACM0 460800

$ udevadm info -q property -n /dev/ttyACM0 | grep ID_MM
ID_MM_CANDIDATE=1
ID_MM_DEVICE_IGNORE=1
ID_MM_PORT_IGNORE=1
```

HA web UI responds on `:8123`, and the `FileNotFoundError` is gone from the log.

---

## Adding the integration

Settings → Devices & Services → Add Integration → **Zigbee Home Automation**

- Serial port: `/dev/ttyACM0`
- **Baud rate: 460800** — not the 115200 default
- Decline any firmware-install prompt; `7.4.4.6` is current

---

## Out-of-band firmware access

Flash and probe from the **host**, not the container — this sidesteps all passthrough
concerns and is the reliable path if the device ever needs recovery.

```bash
python3 -m venv usf-venv
./usf-venv/bin/pip install universal-silabs-flasher

# Read current state — safe, non-destructive
./usf-venv/bin/universal-silabs-flasher --device /dev/zbt2 probe

# Flash (destructive). --allow-cross-flashing only when switching Zigbee <-> Thread
./usf-venv/bin/universal-silabs-flasher --device /dev/zbt2 flash \
  --firmware <file>.gbl
```

Stop the `homeassistant` container first so it is not holding the port.

---

## Known watch item: USB enumeration fault

The kernel log shows the adapter failing its first enumeration attempt before recovering:

```
usb 3-2: device not accepting address 2, error -71
usb 3-2: new full-speed USB device number 3 using xhci-hcd   # retry succeeded
```

Harmless as observed, but `-71` indicates a signalling or power fault. If Zigbee dropouts
appear later, this is the first suspect.

The standard remedy is also what Nabu Casa recommends for range: put the ZBT-2 on a short
USB 2.0 extension cable, away from the Pi. USB 3.0 ports and the Pi itself emit broadband
noise directly in the 2.4 GHz band, which degrades both enumeration reliability and Zigbee
reception.

---

## References

- [Recovering from a failed ZBT-2 flash](https://community.home-assistant.io/t/solved-recovering-from-a-failed-zbt-2-flash/977625)
- [ZBT-2 with Home Assistant on Docker](https://matteoschizzerotto.dev/snippets/zbt-2/)
- [Spurious ZBT-2 discovery when device isn't passed to HA container (core#170154)](https://github.com/home-assistant/core/issues/170154)
- [HA in Docker cannot discover ZBT-2 when ACM number is not stable (core#160224)](https://github.com/home-assistant/core/issues/160224)
- [Zigbee2MQTT: fails to start / crashes at runtime](https://www.zigbee2mqtt.io/guide/installation/20_zigbee2mqtt-fails-to-start_crashes-runtime.html)
