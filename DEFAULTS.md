# HBA Factory Defaults — v4.10.1-r20

All values set by `script.hba_apply_defaults`. Run once after fresh install via
Developer Tools → Services → `script.turn_on` → `script.hba_apply_defaults`.
**Re-running resets all user-configurable values to the defaults listed here** — including
PID tuning, strategy settings, and SoC cutoffs. It never touches internal state
(i_term, timestamps, etc.), so the controller continues from where it left off.

## Master / Strategy

| Helper | Default |
|---|---|
| `input_select.hba_marstek_master_battery_mode` | `Full control` |
| `input_select.hba_strategy` | `Self-consumption` |
| `input_number.hba_battery_count` | `1` |
| `input_number.hba_control_prioritize_battery` | `1` |
| `input_select.hba_control_priority_change_interval` | `Auto balance` |

## PID Parameters

apply_defaults sets the preset selector AND the individual values. The individual values
are always consistent with "Very safe" so the preset selector is not misleading.

| Helper | Default | Notes |
|---|---|---|
| `input_select.hba_control_pid_presets` | `Very safe` | Deliberately conservative for an unverified install. **Switch to `Regular` once the batteries are confirmed responding** — it is the validated operating point and roughly halves the grid energy per disturbance. |
| `input_number.hba_target_grid_consumption` | `0` W | Keep grid import at 0 W |
| `input_number.hba_control_kp` | `0.35` | Matches Very safe preset |
| `input_number.hba_control_ki` | `0.1` | Matches Very safe preset |
| `input_number.hba_control_kd` | `0.1` | Matches Very safe preset |
| `input_number.hba_control_pid_output_dampening` | `10` % | Matches Very safe preset |
| `input_number.hba_control_error_signal_dampening` | `20` % | Matches Very safe preset |
| `input_number.hba_control_hysteresis` | `20` W | Direction-flip guard threshold |
| `input_number.hba_control_idle_time` | `5` min | Per-battery idle hold before relay disconnect |
| `input_number.hba_control_write_refresh_secs` | `30` s | Re-send an unchanged battery command at least this often. Identical commands in between skip their three Modbus writes (~150 ms each), which roughly halves the control-loop period under load. `0` disables de-duplication and writes every cycle. |

### PID Presets

> ⚠️ **Do not copy PID values from the Node-RED HBC project.** They will not behave the same
> here, and the difference is large.
>
> HBC gates its PID behind a rate limiter — it only runs the pipeline when grid power has
> moved **more than 20 W *and* more than 2 %**, and it blocks the next cycle entirely after a
> slow one. HBA runs the PID on **every** `sensor.p1_meter_power` update, subject only to a
> 15 W deadband. The integrator therefore accumulates far more often here, so the same Ki is
> dramatically more aggressive in HBA than in HBC. HBC's published gains (e.g. Ki 0.4,
> Kd 0.8) are not transferable, and the former "Regular (original HBC)" preset has been
> removed for that reason.
>
> The same applies in reverse: do not report HBA gains as HBC settings.

The four everyday presets share **Kp 0.35 / Kd 0.1 / error damping 20 % / output damping
10 %** and differ **only in Ki**, because **Kp 0.35 and the 20 %/10 % damping are both measured
optima** — bracketed on both sides on production against a real 2250 W load, Ki held at 0.22:

| | Kp 0.20 | **Kp 0.35** | Kp 0.55 |
|---|---|---|---|
| peak (+3 s) | 1602 W | 1420 W | 1304 W |
| tail (+10 s) | 54 W | 156 W | 349 W |
| **cost per disturbance** | 0.74 ct | **0.61 ct** | 0.71 ct |

Lower Kp gives a higher peak but a faster tail; higher Kp the reverse. Both cost more overall,
so the presets leave Kp alone and vary only Ki.

If transient **peaks** matter to you more than energy, **Kp is the wrong lever** — the exchange
rate there is a poor one, roughly 8 % lower peak for 16 % higher cost per disturbance (Kp 0.55).
Use the `Low peak (grid limit)` preset instead; it removes output damping, which buys a bigger
peak reduction (~10 %) for nothing. See below.

