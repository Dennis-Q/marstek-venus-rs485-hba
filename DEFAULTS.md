# HBA Factory Defaults — v4.10.0-r1

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
| `input_select.hba_control_pid_presets` | `Very safe` | |
| `input_number.hba_target_grid_consumption_in_w` | `0` W | Keep grid import at 0 W |
| `input_number.hba_control_kp` | `0.1` | Matches Very safe preset |
| `input_number.hba_control_ki` | `0.1` | Matches Very safe preset |
| `input_number.hba_control_kd` | `0` | Matches Very safe preset (D-term off) |
| `input_number.hba_control_pid_output_dampening` | `10` % | Matches Very safe preset |
| `input_number.hba_control_error_signal_dampening` | `0` % | Matches Very safe preset (no error smoothing) |
| `input_number.hba_control_hysteresis_in_w` | `20` W | Direction-flip guard threshold |
| `input_number.hba_control_idle_time` | `5` min | Per-battery idle hold before relay disconnect |

### PID Presets

| Preset | Kp | Ki | Kd | Error damp | Output damp | Hysteresis |
|---|---|---|---|---|---|---|
| Very safe | 0.1 | 0.1 | 0 | 0 % | 10 % | (unchanged) |
| Safe | 0.3 | 0.3 | 0.1 | 20 % | 0 % | (unchanged) |
| Regular | 0.35 | 0.3 | 0.1 | 20 % | 10 % | (unchanged) |
| Regular (original HBC) | 0.3 | 0.4 | 0.8 | 50 % | 10 % | (unchanged) |

Very safe / Safe / Regular (original HBC) are carried over from HBC. **Regular** is an
HBA-introduced preset still under review — treat as a starting point.

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

When either helper is **empty** (e.g. before `apply_defaults` has run), the forecast
is treated as **0 kWh** — the solar forecast charge goal will not reduce the charge
target, so the full battery capacity will be charged from the grid. Run `apply_defaults`
or set these manually in Advanced Settings before using the solar forecast charge goal.

## Frank Energie Entity ID

| Helper | Default |
|---|---|
| `input_text.hba_strategy_dynamic_frank_sensor_entity_id` | `sensor.frank_energie_prijzen_gemiddelde_elektriciteitsprijs_alle_uren_all_in` |

## Miscellaneous

| Helper | Default |
|---|---|
| `input_boolean.hba_control_is_debug_mode` | `off` |
| `input_boolean.hba_control_has_power_limit_during_ev_charge` | `off` |
| `input_text.hba_strategy_ev_sensor_entity_id` | `""` (empty) |
