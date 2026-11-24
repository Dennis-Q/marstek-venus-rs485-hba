
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