**The damping values were tested the same way** and are not arbitrary. Running 0 %/0 % for a
night against the same 2250 W load left cost per disturbance unchanged (0.63 vs 0.65 ct,
p = 0.57) and write volume unchanged (1.47 vs 1.42 Modbus writes per cycle), but tripled the
residual error 8 s after the step — **136 W → 441 W, p = 0.008**, with every pulse in the
undamped arm worse than the damped median. Two later nights removed the **output** damping
alone and the tail did *not* suffer, which pins that result on the **error** damping: it is a
low-pass on a grid signal carrying ~140 W of noise, and without it the integrator accumulates
that noise. **Leave error damping at 20 %.** Output damping is the one value with a documented
reason to change — see `Low peak (grid limit)` below.

| Preset | Ki | Character | Measured on an 863 W step |
|---|---|---|---|
| Very safe | 0.10 | Calmest, least battery activity | 6.1 Wh, ~38 s to settle |
| Safe | 0.15 | Noticeably slower tail | 4.4 Wh |
| **Regular** *(default)* | **0.22** | **Validated on production** | 3.7 Wh. Against a real 2.25 kW step: residual **143 W at +8 s**, zero setpoint crossings |
| Responsive | 0.30 | Fastest measured | 3.2 Wh. Untested against 2.25 kW steps — may overshoot, as overshoot scales with step size |

#### `Low peak (grid limit)` — the one preset that is not a Ki step

`Kp 0.35 / Ki 0.22 / Kd 0.1 / error damping 20 % / **output damping 0 %**` — Regular's gains
with output damping removed.

Measured on production over **two nights** (2026-08-06 and 08-07) against Regular on the same
2250 W load, with the two arms **interleaved pulse by pulse** so SoC, weather and household
drift hit both equally, and with the arm order reversed on the second night so a
first-vs-second-in-cycle artefact would have shown up as a sign flip. It did not:

| | Regular (10 %) | Low peak (0 %) | |
|---|---|---|---|
| **peak, +3 s**, night 1 (n = 6/7) | 1630 W | 1320 W | −19 % |
| **peak, +3 s**, night 2 (n = 8/8) | 1410 W | 1320 W | −7 % |
| **peak, +3 s**, both nights (29 pulses) | | | **−10 %, p = 0.0008** (stratified by night) |
| tail, +8 s | 260 W | 236 W | n.s. — unharmed |
| cost per disturbance | 0.71 ct | 0.64 ct | n.s. — **no penalty** |

Expect roughly **10 % off the instantaneous peak**, not the 19 % the first night suggested. The
difference between the two nights is entirely on the *Regular* side — Low peak measured 1320 W
both nights, which looks like a floor set by sensing dead time and the inverter's ramp rate,
while Regular varies with conditions. So the gain is largest exactly when the loop is otherwise
sluggish.

Output damping smooths the commanded power, so removing it lets the batteries swing at the
disturbance sooner. The cost that theory predicts — a slower, dirtier convergence — did not
show up: the tail was, if anything, slightly better, and setpoint crossings stayed at 0 in
both arms.

> **Read "peak" as *instantaneous*.** This preset shaves a few seconds of excursion. It does
> **nothing** for the Dutch *capaciteitstarief* or any tariff billed on the monthly maximum of
> **15-minute averages** — 300 W lasting 3 s moves a 15-minute average by under 1 W. Use
> `power_limit_import` for that. `Low peak` is for a **hard instantaneous limit**: a fuse or a
> contracted connection cap, where a 1600 W transient is roughly 7 A on a phase.

> Regular remains the default: `Low peak` buys a few seconds of lower excursion and nothing
> else, so it is only worth selecting if an instantaneous limit actually binds.

> **These Ki values assume a ~1.1 s control loop**, i.e. Modbus write de-duplication enabled
> (`input_number.hba_control_write_refresh_secs` > 0, v4.10.1-r15+). With de-duplication off
> the loop runs at ~2.2 s and the integrator accumulates half as fast per second, so every
> preset behaves roughly one step slower than its name suggests.


## Peak Shaving

