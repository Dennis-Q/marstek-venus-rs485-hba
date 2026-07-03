# HBA Release Notes

HBA version numbers follow the pattern **`{HBC-version}-r{N}`**. The HBC version indicates
which upstream release HBA is aligned with; the revision suffix (`r1`, `r2`, …) tracks
HBA-specific changes within that alignment. When a new HBC version is released and HBA
is updated to match, the revision resets to `r1`.

For upstream changes in each HBC version, see the
[HBC Release Notes](https://github.com/gitcodebob/marstek-venus-rs485-node-red/blob/main/RELEASE_NOTES.md).
This document covers HBA-specific changes only.

---

## Unreleased — dev branch

Changes on `dev` that have not yet been merged to `main`.

### Added

- **Solar charge outlook sensor** (`sensor.hba_solar_charge_outlook`, in
  `hba_strategy_others.yaml`) — trigger-based template sensor that pre-computes net solar
  energy expected during today's remaining cheap price slots. Reads Solcast's
  `detailedForecast` attribute (list of 30-min `pv_estimate` periods) and integrates the
  proportional overlap with each cheap slot, then subtracts the configurable house load.
  Exposes six attributes: `solar_in_cheap_slots_kwh`, `needed_kwh`, `solar_covers_charge`
  (bool), `cheap_slots_remaining` (int), `last_cheap_slot_ts` (epoch), and
  `self_consume_deadline` (ISO UTC string). Falls back gracefully to state `"No data"` when
  the Solcast entity is unavailable; re-evaluates on every price-data change and every 15
  minutes. Resolution-aware: works correctly with both PT1H and PT15M price data.

- **Solar-aware house load** (`input_number.hba_strategy_solar_aware_house_load`) — new
  helper for the average household consumption to subtract from solar production when
  computing net solar available for charging (default: 400 W).

- **Solar-aware strategy: decision-tree rewrite** — `hba_strategy_solar_aware` now reads
  from `sensor.hba_solar_charge_outlook` instead of computing inline. Six-step decision
  tree (evaluated in order): (1) no cheap slots remain today → Self-consumption; (2) Solcast
  unavailable → Zero import (safe fallback); (3) total solar forecast < threshold →
  Self-consumption (not a solar day); (4) solar covers full charge need → Zero import; (5)
  current time before `self_consume_deadline` → Zero import (still time to export); (6) else
  → Self-consumption. Fixes a 15-min resolution bug where the old code used `slot_ts + 3600`
  to check slot expiry — now uses `as_timestamp(m.end)` from the marks array.

- **Overtemperature notification** — `automation.hba_notify_battery_overtemperature` fires
  when any `sensor.marstek_mX_internal_temperature` reaches ≥ 60 °C for 2 minutes (10 °C
  below BMS thermal-protection trip at ~70 °C). Sends a push notification (orange, high
  priority) and a persistent HA notification. `automation.hba_notify_battery_overtemperature_resolved`
  clears it when temperature drops below 55 °C for 5 minutes (5 °C hysteresis). All six
  battery slots are covered; M4–M6 never fire on 3-battery systems (sensors unavailable).

- **Entity health check** (`binary_sensor.hba_entity_health`, device_class `problem`) —
  polls ten critical entity IDs with `has_value()` every 5 minutes. Turns `on` (problem)
  when any are unavailable or missing; `missing_entity_ids` attribute lists them. Dashboard
  shows an `ha-alert error` banner at the top of the home view when the sensor is `on`.

- **Anti-windup: `assignable_discharge` variable** — `hba_strategy_self_consumption` now
  computes an `assignable_discharge` local variable that sums max discharge power only for
  batteries where `binary_sensor.hba_marstek_mX_not_responding` is `off`. The I-term clamp
  lower bound uses this instead of total max discharge power, so batteries in thermal
  protection or otherwise unresponsive do not inflate the anti-windup ceiling.

### Fixed

- **Frank Energie PT15M resolution support** — `sensor.hba_energy_prices_data` hardcoded
  `datapoints_per_hour = 1` and assumed 3600-second slot intervals. When the Frank Energie
  integration is configured to PT15M resolution (`select.frank_energie_settings_resolution = pt15m`),
  the sensor now detects the slot interval dynamically (96 entries/day at 15-min intervals)
  and adjusts all downstream calculations: `now_slot_ts` floors to `step_sec`; cheap/expensive
  slot caps scale by `pph`; `end_str` uses `step_sec` instead of 3600. The dashboard price
  table was already resolution-aware and required no changes.

- **Anti-windup Self-consumption I-term clamp** — I-term in `hba_strategy_self_consumption`
  is now clamped to `[−assignable_discharge, 0]`, where `assignable_discharge` excludes
  batteries currently marked `not_responding`. Previously the anti-windup used total max
  discharge power regardless of which batteries were actually responding.

- **PID reset on Zero import entry** — `automation.hba_zero_import_pid_reset` now also fires
  on entry to Zero import (covers the Solar-aware → Zero import path). Previously only Sell
  and Charge had on-entry PID resets.

- **Entity names and unique_ids** — all six `not_responding` binary sensors renamed to
  `"HBA Marstek M{N} Not Responding"` (entity_id `binary_sensor.hba_marstek_mX_not_responding`).
  `"Estimated Profit per kWh"` → `"HBA Estimated Profit per kWh"` (`sensor.hba_estimated_profit_per_kwh`).
  Three stale unique_ids corrected: `hba_active_strategy`, `hba_is_charging`, `hba_charge_goal_reached`.

---

## v4.10.1-r13 — June 2026

### Added

- **Battery not-responding sensors** — six `binary_sensor.hba_marstek_mX_not_responding`
  (delay_on: 30 s) detect when a configured battery stops tracking commanded power: RS485
  enabled + |commanded power| ≥ 300 W + |actual − commanded| > 15% sustained for 30+ s.
  Used as availability gates in the anti-windup clamp and to surface per-battery status in
  the Insights view.

- **RS485 mode mismatch sensor** — `binary_sensor.hba_rs485_mode_mismatch` (delay_on: 30 s)
  fires when the master mode is Full control but any configured battery has RS485 control
  disabled. Attribute `mismatched_batteries` lists the affected M-slots.

- **Notifications file** — all notification automations and the `script.hba_notify_dispatch`
  routing script moved to a dedicated `hba_notifications.yaml` package file, keeping
  `hba_strategies_core.yaml` focused on strategy dispatch.

---

## v4.10.1-r12 — June 2026

### Added

- **Solar-aware strategy** — new `hba_strategy_solar_aware` dispatches between *Zero import*
  and *Self-consumption* based on whether cheap hours remain today and the remaining solar
  forecast exceeds a configurable threshold (default 20 kWh).
  - **Before the cheap window on a sunny day** → Zero import: all solar production exports
    to the grid for maximum revenue. Charging happens during the configured cheap window
    (e.g. Dynamic v2 → Charge PV).
  - **After the cheap window, or on a cloudy day** → Self-consumption: batteries absorb
    solar surplus and cover evening loads.
  - Selectable as the default sub-strategy for Dynamic v2 and Timed; also available as a
    standalone strategy.
  - One new helper: `input_number.hba_strategy_solar_aware_forecast_threshold_kwh`
    (default: 20 kWh via `hba_apply_defaults`).
  - Cheap-hours detection is today-only — tomorrow's prices published mid-afternoon by
    Frank Energie don't incorrectly keep the strategy in Zero import mode all evening.
  - Falls back silently to Self-consumption when the solar forecast entity is not configured
    or when Dynamic v2 prices are unavailable.
  - Dashboard: conditional "Solar-aware settings →" navigation tile appears in the
    timed-dynamic and Dynamic v2 views when the default is set to Solar-aware; a dedicated
    section in Advanced Settings shows the threshold helper, a description, and a
    configuration warning when the solar entity or prices are missing.

### Fixed

- **Zero import: discharge spike on strategy switch** — Zero import now resets PID state
  (`input_number.hba_control_i_term` and `hba_control_pid_output` to 0) on entry. Previously,
  a stale I-term carried over from a prior charging sub-strategy (e.g. Dynamic v2 cheap →
  Charge PV, then transitioning to Zero import as the default) sat inside the
  `charge_disabled` anti-windup clamp range `[−assignable_discharge, 0]` and was not
  corrected within 1–2 cycles. This caused an immediate discharge spike the moment
  `charge_disabled` took effect — even when P1 was already near zero or about to go
  negative from solar surplus. The fix aligns Zero import's on-entry PID reset with the
  existing reset policy already applied by the Charge and Sell strategies.

---

## v4.10.1-r11 — June 2026

### Changed

- **Recorder: cell voltage sensors excluded** — `sensor.marstek_m*_battery_cell_*_voltage`
  added to `recorder: exclude:` entity_globs. With three batteries × 16 cells each, these
  generate ~90 000 state writes/day. Live values remain readable in Developer Tools; the
  useful chart target is `sensor.marstek_m*_battery_cell_voltage_delta` (min/max spread).
- **Recorder: raw Modbus sensors excluded** — `sensor.marstek_m*_forcible_charge_power_number`,
  `sensor.marstek_m*_forcible_discharge_power_number`, and `sensor.marstek_m*_inverter_state_number`
  added to `recorder: exclude:`. These are the raw Modbus register reads backing the already-excluded
  template entities and update on every poll (~38 000 writes/day combined).
- **Recorder: `select.marstek_m*_forcible_charge_discharge` restored** — removed from
  `recorder: exclude:` so that charge/discharge mode transitions are visible in history.
  The select changes state infrequently (only on direction changes) and is useful for
  diagnosing control-loop behaviour.
- **`input_number.hba_control_pid_output` intent clarified** — explicitly kept in the
  recorder (useful for PID chart history) and excluded only from the logbook. The previous
  "uncomment to exclude" comment was ambiguous and has been replaced with an explanatory note.

---

## v4.10.1-r10 — June 2026

### Added

- **Logbook noise suppression** — new `logbook: exclude:` block in `hba_helpers.yaml`
  hides all high-frequency HBA/Marstek control-loop entities (battery power/mode selects,
  scripts, PID state, idle timestamps, flow-trace helpers) from the HA logbook. Without
  this, the logbook accumulates ~800 000 entries/day from internal battery control calls.
- **Recorder: Marstek control outputs now excluded** — `number.marstek_m*_forcible_charge_power`,
  `number.marstek_m*_forcible_discharge_power`, and `select.marstek_m*_forcible_charge_discharge`
  added to `recorder: exclude:`. These were generating ~136 000 state changes/day with no
  diagnostic value.
- **`install.sh`: logbook Modbus domain check** — installer now warns if `configuration.yaml`
  is missing the Modbus domain logbook exclusion and shows the snippet to add. The exclusion
  is kept out of `hba_helpers.yaml` itself because other packages (e.g. EV charger) also use
  Modbus and should not be silently suppressed.

---

## v4.10.1-r9 — June 2026

### Fixed

- **`hba_set_batteries` default branch: missing idle-timer hold** — when a battery's PID share
  dropped to 0 (e.g. total load < priority battery max), the default branch immediately sent a
  hard stop (`select = stop`) with no idle-timer check. The battery relay disengaged on the very
  next cycle. Fixed: the default branch now mirrors `getStopSolution()` from Node-RED — sends a
  1 W directed hold while `time_idle < idle_time`, hard stop only after the timer expires.

- **Write-symmetry: both power registers always equal** — in all active and idle-hold paths,
  `forcible_charge_power` and `forcible_discharge_power` are now written to the same value
  (`share` W or 1 W). Previously the non-active register was zeroed, risking relay disengagement
  if the battery processed the 0 W write before the `select` mode change. Only full stop and
  idle-stop (`select = stop`) paths still write 0 to both registers — those are the only
  intentional relay-disconnect points. Matches HBC behaviour.

- **Direction-flip guard: redirect to previous direction** — when the direction-flip guard fires
  (PID wants to flip charge↔discharge but magnitude < hysteresis), the output is now mirrored
  into the previous direction at the same magnitude (`|output| × prev_sign`) instead of being
  zeroed. Zeroing caused an unnecessary 1 W idle hold on every boundary crossing; the redirected
  output keeps the battery actively working near the setpoint. Matches Node-RED HBC behaviour.

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
