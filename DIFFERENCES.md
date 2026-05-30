# HBA vs HBC — Differences

This document covers how Home Battery Assistant (HBA) differs from the original
[Home Battery Control (HBC)](https://github.com/gitcodebob/marstek-venus-rs485-node-red)
project. It is aimed at HBC users who want to understand what changed, and at anyone
curious about the design trade-offs made in the HA-native port.

For HBC users installing HBA alongside HBC, see also the
[For existing HBC users](README.md#for-existing-hbc-users) section in the README.

---

## The fundamental difference: no Node-RED

HBC runs its control logic in Node-RED flows. HBA replaces those flows entirely with
native HA automations and scripts. From the battery's perspective, the commands are
identical — the same Modbus writes, the same strategy logic, the same PID algorithm.
What changes is where that logic lives.

Practical consequences:

- **No Node-RED installation required.** The only runtime is Home Assistant itself.
- **State survives restarts.** Node-RED stores PID state (I-term, timestamps, etc.) in
  flow context, which is lost when Node-RED restarts. HBA stores everything in
  `input_number` and `input_datetime` helpers, which HA restores from `.storage/` on
  every restart. The I-term in particular — losing it means the battery starts from zero
  integration and overshoots until it builds up again. HBA never loses it.
- **No rate limiter.** HBC has an "operational thresholds" gate that skips the PID cycle
  when P1 changes less than 20 W and less than 2% from the previous reading. HBA has
  no equivalent — it runs on every P1 update (subject only to the 15 W deadband). This
  is the most significant behavioural difference; see [PID behaviour](#pid-behaviour) below.

---

## PID behaviour

The PID algorithm is a direct port of HBC's implementation. The parameters (Kp, Ki, Kd,
error dampening, output dampening, hysteresis) are identical in meaning and work the same
way. However, one structural difference affects how the controller feels in practice.

### HBA runs the integrator more often

HBC skips the entire PID cycle — including the integrator — when P1 is stable (< 20 W
and < 2% change from the previous reading). HBA has no such gate; it runs on every P1
update. With a 1 s DSMR meter, this means HBA can accumulate I-term up to 20× more
frequently during a stable period than HBC does.

**Effect:** the same Ki value is more aggressive in HBA than in HBC, particularly
during stable, low-error periods where the integrator has time to wind up.

**If you are migrating PID values from HBC:** start with a lower Ki and tune from there.
The [docs.homebatterycontrol.com/04-setup-self-consumption](https://docs.homebatterycontrol.com/04-setup-self-consumption)
page covers tuning in general. The HBA-specific starting point is to halve your HBC Ki
and observe.

### P1 update rate matters

HBA runs at whatever rate the P1 sensor updates. DSMR 5.0 meters update every 1 s;
older meters may update every 3–10 s. At slower update rates the integrator accumulates
more slowly and HBA behaves more conservatively — closer to HBC's behaviour. The Ki
warning above is most relevant for 1 s meters.

### Built-in presets

**Very safe**, **Safe**, and **Regular (original HBC)** are carried over from HBC.
HBA introduces a new **Regular** preset with values that appear to work better in
practice — it is still under review. The original HBC Regular preset is preserved
as **Regular (original HBC)**. Treat all presets as starting points, not tuned
recommendations.

### Other PID differences

| Aspect | HBC | HBA |
|---|---|---|
| Derivative term | On measurement: `Kd × -(P1 − P1_last)` | On error: `Kd × (err − prev_err)` — mathematically equivalent for a constant setpoint |
| Direction-flip guard when triggered | Locks to previous direction at full PID magnitude | Sets output to 0; battery idles at 1 W hold |
| SoC cutoff boundary | Exact: `soc >= soc_max` | ±0.5% buffer to prevent relay chatter at the exact boundary |

---

## Feature additions

These are features HBA has that are not in HBC:

| Feature | Notes |
|---|---|
| **Battery connectivity validation** | Onboarding wizard verifies Modbus communication for each battery before going live |
| **Availability gates** | Template `select` entities on m2–m6 gate Modbus polling behind `hba_battery_count` — prevents log flooding when fewer than 6 batteries are configured |
| **Conflict detection** | Fires automatically if HBA and HBC both end up in Full control simultaneously; disables HBA and creates a persistent HA notification |
| **HBC coexistence panel** | Dashboard buttons to hand control between HBA and HBC (Take control / Yield to HBC) |
| **Configurable Frank Energie entity ID** | Set in Advanced Settings — see [Dynamic pricing](#dynamic-pricing) below |
| **Configurable slow-charge thresholds** | HBC hard-codes the near-full slowdown at ≥ 95% → 1500 W and ≥ 99% → 1000 W. HBA exposes both SoC thresholds *and* both power limits as individual helpers in Advanced Settings — defaults match HBC, but you can change either pair or disable a step by setting its power limit to 0 |
| **Reset to defaults button** | `script.hba_apply_defaults` is surfaced as a one-click button in onboarding Step 1 and again in Advanced Settings. Resets every user-configurable helper to a sensible starting value without touching internal PID state. HBC has no equivalent factory reset |
| **Version mismatch banner** | The dashboard compares `sensor.hba_version` against a hard-coded version string baked into the YAML and warns when they diverge — i.e. when only one half of the install was updated. Prevents silent drift between dashboard and backend |
| **Battery offline banner** | `binary_sensor.hba_any_battery_offline` drives a banner on the overview that lists which M-slots dropped off Modbus. HBC has no offline detection at the dashboard level |
| **Onboarding Step 6** | HBA's onboarding ends with an explicit "Set Master Battery Control to Full control" step plus a button to hide the wizard once the user is up and running. HBC's onboarding ends at Step 5 |
| **Insights view** | See [Insights view](#insights-view) below for what it actually contains — it's substantially richer than a single flow-trace card |
| **Peak shaving — all strategies** | HBC applies peak shaving only in the partials flow (Charge PV, Zero import, Standby). HBA integrates it into `self_consumption`, so Timed and Dynamic also inherit it automatically |
| **"Disabled" master mode** | HBA adds a fourth option to the Master Battery Mode dropdown alongside the three HBC carries (Manual / Marstek / Full): **Disabled**. Picking it turns off `automation.hba_control_loop_p1_meter_triggered` entirely — no more P1-triggered control loop firing (no ~1 Hz trigger overhead, no dispatch attempts). It also sends a one-shot stop to every reachable battery first (zero force-power + select `stop`, while RS485 is still enabled) so nothing keeps charging/discharging at the last commanded level. Deliberately does NOT change `user_work_mode` or `rs485_control_mode` — it's a pure soft kill-switch; whatever state the previous mode left the batteries in stays. Re-selecting any other mode flips the control loop automation back on. Useful for staging instances, troubleshooting, or any time you want HBA "off" without renaming Modbus YAML files |

---

## Dynamic pricing

Both Dynamic v1 and v2 are direct ports of HBC's algorithms — logic, marks format, and
sub-strategy dispatch are identical. The differences are in implementation and a small
number of HBA-specific additions.

### Configurable Frank Energie entity ID

HBC hardcodes the Frank Energie sensor entity ID in the Node-RED flow. HBA makes it
configurable in Advanced Settings (default matches HBC:
`sensor.frank_energie_prijzen_gemiddelde_elektriciteitsprijs_alle_uren_all_in`).

If your integration uses English entity names or you prefer market price over all-in,
update the entity ID there — for example:
- `sensor.frank_energie_prices_average_electricity_price_all_hours_all_in` (English, all-in)
- `sensor.frank_energie_prices_current_electricity_market_price` (English, market price ex taxes)

This applies to both v1 and v2.

---

## Dashboard differences

### Insights view

HBC's Insights view shows a live Node-RED flow trace via `sensor.home_battery_control_trace`
and a log table via `sensor.home_battery_control_log` — both Node-RED-only sensors.

HBA replaces this with a custom HA-native view that is substantially more detailed than
HBC's. The cards on it:

- **Flows used** — indented tree rendered from `input_text.hba_strategy_active_flow`
  (e.g. `Control loop → Dynamic → Charge PV → Self-consumption (charge only)`)
- **Controller state** — grid power vs setpoint, current error, deadband indicator,
  P1 sensor age, peak-shaving clamp status per side (🟢/🔴), EV-stop entity state,
  and the current PID phase from `input_text.hba_control_cycle_state` (Deadband,
  Direction guard, Active, Idle hold, Idle stop)
- **System state** — `binary_sensor.hba_is_charging`, `binary_sensor.hba_charge_goal_reached`,
  current priority battery
- **Battery connectivity** — per-battery 🟢/🔴 with `inverter_state`
- **Battery aggregates** — measured total power alongside `sensor.hba_total_commanded_power`
  (the last value HBA wrote to the batteries), plus max charge/discharge and time remaining
- **Power history** — 1-hour graph of P1 vs total battery power
- **PID controller breakdown** *(debug mode)* — P/I/D term values with gains and the I-term
  anti-windup cap, plus a per-battery load-distribution dump showing SoC, cutoffs, mode,
  current command, slow-charge cap warnings, and per-battery idle timer state
- **Dynamic pricing now** *(debug mode)* — `mark_now`, cheap/expensive threshold-met flags,
  the dispatched sub-strategy, and the active time windows

All of the above update at P1 frequency. Debug-only cards are gated behind
`input_boolean.hba_control_is_debug_mode` to avoid history bloat at ~1 Hz.

### Dynamic v2 price marks table — vertical layout

HBC's price marks table uses a horizontal layout (one column per hour). HBA uses a
vertical layout — one row per hour, today and tomorrow side by side:

![Dynamic v2 price marks table](docs/screenshots/dynamic_v2_price_marks_table.png)

This scales better for 24+ rows and avoids horizontal scrolling. The data shown is
identical; the layout is intentionally different.

### Lab features view

HBA's Lab features view (Dynamic v2 price marks table + 48-hour ApexCharts bar chart)
is always navigable from the dashboard. HBC gates it on the presence of the
`update.cheapest_energy_hours_update` entity, which is not available in all setups.

---

## Known gaps vs HBC

These are HBC behaviours that are not yet implemented in HBA:

| Gap | HBC behaviour | HBA current behaviour |
|---|---|---|
| **Reverse-discharge priority** | When the priority cycle interval is not "Auto balance", HBC reverses the battery array during discharge — so the last-in-priority battery discharges first, spreading wear across batteries | HBA always processes batteries in priority-first order for both charge and discharge |

