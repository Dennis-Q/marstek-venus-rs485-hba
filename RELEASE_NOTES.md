# HBA Release Notes

HBA version numbers follow the pattern **`{HBC-version}-r{N}`**. The HBC version indicates
which upstream release HBA is aligned with; the revision suffix (`r1`, `r2`, …) tracks
HBA-specific changes within that alignment. When a new HBC version is released and HBA
is updated to match, the revision resets to `r1`.

For upstream changes in each HBC version, see the
[HBC Release Notes](https://github.com/gitcodebob/marstek-venus-rs485-node-red/blob/main/RELEASE_NOTES.md).
This document covers HBA-specific changes only.

---

## v4.10.1-r3 — May 2026

### Dashboard

- **Version mismatch warning** — A full-width warning appears at the top of the dashboard
  when the loaded packages report a different version than the dashboard expects. Prompts
  to reload YAML. Requires `sensor.hba_version` (added in this release).

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
