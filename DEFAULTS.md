# HBA Factory Defaults — v4.10.1-r19

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

All four presets share **Kp 0.35 / Kd 0.1 / error damping 20 % / output damping 10 %** and
differ **only in Ki**, because **Kp 0.35 is the measured optimum** — bracketed on both sides
on production against a real 2250 W load, Ki held at 0.22:

| | Kp 0.20 | **Kp 0.35** | Kp 0.55 |
|---|---|---|---|
| peak (+3 s) | 1602 W | 1420 W | 1304 W |
| tail (+10 s) | 54 W | 156 W | 349 W |
| **cost per disturbance** | 0.74 ct | **0.61 ct** | 0.71 ct |

Lower Kp gives a higher peak but a faster tail; higher Kp the reverse. Both cost more overall,
so the presets leave Kp alone and vary only Ki.

Changing Kp is only worthwhile if transient **peaks** matter to you more than energy — peak
shaving, a capacity tariff, or a hard grid limit. The exchange rate is roughly **8 % lower
peak for 16 % higher cost per disturbance** (Kp 0.55).

| Preset | Ki | Character | Measured on an 863 W step |
|---|---|---|---|
| Very safe | 0.10 | Calmest, least battery activity | 6.1 Wh, ~38 s to settle |
| Safe | 0.15 | Noticeably slower tail | 4.4 Wh |
| **Regular** *(default)* | **0.22** | **Validated on production** | 3.7 Wh. Against a real 2.25 kW step: residual **143 W at +8 s**, zero setpoint crossings |
| Responsive | 0.30 | Fastest measured | 3.2 Wh. Untested against 2.25 kW steps — may overshoot, as overshoot scales with step size |

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
| `input_text.hba_strategy_solar_forecast_entity_id` | `sensor.solcast_pv_forecast_forecast_today` |
| `input_text.hba_strategy_solar_forecast_tomorrow_entity_id` | `sensor.solcast_pv_forecast_forecast_tomorrow` |

> **Why `forecast_today` and not `forecast_remaining_today`:** the Solar-aware outlook
> sensor needs the `detailedForecast` attribute (half-hourly breakdown), which only
> `forecast_today` / `forecast_tomorrow` carry — and only when the Solcast integration's
> half-hourly detail attribute option is enabled. `forecast_remaining_today` has a valid
> kWh state but no detail attribute, which puts the outlook in the `No solar detail`
> fallback (permanent Zero import). Earlier releases defaulted to
> `forecast_remaining_today` — re-run `apply_defaults` or fix the helper manually.

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
