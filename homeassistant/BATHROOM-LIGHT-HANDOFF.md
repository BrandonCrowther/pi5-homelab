# Bathroom light: handoff

**Status:** unresolved by design, not by bug. Two real bugs were found and fixed;
the underlying feature the design depends on does not work on this hardware.
A direction decision is needed before more code is written.

**Date of investigation:** 2026-08-21 (timezone `America/Halifax`).
**Changes from this session are uncommitted** — see [What changed](#what-changed).

---

## TL;DR for the next agent

The bathroom bulb is a **smart bulb behind a dumb wall switch**. The design in
`config/automations.yaml` works around that by writing the bulb's firmware
power-on brightness (ZCL `StartUpCurrentLevel`, 0x4000) so the bulb comes up at
the right level with no help from HA at flip time.

**That attribute does not work on this bulb.** The bulb accepts the write,
stores it in NVRAM, reads it back correctly — and then ignores it at power-up.

There is also **no event HA can trigger on** when the wall switch is flipped, so
no HA-side correction can react. Those two facts together mean the current
approach cannot be made to work by fixing it. See
[Direction decision needed](#direction-decision-needed).

**Do not re-verify anything using the ZHA attribute cache.** It is written
optimistically on write, not only on read, and it lied throughout this
investigation. See [Verification traps](#verification-traps) before trusting
any evidence.

---

## The device

| | |
|---|---|
| Model | ThirdReality 3RCB01057Z |
| IEEE | `b4:e8:42:8f:6e:26:00:00` |
| HA device_id | `de67b5df8b7e284774122875fed4d6d9` |
| Device name | "Bathroom Light" |
| Light entity | `light.third_reality_inc_3rcb01057z` (friendly name "Bathroom Light 1") |
| Firmware | `0x0000004a` — **already latest**, no OTA fix available |

### There are four identical bulbs — the automation targets the right one

This was checked and is **not** a source of confusion, but it looks like one at
first glance because the entity registry has `_2` and `_3` suffixed duplicates
of every entity. Those are three *other physical bulbs* of the same model, not
stale registrations:

| IEEE | Name | Entity suffix |
|---|---|---|
| `b4:e8:42:8f:6e:26:00:00` | **Bathroom Light** ← the target | *(none)* |
| `b4:e8:42:8f:ba:08:00:00` | Lamp | *(none — separate device)* |
| `b4:e8:42:90:be:88:00:00` | *unnamed* | `_2` |
| `b4:e8:42:8f:fa:c8:00:00` | *unnamed* | `_3` |

Verified by joining `core.entity_registry` → `core.device_registry` on
`device_id`. The un-suffixed `light.third_reality_inc_3rcb01057z` maps to the
"Bathroom Light" device. The automation is aimed correctly.

---

## What was actually wrong (and is now fixed)

### Bug 1 — a debug pin left in the automation

`config/automations.yaml` had the power-on level hardcoded, with a comment
saying to restore it after a test that was never finished:

```yaml
# TEMPORARY: pinned to 13 for the test. Restore to
#   {{ 13 if is_state('sun.sun', 'below_horizon') else 254 }}
# once we know whether OnLevel is the culprit.
target: 13
```

`13` is 5% of 255. The bulb was being told "come up at 5%" around the clock.
**This was the direct cause of the reported symptom** (light stuck at 5% during
the day) and is now restored to the sun-based expression.

### Bug 2 — removing `initial_state: false` does not re-enable an automation

The adaptive-curve automation had `initial_state: false` from the same test.
Deleting that line is **not** sufficient: with no `initial_state` key, HA
restores the entity's last persisted enabled/disabled state, which was `off`.
It came back up disabled after a restart.

Fixed by setting `initial_state: true` explicitly. Worth remembering generally.

Neither fix solves the wall-switch case, because that case is not solvable this
way.

---

## The core finding: the bulb ignores `StartUpCurrentLevel`

### Evidence

1. **A genuine read-back shows the write persisted.** After an HA restart at
   10:51:56, ZHA interrogated the device and at **10:53:04** reported
   `number.*_power_on_level` = **254** and `number.*_on_level` = **254**, with
   `select.*_power_on_behavior` = **On**.

   This read is trustworthy: it landed 1s after the entity left `unavailable`,
   and the automation that writes those values has a 10s delay, so it could not
   have produced it. The bulb really does store 254.

2. **The bulb still comes up dim.** Confirmed by the user visually, after
   several wall-switch cycles, with 254 stored.

3. **Explicit level commands work fine.** Toggling the light off→on *from the HA
   UI* brings the room to full brightness. The bulb is not broken; it just does
   not honour this one attribute at power-up.

### The prior "VERIFIED WORKING" claim is a false positive

`config/automations.yaml` contains a comment asserting the mechanism was
verified, based on: `StartUpCurrentLevel=13` written, then `CurrentLevel=13`
read after a wall-switch cycle.

**That test cannot distinguish success from failure.** Writing `13` (dim) and
observing a dim bulb is exactly what a bulb that *always* comes up dim would
produce. Writing `254` was the first test capable of telling the two apart, and
it failed. Treat that comment as disproven — it should be corrected or deleted.

---

## The second constraint: HA cannot detect a wall-switch flip

Even with a working HA-side correction, there is nothing to trigger it on.

- **`consider_unavailable_mains` is already `60`** in the ZHA config entry
  options. The `KNOWN LIMITATION` comment in `automations.yaml` claiming it is
  the 2-hour default is **stale and wrong** — that setting was already
  shortened. It does not help: a wall flick is ~1s, so the device never misses
  enough check-ins to be marked unavailable.
- **ZHA emits `device_offline` but never `device_online`.** All `zha_event`
  rows in the recorder are `device_event_type: device_offline`. There is no
  power-on event to trigger on.
- **The entity simply never changes state.** Across several deliberate
  wall-switch cycles between 10:30 and 10:47, `light.third_reality_inc_3rcb01057z`
  produced **exactly one** state row (`on` at 10:36:07) — no `unavailable`, no
  `off`, no `device_offline` event.

Consequence: the `from: unavailable, to: "on"` trigger in the adaptive-curve
automation **only fires on HA restarts**, never on real wall usage. Its
`last_triggered` history confirms this — every trigger is either
`Home Assistant starting` or a post-restart state change.

---

## Verification traps

The single most important thing to carry forward. Several hours were lost to
evidence that looked solid and was not.

1. **`zigbee.db` `attributes_cache_v15` is written on WRITE, not only on read.**
   Seeing `StartUpCurrentLevel = 254` there proves the bulb *ACKed* the command,
   not that it stored or honours it. This is the cache the user correctly warned
   did not represent the bulb's actual state.
2. **`number.set_value` updates the HA entity optimistically.** The entity
   reading `254` right after a write is an echo of your own command.
3. **The only trustworthy read is ZHA's startup interrogation** — visible in the
   recorder as a state row immediately after the entity leaves `unavailable`,
   and *before* the automation's 10s-delayed write lands. Restarting HA is
   currently the only way to force one.
4. **Even a true read-back does not prove behaviour.** The bulb stores 254 and
   still comes up dim. For this problem, **ground truth is a human looking at
   the room.** Ask.

---

## Unexplained anomaly worth a look

**HA has no brightness reading for any of these bulbs, ever.** All 200 most
recent `on` state rows for `light.third_reality_inc_3rcb01057z` have
`brightness=None` and `color_mode=None` — and both sibling bulbs (`_2`, `_3`)
are identical in this respect.

For a light whose registry `capabilities` advertise
`supported_color_modes: ['color_temp', 'xy']`, that is wrong. HA genuinely does
not know how bright these bulbs are at any point.

This did not cause the reported symptom and was not chased down. It may be a
ZHA attribute-reporting configuration issue, and it is plausibly related to why
so much of this system's state is untrustworthy. Worth investigating
independently.

---

## Direction decision needed

The user was asked to choose and opted for this handoff instead, so **this is
still open**. Do not start implementing without confirming the choice.

### Option A — stop cutting mains to the bulb *(recommended)*

Leave the wall switch permanently on and control the light via HA or a battery
Zigbee button; or replace the dumb switch with a smart relay that keeps the bulb
powered.

The entire problem class disappears: the bulb stays on the mesh, Adaptive
Lighting's `intercept` on off→on works exactly as designed, no polling is
needed, and the whole `StartUpCurrentLevel` workaround can be deleted. This is
the only option that is actually correct. Costs hardware or a habit change.

### Option B — periodic re-apply

A `time_pattern` automation re-applies the AL curve every N minutes while the
light is on (`adaptive_lighting.apply`, without `force`, so AL's
`manual_control` tracking still lets manual overrides stick).

**Read the tradeoff carefully before choosing this.** Worst case is N minutes of
wrong brightness after a flip. Making N small enough to feel acceptable in a
bathroom (~1 min) means *more* Zigbee traffic than the 90s Adaptive Lighting
interval that was deliberately disabled via `only_once: true` — see the long
comment in `config/configuration.yaml` explaining that it was flooding the log
with "device did not respond" errors. This option partially undoes a considered
earlier decision.

### Option C — accept it

Keep the two fixes, accept that the wall switch yields whatever the bulb
defaults to, and correct the now-disproven comments so the file stops asserting
false things.

---

## What changed

Uncommitted, all in `config/automations.yaml`:

1. Restored `target: "{{ 13 if is_state('sun.sun', 'below_horizon') else 254 }}"`
   (was pinned to `13`). Correct and worth keeping regardless of direction.
2. Added explicit `initial_state: true` to
   `bathroom_adaptive_lighting_reapply_on_available`, with a comment explaining
   why the key cannot simply be omitted.
3. Updated one stale sentence in the `KNOWN LIMITATION` comment block.

HA was restarted twice during the session (10:25, 10:51) to force attribute
read-backs. Config check passes.

---

## Cleanup backlog

- **Stale comments in `config/automations.yaml`:** the `KNOWN LIMITATION` block
  still describes `consider_unavailable_mains` as the 2-hour default (it is
  `60`), and the `VERIFIED WORKING` block asserts a conclusion this session
  disproved.
- **Orphaned entity:** `automation.bathroom_light_keep_power_on_brightness_dim`
  exists in `core.entity_registry`, currently `unavailable`, with no definition
  in `automations.yaml`. A previous automation whose literal purpose was keeping
  this bulb dim. Should be deleted from the registry.
- **The `OnLevel` (0x0011) write** in the sun automation was added as part of the
  now-moot "is OnLevel the culprit" diagnostic. Decide whether to keep it.
- `BOOT-PERFORMANCE.md` is untracked at the repo root (unrelated to this work).

---

## Working notes for the environment

- Config lives at `homeassistant/config/`, bind-mounted to `/config` in the
  `homeassistant` container. **Files are root-owned — edits need `sudo`.**
- **There is no `sqlite3` binary on this host.** Use `python3`'s `sqlite3`
  module.
- To read either database, copy **`.db`, `-wal`, and `-shm` together** to a
  scratch dir first, or you will read stale pre-WAL data.
  - Recorder: `config/home-assistant_v2.db` (state history, `automation_triggered`
    and `zha_event` events)
  - Zigbee: `config/zigbee.db` (`attributes_cache_v15` — see
    [Verification traps](#verification-traps))
- Useful `.storage` files: `core.entity_registry`, `core.device_registry`,
  `core.config_entries` (ZHA options live here).
- **No HA API token is available.** The user was offered the option of creating
  a long-lived token and declined in favour of restart-based read-backs.
  Obtaining one would make this dramatically easier — it would allow live state
  reads, forced ZHA attribute reads, and service calls without restarting HA.
- Config check: `docker exec homeassistant python -m homeassistant --script check_config -c /config`
