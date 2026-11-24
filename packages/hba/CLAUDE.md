
## Predicted cell temperature (EXPERIMENTAL, 2026-11-24)

Setting `input_text.hba_strategy_planned_battery_room_temp_entity_id` (empty / unknown = off, nothing extra
runs; prod: the garage sensor `sensor.environment_sensor_onbekend_temperature`). In the planner, right after
the per-battery BMS rows (`ns_p.bats`): per later slot and per energy level, the warmest cell per battery =
room + (cell now − room) × e^(−0.186 × hours ahead) + 3.81 °C per AC kWh above the stored energy of now ×
e^(−0.186 × hours ahead / 2), then the row with the BMS hysteresis (+0.75 up / −3.5 down from the row of now).
A slot whose rows differ from now gets its own key (`cell.at`, `cell.rows`): its own per-level power
(`ns_p.plc` / `ns_p.pld`), slot ceiling (`sl.pc` / `sl.pd`, `sl.pk`) and reach tables (`reach.c[key@hours]`).
Summary `cell`: room, slots with other rows, `tp` = warmest cell at each slot start at this plan's energy.
Why "above the energy of now" (dev tests 11-24): (1) the warmth of a first plan given to a second dropped the
hours that made it (02-05 h at 10 A -> all at 05 h at 30 A); (2) warmth from the low point of the plan in force
flipped between two plans at every re-plan. Now it never counts more warmth than its own charging gives;
cautious in the evening before a Sell and with charging far ahead (decay over half the hours ahead), close at
the low point. Dev, 3 fake batteries, cells 3 °C, 0.1 kWh stored: room 5 °C -> 03-04 h at 10 A then 05 h 4.27
kWh (30 A); room 0 °C -> 10 A all night. On prod (4 batteries, power groups) the first version took 2.3-2.5 s
per plan against 1.1-1.35 s off (11-24 18:02-19:00). Speed-up 11-24 (same plan on dev): a battery's cell
temperature read once per plan, its rows looked up per 0.1 °C and kept (`cell.memo`), the power of each level
worked out once per set of rows (`jobs`, `pw`), slots with the same power per level share one key and one pair
of reach tables (`p0` = now, `p1` ...). Dev: 0.71 -> 0.46 s on, 0.35-0.41 s off.

## Backward pass speed-up (2026-11-24, same plan)

Dev timing per part (11-24): the backward pass was 0.30 of 0.35 s. Two changes, both only in the backward pass
(the forward pass, which names the strategy, still weighs every option):
- Partial Charge / Sell targets: their cost is linear in the target level j plus V[j] (Charge in between imports
  all of net; Sell in between exports dis - d + u with the sun exported = u), so per slot two lists `wl.c` /
  `wl.s` and the best target of a level = min of a slice. Car partial targets keep the loop (the 0.7 kWh
  minimum is an exact threshold per j).
- u = 0: Charge PV = Full stop and Self-consumption = Zero import except the tie-breaker; the twin with the
  higher tie-breaker is skipped.
Proof: `cmp_plan.py`-style render of the template at a fixed time in 7 situations (no car, car preview, battery
to car offered, cold cells with prediction, with and without car), inputs re-set until stable (the fake
batteries overwrite test states on their poll); old vs new identical within 1e-9 in plan and summary.
Dev: 0.35 -> 0.15-0.21 s without the prediction, 0.46 -> 0.33-0.36 s with it.
