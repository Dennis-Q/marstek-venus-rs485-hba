# HBA Release Notes

HBA version numbers follow the pattern **`{HBC-version}-r{N}`**. The HBC version indicates
which upstream release HBA is aligned with; the revision suffix (`r1`, `r2`, …) tracks
HBA-specific changes within that alignment. When a new HBC version is released and HBA
is updated to match, the revision resets to `r1`.

For upstream changes in each HBC version, see the
[HBC Release Notes](https://github.com/gitcodebob/marstek-venus-rs485-node-red/blob/main/RELEASE_NOTES.md).
This document covers HBA-specific changes only.

---

## v4.10.1-r8 — June 2026

### Breaking: entity renames

Unit suffixes removed from entity IDs for consistency — all other HBA helpers omit the unit
from the ID. Update any automations or templates that reference these directly.

| Old | New |
|---|---|
| `input_number.hba_target_grid_consumption_in_w` | `input_number.hba_target_grid_consumption` |
| `input_number.hba_control_hysteresis_in_w` | `input_number.hba_control_hysteresis` |
| `input_number.hba_battery_assist_min_soc_pct` | `input_number.hba_battery_assist_min_soc` |

`sensor.hba_total_battery_power` unique_id also updated (`hba_total_battery_power_in_w` →
`hba_total_battery_power`) — HA will treat this as a new entity and history will not be linked.

### New features

- **"Battery Assisted EV Charging" renamed to "Timed EV Charge"** — clearer name; entity IDs
  (`hba_battery_assist_*`) are unchanged to preserve HA history.

- **Timed EV Charge: car connected condition** — new optional `input_text.hba_battery_assist_car_connected_entity`.
  When set, `binary_sensor.hba_battery_assist_active` only activates if that entity is `on`.
  Leave empty to ignore (default).

- **Timed EV Charge: max discharge power** — new `input_number.hba_battery_assist_max_discharge_power`
  caps discharge power during the window. `0` (default) means use the battery hardware maximum.
  Range 0–25 000 W to cover up to 6 batteries at single-phase max.

- **Timed EV Charge: reserved energy sensor** — new `sensor.hba_battery_assist_reserved_energy`
  shows how much energy the home can still use after assist stops: `max(0, min_soc − cutoff) × capacity`
  per battery. Reads `0 kWh` when `min_soc ≤ cutoff` (hardware stops at the same point).

- **Timed EV Charge: PID reset** — new `automation.hba_battery_assist_pid_reset` clears
  `input_number.hba_control_pid_output` to 0 when assist starts, stops, or when the
  self-consumption overflow guard releases while assist is active.

- **Notifications framework** — `script.hba_notify_dispatch` routes notifications to a
  configurable legacy `notify.mobile_app_*` service, falling back to persistent notifications
  when the helper is empty. `binary_sensor.hba_notify_target_invalid` validates the configured
  target; `automation.hba_notify_target_validation` surfaces a persistent notification when
  misconfigured. New `input_boolean.hba_notifications_enabled` master switch.

### Fixed

- **`hba_grid_exporting_sustained` overflow guard sign error** — battery power condition was
  `< -500` but `sensor.hba_total_battery_power` is positive when discharging. Changed to `> 500`.

- **Notify validator: modern notify entities rejected** — `notify.xyz` names that correspond to
  a registered HA notify entity silently fail as legacy service calls. The validator now flags
  them as invalid using a `notify.mobile_app_` prefix check (more reliable than the previous
  `states.notify` lookup, which HA may not re-evaluate when notify entities change).
  `available_notify_services` attribute correctly shows `notify.mobile_app_*` legacy service names
  (previous `map('replace', ...)` call was silently a no-op in HA's Jinja2).

- **`sensor.hba_battery_assist_reserved_energy` formula** — hardware-locked energy (below
  `discharging_cutoff_capacity`) was included, making the sensor misleadingly high when
  `min_soc ≤ cutoff`. Fixed to `max(0, min_soc − cutoff) × capacity`.

### Changed

- **Flow label rename** — `Battery assist → EV discharge` → `Timed EV charge → Discharge to EV`.
  Overflow label: `Timed EV charge — Grid overflow → Self-consumption`.
- **Label consistency** — `Standby / peak shave` sub-label casing consistently lowercase everywhere.

### Dashboard

- **EV Charge view** — EV Stop Trigger and Timed EV Charge combined into a single "EV Charge"
  view (path: `ev-charge`). EV Stop Trigger is shown first; Timed EV Charge below it. Advanced
  Settings has two subtitle nav links (EV Stop Trigger, Timed EV Charge) both pointing to this view.
- **Notifications view** — moved out of Advanced Settings into its own view (tab). Notes it is
  an HBA-specific feature not part of HBC.
- **Auto-entities list of notification automations** — Notifications view shows all
  `automation.hba_*notif*` automations with enable/disable toggles.
- **Compact defaults buttons** — "Apply section defaults" and "Reset to defaults" are now
  inline entities rows with `last-triggered` timestamp.
- **Timed EV Charge section** — shows average SoC, reserved energy, and max discharge power.
- **Send test notification** — inline entities row instead of full-width button card.

---

## v4.10.1-r7 — June 2026

### Fixed

- **`hba_grid_exporting_sustained` overflow guard sign error** — the battery power
  condition was `< -500` but `sensor.hba_total_battery_power` is positive when
  discharging. Changed to `> 500`. Previously the overflow guard in battery assist mode
  never triggered, allowing batteries to discharge into the grid unchecked.

---

## v4.10.1-r6 — June 2026

### New feature: Battery Assisted EV Charging

Discharges batteries during a configured time window to direct that capacity to an EV
charger — useful when you have excess battery reserves and want to maximize EV charge
before the car is needed.

**New helpers:**
- `input_boolean.hba_battery_assist_enabled` — master on/off toggle
- `input_datetime.hba_battery_assist_start_time` / `hba_battery_assist_end_time` — discharge window
- `input_number.hba_battery_assist_min_soc` — SoC floor; assist stops when average SoC drops below this

**New sensors:**
- `sensor.hba_average_battery_soc` — average SoC across all configured batteries (also used internally by the Charge and Sell strategy goal checks, replacing inline loops)
- `binary_sensor.hba_battery_assist_active` — true when enabled, within the time window, and SoC above the floor; use this in an automation to start/stop EV charging
- `binary_sensor.hba_grid_exporting_sustained` — true when grid export exceeds 1 kW sustained for 2+ minutes with batteries discharging; used as an overflow guard to fall back to self-consumption

**Strategy dispatch:** the battery assist branch is evaluated above the EV stop trigger in `hba_run_strategy`. When active, batteries discharge at max power via `hba_set_batteries`; falls back to self-consumption if the overflow guard fires.

**Notification:** `automation.hba_unexpected_export_notify` fires a persistent notification when the grid exports unexpectedly (overflow guard active but battery assist is off).

**Dashboard:** new Battery Assisted EV Charging section in Advanced Settings with all controls and status tiles.

---

## v4.10.1-r5 — June 2026

### Improvements

- **Packages moved to `packages/hba/` subdirectory** — HBA files now live under
  `packages/hba/` instead of directly in `packages/`. The installer migrates
  existing installs automatically (asks before moving old files). No HA config
  change required — `!include_dir_named packages` recurses into subdirectories.

---

## v4.10.1-r4 — May 2026

### Improvements

- **Reduced database writes** — HBA scripts, the control loop automation, per-battery
  idle timestamps, and flow-trace helpers are now excluded from the recorder. Eliminates
  tens of thousands of low-value state writes per day.

---

## v4.10.1-r3 — May 2026

### Bug fixes

- **Auto balance priority rotation** — Rotation did not occur under certain circumstances
  (e.g. all batteries charging at mid-range SoC). Fixed to rotate every 30 minutes
  as intended.

### Dashboard

- **Version mismatch warning** — A full-width error banner appears at the top of the
  dashboard when the loaded packages report a different version than the dashboard expects.
  Prompts to reload YAML. Requires `sensor.hba_version` (added in this release).

- **View headers updated** — All view headers now show the current HBA version. Previously
  stuck on v4.10.0-r1.

### New entities

- `sensor.hba_version` — reports the version of the currently loaded HBA packages.
  Used by the dashboard mismatch check; also useful to verify what version is running.

---

## v4.10.1-r2 — May 2026

Minor fixes to reduce log noise and correct HA validation warnings.

### Fixes

- **Solar forecast sensors: invalid `state_class`** — `device_class: energy` requires
  `state_class: total` or `total_increasing`, not `measurement`. Fixed on all four
  solar forecast sensors (`hba_solar_forecast_today/tomorrow` and the surplus variants).

- **Control loop log noise** — `mode: single` on the P1-triggered control loop logs
  "Already running" on every dropped trigger (~1/s during normal operation). Added
  `max_exceeded: silent` to suppress it — behaviour is unchanged, drops still occur.

---

## v4.10.1-r1 — May 2026

Aligns with HBC v4.10.1. Neither bug fixed in HBC v4.10.1 affects HBA — the midnight
price rollover and decimal kWh display issues were already handled correctly. This release
ships two bugs found during initial testing.

### Bug fixes

- **Multi-battery distribution: only priority battery received power** *(critical)* —
  A Jinja2 for-loop scoping bug in `hba_set_batteries` caused only the priority battery to
  receive charge or discharge commands; all other batteries always got 0 W. Affected all
  strategies (Sell, Charge, Self-consumption, etc.).

- **Auto balance cycling every ~75 min instead of 30 min** — The rotation check ran every
  15 min with a hard 1-hour gate, giving worst-case 75-min intervals. Aligned with original
  HBC: checks every 30 min, no time gate (the SoC-limit condition prevents redundant rotations).

### Dashboard

- **Idle state label** — Batteries past their idle timeout now show "⏸ resting" instead of
  "⏹ timeout" in the Insights debug view. The stop state after `idle_time` expires is
  expected; the previous label looked like an error.

---

## v4.10.0-r1 — May 2026

Initial release of Home Battery Assistant. Full native HA port of HBC v4.10.0 —
no Node-RED required.

### Strategies

All ten strategies from HBC v4.10.0 are implemented:

| Strategy | Notes |
|---|---|
| Self-consumption | PID controller, full parameter set |
| Charge PV | Solar-only charging |
| Zero import | Discharge to cover loads, no grid import |
| Standby / peak shave | Soft idle + activates at grid limit breach |
| Charge | Goal-based (full / SoC% / energy kWh / solar forecast) |
| Sell | Goal-based (empty / SoC% / energy kWh) |
| Timed | Up to 3 configurable time windows + default |
| Dynamic v1 | Contiguous window via HACS Cheapest Energy Hours |
| Dynamic v2 | Extreme-Pair Matching; aligned with HBC's "Dynamic 2" |
| Full stop | Stops all batteries, resets PID I-term |

### PID controller
- Kp, Ki, Kd, error dampening, output dampening, hysteresis
- Three-layer oscillation guard: deadband → direction-flip guard → idle hold
- Per-battery idle timers (relay disconnect after configurable idle period)
- I-term stored in `input_number` — survives HA restart (Node-RED loses it on restart)
- Anti-windup: I-term clamped to assignable battery power / Ki
- Four built-in presets: Very safe, Safe, Regular, Regular (original HBC)
  — carried over from HBC and still under review for HBA's implementation
- Hysteresis guidance in Advanced Settings: recommended value is Kp × 50 W

### Dynamic pricing
- v1: HACS Cheapest Energy Hours, all supported price sources
- v2: Extreme-Pair Matching per calendar day, two-pointer algorithm
- Frank Energie sensor entity ID configurable in Advanced Settings
- Threshold binary sensors (`hba_dynamic_cheap_threshold_met` / `…expensive_threshold_met`)
- Estimated profit sensor (shown when expensive strategy = Sell)

### Multi-battery
- Up to 6 Marstek Venus E batteries via Modbus TCP
- Availability gates on unconfigured batteries — no log flooding at low battery counts
- Priority-first load distribution with configurable rotation (Never / Daily / Weekly / Auto)
- Per-battery SoC cutoffs and configurable slow-charge limits near full SoC
- `marstek_m4–m6_modbus_tcp.yaml` generated from fonske's m2 (fonske publishes m1–m3 only)

### Solar forecast
- Solar forecast charge goal (Solcast integration)
- Distribution card: Available / Grid charge / Solar charge portions
- Configurable house consumption reserve (`hba_solar_reserved_for_house`)

### Dashboard
- Close port of the original HBC dashboard (all views, all features)
- Insights view: live flow tracing via `input_text` helpers (replaces Node-RED context sensors)
- Onboarding wizard with Modbus connectivity check per battery
- Lab features view: Dynamic v2 price marks table + 48h ApexCharts bar chart
- HBA ↔ HBC coexistence panel: handoff buttons + conflict guard

### HBA-specific additions
- **Install script** (`install.sh`): one-line install and update via `curl | bash`;
  handles first-install vs update logic, asks about optional files, warns on
  `configuration.yaml` gaps. Supports `HBA_VERSION=` for pinned installs.
- **HBC coexistence** (`hba_hbc_coexistence.yaml`): Take control / Yield to HBC buttons,
  conflict guard (fires if both run in Full control simultaneously)
- **Factory defaults script** (`hba_apply_defaults`): sets all helpers to sensible
  starting values; safe to re-run; documented in [DEFAULTS.md](DEFAULTS.md)
- **`initial:` removed** from all user-configurable helpers — HA now restores from
  `.storage/` on restart instead of resetting to coded defaults

### Installation (fresh)
See [README — Installation](README.md#installation) for full instructions.
Quick start (from `/config`):
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/marstek-venus-rs485-hba/main/install.sh)
```