| Helper | Default |
|---|---|
| `input_boolean.hba_control_has_power_limit_import` | `off` |
| `input_boolean.hba_control_has_power_limit_export` | `off` |
| `input_number.hba_control_power_limit_import` | `5000` W |
| `input_number.hba_control_power_limit_export` | `5000` W |

## Slow Charge Limits

Reduces max charge power near full SoC to protect battery cells. Set a limit to `0` to disable that threshold.

| Helper | Default |
|---|---|
| `input_number.hba_control_slow_charge_soc_threshold_1` | `95` % |
| `input_number.hba_control_slow_charge_power_limit_1` | `1500` W |
| `input_number.hba_control_slow_charge_soc_threshold_2` | `99` % |
| `input_number.hba_control_slow_charge_power_limit_2` | `1000` W |

## Charge Strategy

| Helper | Default | Notes |
|---|---|---|
| `input_select.hba_strategy_charge_goal` | `batteries are full` | |
| `input_select.hba_strategy_charge_goal_reached` | `Full stop` | |
| `input_number.hba_strategy_charge_target_soc` | `90` % | Used when goal = state of charge |
| `input_number.hba_strategy_charge_target_energy` | `5` kWh | Used when goal = energy reserve |
| `input_number.hba_solar_reserved_for_house` | `0` kWh | Expected house consumption during daylight hours; solar surplus beyond this charges the battery |

## Sell Strategy

| Helper | Default |
|---|---|
| `input_select.hba_strategy_sell_goal` | `batteries are empty` |
| `input_select.hba_strategy_sell_goal_reached` | `Full stop` |
| `input_number.hba_strategy_sell_target_soc` | `20` % |
| `input_number.hba_strategy_sell_target_energy` | `2` kWh |

## Timed Strategy

| Helper | Default |
|---|---|
| `input_boolean.hba_strategy_timed_has_period_b` | `off` |
| `input_boolean.hba_strategy_timed_has_period_c` | `off` |
| `input_select.hba_strategy_timed_strat_0` | `Self-consumption` (default / no period match) |
| `input_select.hba_strategy_timed_strat_a` | `Charge` |
| `input_select.hba_strategy_timed_strat_b` | `Sell` |
| `input_select.hba_strategy_timed_strat_c` | `Self-consumption` |

Period times (`input_datetime.hba_strategy_timed_period_a1` etc.) are not set by apply_defaults — configure them manually.

## Dynamic Pricing (v1)

| Helper | Default |
|---|---|
| `input_select.hba_strategy_dynamic_data_source` | `Frank Energie` |
| `input_select.hba_strategy_dynamic_default` | `Self-consumption` |
| `input_select.hba_strategy_dynamic_cheapest` | `Charge` |
| `input_select.hba_strategy_dynamic_expensive` | `Self-consumption` |
| `input_number.hba_strategy_dynamic_cheapest_hrs` | `4` h |
| `input_number.hba_strategy_dynamic_expensive_hrs` | `2` h |
| `input_number.hba_strategy_dynamic_threshold_cheapest_period` | `5` ct/kWh |
| `input_number.hba_strategy_dynamic_threshold_delta` | `5` ct/kWh |

## Dynamic Pricing (v2 — Extreme-Pair Matching)

| Helper | Default |
|---|---|
| `input_number.hba_strategy_dynamic_v2_max_cheap_hours_per_day` | `4` h/day |
| `input_number.hba_strategy_dynamic_v2_max_expensive_hours_per_day` | `2` h/day |

`threshold_delta` is shared with v1 (see above). `threshold_cheapest_period` is v1-only and ignored by v2.

## Per-Battery SoC Cutoffs (all 6 slots)

| Helper | Default | Notes |
|---|---|---|
| `input_number.hba_marstek_m{1-6}_charging_cutoff_capacity` | `100` % | |
| `input_number.hba_marstek_m{1-6}_discharging_cutoff_capacity` | `12` % | Works for Venus E v1/v2/v3. Venus E v3.0 users may want to raise this to **13%**: the v3.0 firmware has a ~2% hysteresis and in practice won't discharge below ~13% regardless of the software setting. |

## Solar Forecast Entity IDs

