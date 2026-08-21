# Service Dashboard

Replaces the retired `homepage` stack and its Chromium kiosk. Shows service
up/down, per-host CPU/memory/temperature, Pi-hole stats, and weather.

Live at <https://ha.bcrowthe.com/service-dashboard>.

## How it is loaded

It is a **storage-mode** dashboard: Home Assistant owns the live copy in
`../config/.storage/lovelace.service_dashboard`, which is gitignored. The UI
editor works normally.

`service-dashboard.yaml` here is the version-controlled record, not the source
of truth. The two drift as soon as you move a card in the UI — run `./export.sh`
afterwards to refresh this file from the live config.

Note what export costs you: HA's stored copy is JSON and never held comments,
so exporting keeps this file's leading header block but **discards every inline
comment in the views body**. Worth running after real UI edits; not worth
running to tidy up.

The url_path must contain a hyphen — HA rejects a single word with "Url path
needs to contain a hyphen (-)". Hence `/service-dashboard`.

This was briefly YAML-mode (`lovelace:` in `configuration.yaml`, HA reading the
file directly). That made the repo authoritative and needed no export step, but
disabled the UI pencil. Storage mode was the better trade.

## Service probes

The `binary_sensor.status_*` entities come from `../config/command_line.yaml`,
included from `configuration.yaml`. They load on HA start — no UI step, no HACS:

| Entity | Probes |
| --- | --- |
| `binary_sensor.status_traefik` | `https://127.0.0.1/` on the host |
| `binary_sensor.status_vaultwarden` | `https://vault.bcrowthe.com/` |
| `binary_sensor.status_pi_hole` | `http://192.168.2.3:8314/admin/` |
| `binary_sensor.status_blog` | `https://blog.bcrowthe.com/` |
| `binary_sensor.status_fps` | `https://fps.bcrowthe.com/` |
| `binary_sensor.status_maddy` | `https://maddy.bcrowthe.com/` |
| `binary_sensor.status_whoami` | `https://whoami.bcrowthe.com/` |
| `binary_sensor.status_glances_pi5` | `http://192.168.2.2:61208/api/4/cpu` |
| `binary_sensor.status_glances_pi3` | `http://192.168.2.3:61208/api/4/cpu` |

The id is `status_pi_hole`, not `status_pihole` — HA slugified the hyphen in
the friendly name "Status Pi-hole".

Public services are probed over their real hostnames rather than against the
container, so one green tile covers the whole visitor path: public DNS ->
traefik -> TLS -> service. A cert expiry or a broken router shows up; a
container-level check would miss both.

## Stats entities

Glances (x2), Pi-hole and Open-Meteo are config-flow integrations added through
the UI. Entity ids derive from whatever each config entry was named, so they are
not predictable in advance — these are the real ones:

| Card | Pi 5 | Pi 3 |
| --- | --- | --- |
| CPU | `sensor.192_168_2_2_cpu_usage` | `sensor.raspberry_pi_3_cpu_usage` |
| Memory | `sensor.192_168_2_2_memory_usage` | `sensor.raspberry_pi_3_memory_usage` |
| Temperature | `sensor.192_168_2_2_cpu_thermal_0_temperature` | `sensor.raspberry_pi_3_cpu_thermal_0_temperature` |

Use `cpu_usage`, not `cpu_load`. Glances exposes both; `cpu_usage` is the
percentage the old homepage `metric: cpu` widget showed, while `cpu_load` is the
load average and reads as a much smaller, differently-scaled number on a 0-100
gauge.

Pi-hole: `sensor.pi_hole_dns_queries`, `sensor.pi_hole_ads_blocked`,
`sensor.pi_hole_ads_percentage_blocked`, `sensor.pi_hole_domains_blocked`,
`binary_sensor.pi_hole_status`, and `switch.pi_hole` — the switch is a genuine
gain over the old read-only widget. Weather is `weather.home`.

### The Pi 5 entity ids are ugly on purpose

The Pi 5 Glances config entry was named `192.168.2.2`, giving
`sensor.192_168_2_2_*` where the Pi 3 entry gives `sensor.raspberry_pi_3_*`.
Renaming the entry regenerates its entity ids and breaks every reference in the
dashboard, so rename only if you update the dashboard in the same pass.

## Why there is no kiosk any more

`homepage` had no authentication, so the old `kiosk-start.sh` could point
Chromium at `localhost:3000` and get a dashboard with no login. Every HA
dashboard requires one, and bridging that gap needs either a `trusted_networks`
auth provider or a persistent browser profile — both of which weaken or
complicate the setup for one screen.

The kiosk was retired instead: the labwc autostart entry is gone and the Pi
boots to a normal desktop. Reach the dashboard from any browser; the route is
protected by password plus TOTP.