| Helper | Default |
|---|---|
| `input_text.hba_strategy_solar_forecast_entity_id` | `sensor.solcast_pv_forecast_forecast_remaining_today` |
| `input_text.hba_strategy_solar_forecast_tomorrow_entity_id` | `sensor.solcast_pv_forecast_forecast_tomorrow` |
| `input_text.hba_strategy_solar_aware_forecast_entity_id` | `sensor.solcast_pv_forecast_forecast_today` |

> **Two separate helpers, because the two consumers need different things.**
>
> The first two feed the **Charge goal** (`solar forecast`) and the forecast/surplus
> sensors. They read only the **state** (kWh), so "today" defaults to
> `…_forecast_remaining_today`: the whole-day `forecast_today` keeps counting solar that
> has already been produced, so from midday onwards it makes the goal believe a large
> surplus is still coming and suppresses grid charging during the cheap hours.
> `remaining_today` shrinks as the day goes on and lets the goal fall back to the grid.
> Tomorrow has no "remaining" variant — the whole day is still ahead.
>
> The third feeds **Solar-aware** only (`sensor.hba_solar_charge_outlook` and
> `script.hba_strategy_solar_aware`). It integrates the `detailedForecast` attribute
> (half-hourly breakdown) over the remaining cheap slots, and that attribute exists only
> on `forecast_today` / `forecast_tomorrow`, and only when the Solcast integration's
> half-hourly detail attribute option is enabled. Pointing it at
> `…_forecast_remaining_today` puts the outlook in the `No solar detail` fallback
> (permanent Zero import). **This helper must be a whole-day sensor.**
>
> Leave `hba_strategy_solar_aware_forecast_entity_id` **empty** to inherit
> `hba_strategy_solar_forecast_entity_id` — that is the pre-split behaviour, so existing
> installs keep working untouched.

When either helper is **empty** (e.g. before `apply_defaults` has run), the forecast
is treated as **0 kWh** — the solar forecast charge goal will not reduce the charge
target, so the full battery capacity will be charged from the grid. Run `apply_defaults`
or set these manually in Advanced Settings before using the solar forecast charge goal.

## Solar-aware Strategy

| Helper | Default | Notes |
|---|---|---|
| `input_number.hba_strategy_solar_aware_forecast_threshold_kwh` | `20` kWh | Min. remaining solar forecast to activate Zero import |

## Frank Energie Entity ID

| Helper | Default |
|---|---|
| `input_text.hba_strategy_dynamic_frank_sensor_entity_id` | `sensor.frank_energie_prijzen_gemiddelde_elektriciteitsprijs_alle_uren_all_in` |

## Miscellaneous

| Helper | Default |
|---|---|
| `input_boolean.hba_control_is_debug_mode` | `off` |
| `input_select.hba_control_strategy_during_ev_charge` | `Full stop` |
| `input_text.hba_strategy_ev_saturated_entity_id` | `""` (empty — Charge PV runs whenever the EV charges; set to the EV side's saturated binary_sensor to gate it) |
| `input_text.hba_strategy_ev_sensor_entity_id` | `""` (empty) |

## Notifications

| Helper | Default | Notes |
|---|---|---|
| `input_boolean.hba_notifications_enabled` | `on` | Master on/off for all HBA notifications |
| `input_text.hba_notify_entity_id` | `""` (empty) | Target notify action — empty falls back to HA persistent notifications |

## Timed EV Charge

| Helper | Default | Notes |
|---|---|---|
| `input_boolean.hba_battery_assist_enabled` | `off` | Master on/off toggle |
| `input_datetime.hba_battery_assist_start_time` | `05:00:00` | Start of discharge window |
| `input_datetime.hba_battery_assist_end_time` | `07:00:00` | End of discharge window |
| `input_number.hba_battery_assist_min_soc` | `20` % | SoC floor — assist stops when average SoC drops below this |
| `input_number.hba_battery_assist_max_discharge_power` | `0` W | Max discharge power during assist; `0` = use battery hardware maximum |
| `input_text.hba_battery_assist_car_connected_entity` | *(empty)* | Optional: entity (`on` = car connected). If empty, condition is ignored |
