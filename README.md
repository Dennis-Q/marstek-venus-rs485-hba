# Home Battery Assistant (HBA) — v4.10.1-r3

A native Home Assistant replacement for the Node-RED battery control flows in
[gitcodebob/marstek-venus-rs485-node-red](https://github.com/gitcodebob/marstek-venus-rs485-node-red).
Same strategies, same logic, same dashboard — no Node-RED required.

> **Use at your own risk.** This project controls hardware that charges and discharges
> batteries. Misconfiguration can cause unexpected behaviour. Always verify your setup
> and monitor the first few cycles. No warranty is provided.

---

## Credits and donations

**All credit for the battery control strategies goes to [gitcodebob](https://github.com/gitcodebob)**
for designing and building the original
[marstek-venus-rs485-node-red](https://github.com/gitcodebob/marstek-venus-rs485-node-red)
project — the strategies, PID algorithm, dashboard design, and overall approach all originate
there. This project would not exist without it.

**Credit for the Marstek Modbus integration goes to [fonske](https://github.com/fonske)**
for the [MarstekVenusV3-modbus-TCP-IP](https://github.com/fonske/MarstekVenusV3-modbus-TCP-IP)
project. The `marstek_m*.yaml` files in this repository are based directly on his work.

If you find this useful, please **donate to the original projects**, not here.
Donation links are on their respective repository pages.

HBA was developed with support of [Claude](https://claude.ai) by Anthropic.

---

## What this is

HBA's primary goal is to make Marstek battery control accessible without Node-RED — just Home
Assistant, no extra runtime required. It replaces the Node-RED flows from the original project
with native HA automations and scripts, keeping the same strategies, logic, and feature set.

Most documentation written for the original project also applies here — the strategies,
settings, and PID parameters work the same way. The original documentation lives at
**[docs.homebatterycontrol.com](https://docs.homebatterycontrol.com)** and is the primary
reference for strategies, PID tuning, and advanced features.

📃 **[HBA Release Notes](RELEASE_NOTES.md)** — what changed between HBA releases.

HBA aims to stay reasonably aligned with the original project as it evolves, but this is a
best-effort goal — it started as an experiment, and maintenance depends on available time.

---

## How it differs from HBC

The most significant difference is the Node-RED dependency — HBA replaces Node-RED flows
with native HA automations and scripts. The strategies, PID algorithm, and overall logic
are direct ports of HBC. State that HBC stores in Node-RED context (and loses on restart)
is stored in HA helpers and survives restarts. HBA also adds features that made sense in
the HA context and were not possible in Node-RED.

For a full breakdown — including PID behaviour differences, feature additions, dashboard
changes, and known gaps — see **[DIFFERENCES.md](DIFFERENCES.md)**.

---

## For existing HBC users

HBA is designed to be installed **alongside HBC** on the same HA instance — you do not
have to choose one or commit to switching. Try HBA while HBC remains installed; switch
back at any point with one button.

### Your existing config is compatible

**Marstek battery files** — HBA uses the same fonske-based entity IDs as HBC
(`select.marstek_m1_forcible_charge_discharge`, `number.marstek_m1_forcible_charge_power`,
etc.). If your Marstek files are already working with HBC, they work with HBA without
any changes to those files.

**P1 meter sensor** — HBC's `house_battery_control_config.yaml` already defines
`sensor.p1_meter_power`. HBA reads that same entity — no changes to `hba_config.yaml`
needed while HBC is installed. `hba_config.yaml` only becomes relevant if you later
decide to remove HBC, at which point you would migrate your sensor definition there.

**Helper entities** — all HBA helpers use the `hba_` prefix; they do not collide with
HBC's `hbc_` entities. Both sets can exist in HA simultaneously.

### PID values from HBC do not transfer directly

HBA's PID controller runs on every P1 update with no additional cycle skipping (beyond
the 15 W deadband). HBC has an "operational thresholds" gate that skips the PID cycle
when P1 changes less than 20 W and less than 2% from the previous reading — so HBC
runs the integrator less frequently during stable periods.

With the same Ki, HBA accumulates I-term faster than HBC. If you migrate your HBC PID
values directly you may find the system feels more aggressive, particularly the
I-term. **Start with a lower Ki than you used in HBC** and tune from there.

**P1 update rate matters:** DSMR 5.0 meters update every 1 s; older meters may update
every 3–10 s. HBA runs at whatever rate the P1 sensor updates — with a slower meter
the I-term accumulates proportionally slower, so the system is more conservative.
The Ki warning above is most relevant for 1 s meters; at slower rates HBA and HBC
behave more similarly.

The built-in presets **Very safe**, **Safe**, and **Regular (original HBC)** are carried
over from HBC. A new **Regular** preset has been introduced in HBA with values that
appear to work better in practice — it is still being reviewed, so treat it as a starting
point. The original HBC values are preserved as **Regular (original HBC)** for reference.
All presets are still being reviewed for optimal values with HBA's implementation.
[docs.homebatterycontrol.com/04-setup-self-consumption](https://docs.homebatterycontrol.com/04-setup-self-consumption)
covers PID tuning in general; the HBA-specific starting point is a lower Ki.

### Switching between HBA and HBC

The HBA dashboard has a coexistence panel (in Advanced Settings) with two buttons:

- **Take control** — stops the Node-RED addon, disables HBC's automations, enables HBA
- **Yield to HBC** — disables HBA, starts Node-RED, re-enables HBC's automations

A conflict guard fires automatically if both systems end up in Full control at the same
time, disabling HBA and creating a persistent notification.

> ⚠️ The Take control / Yield to HBC buttons start and stop the Node-RED **addon**. If
> you have Node-RED flows unrelated to battery control, they are also affected. Check
> before using.

For full details see [Running HBA alongside HBC](#running-hba-alongside-hbc) below.

---

## Requirements

**Required**

- Home Assistant 2025.1 or newer (tested on 2026.5.1)
- Marstek Venus E battery with Modbus TCP (direct Ethernet, port 502)
  — tested on V3; V1 and V2 are expected to work but have not been verified

**Optional**

- **Solar forecast integration** — for the solar forecast charge goal. Requires a
  forecast integration that exposes estimated energy for today and tomorrow (in kWh).
  Tested with Solcast PV Forecast; any integration providing equivalent sensors works.
  Entity IDs are configurable in Advanced Settings. When not configured, forecast is
  treated as 0 kWh and the charge goal charges the full battery capacity from the grid.
- **Energy price integration + [HACS Cheapest Energy Hours](https://github.com/TheFes/cheapest-energy-hours)**
  — for the Dynamic pricing strategy. Requires a supported price source (e.g.
  [Frank Energie](https://github.com/HiDiHo01/home-assistant-frank_energie), Tibber,
  Nordpool) and the HACS Cheapest Energy Hours integration. See
  **[docs.homebatterycontrol.com/05-setup-dynamic](https://docs.homebatterycontrol.com/05-setup-dynamic)**
  for supported sources and setup.

---

## Installation

### Step 1 — Prerequisites: HA running, batteries visible via Modbus

The goal of this step is to have Home Assistant running with your Marstek batteries
accessible as entities. The
**[HBC Getting Started guide](https://docs.homebatterycontrol.com/01-getting-started)**
covers hardware connection, Modbus setup, and the HA integration in full. Follow it
up to — but not including — the Node-RED installation step.

### Step 2 — Install packages and dashboard

**Option A — Install script** (recommended)

From your HA config directory (`/config`), run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/marstek-venus-rs485-hba/main/install.sh)
```

The script downloads all HBA files, skips files you have already configured (P1 sensor, battery IPs), asks whether to include the HBC coexistence file, and warns if `configuration.yaml` needs updating. Run it again at any time to update to the latest version.

> **Tip:** The [SSH & Web Terminal add-on](https://github.com/hassio-addons/addon-ssh) gives you a terminal on your HA instance. Run the command above from `/config`.

To install a specific version: `HBA_VERSION=v4.10.1-r3 bash <(curl -fsSL ...)`

**Option B — Manual**

Copy the entire `packages/` directory and `lovelace/battery_assistant.yaml` to your HA config root, then add to `configuration.yaml`:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

> **Which files to edit:** only `hba_config.yaml` (Step 3) and the
> `marstek_m*.yaml` battery files (Step 4). All other `hba_*.yaml` files
> work without modification. `hba_hbc_coexistence.yaml` can be skipped on
> a clean install with no HBC — it polls the Supervisor API every 10 s for
> the Node-RED addon, which is unnecessary overhead if Node-RED is not
> installed. Include it if you have or previously had HBC
> (see [Running alongside HBC](#running-hba-alongside-hbc)).

### Step 3 — Configure your grid power sensor

Edit `packages/hba_config.yaml` to define `sensor.p1_meter_power` for your setup.
The file ships with commented examples. The sensor must be **positive when importing**
from the grid and negative when exporting. Entity names depend on your DSMR reader —
check **Developer Tools → States** to find the correct ones.

### Step 4 — Set battery IPs

Edit each `packages/marstek_m*.yaml` for the batteries you have and replace the
placeholder IP with the actual IP of that battery. Only configure the files for
batteries you physically have; unused files can be left as-is or deleted.

### Step 5 — Restart Home Assistant

Restart HA (or **Developer Tools → YAML → Reload All YAML**) to load the packages.

### Step 6 — Load the dashboard

The dashboard YAML is at `lovelace/battery_assistant.yaml`.

**Option A — YAML dashboard** (requires file access to the HA config)

Add to `configuration.yaml`:

```yaml
lovelace:
  dashboards:
    home-battery-assistant:
      mode: yaml
      title: Home Battery Assistant
      icon: mdi:battery-charging
      filename: lovelace/battery_assistant.yaml
```

**Option B — Copy-paste** (no file system access required)

In HA, create a new dashboard and set its URL to **`home-battery-assistant`**
(Settings → Dashboards → Add dashboard → URL field). Then open the raw YAML editor
and paste the contents of `lovelace/battery_assistant.yaml`.

> The slug must be `home-battery-assistant` — the dashboard contains hard-coded
> navigation links to `/home-battery-assistant/...` that break if a different slug
> is used.

### Step 7 — Run onboarding

Open the Home Battery Assistant dashboard. The built-in onboarding wizard walks you
through battery count, verifies Modbus connectivity for each battery, and runs
`script.hba_apply_defaults` to set all helpers to sensible starting values —
no manual helper editing required.

---

## HBA-specific topics

### Package file reference

| File(s) | Purpose | Edit? |
|---|---|---|
| `hba_config.yaml` | Grid power sensor (`sensor.p1_meter_power`) | **Yes** — required |
| `marstek_m1–6_modbus_tcp.yaml` | Modbus hub + all sensors per battery | IPs only |
| `hba_helpers.yaml` | All input helpers and aggregate sensors | No |
| `hba_strategies_core.yaml` | Control loop, PID controller, strategy dispatch | No |
| `hba_strategy_*.yaml` (7 files) | Individual strategy scripts | No |
| `hba_hbc_coexistence.yaml` | HBC coexistence controls | No — skip on clean install without HBC |

All default values for helpers are documented in [DEFAULTS.md](DEFAULTS.md).

### Marstek battery files

The `marstek_m*.yaml` files are built from
[fonske's MarstekVenusV3-modbus-TCP-IP](https://github.com/fonske/MarstekVenusV3-modbus-TCP-IP)
originals. All entity IDs are unchanged and the files are compatible with HBC.
**You can use fonske's files directly** if you prefer — HBA works fine with them.

The files differ from fonske's in three minimal ways:
- `service:` → `action:` throughout (required for HA 2026.x)
- Bug fix: corrected a missing entity prefix in the `charge_to_soc` state template
- **m2–m6 only:** an `availability:` condition on each template `select` entity

The availability condition prevents HA from polling batteries that are not configured.
Without it, setting `hba_battery_count` to 1 still causes the Modbus hub to poll
batteries 2–6 on every scan interval, fail, and fill your logs with connection errors.

`marstek_m4–m6_modbus_tcp.yaml` are generated from fonske's m2 structure (fonske does
not publish m4–m6) with the battery number substituted throughout.

**Tested hardware:** Venus E V3 via TCP Modbus. V1 and V2 are expected to work but
have not been verified.

### Running HBA alongside HBC

HBA is designed to coexist with HBC on the same HA instance. The package
`hba_hbc_coexistence.yaml` handles detection and handoff:

- **"Take control" button** — disables HBC's HA automations, stops the Node-RED addon,
  then activates HBA in Full control mode.
- **"Yield to HBC" button** — disables HBA, starts Node-RED, then re-enables HBC's
  HA automations.

> ⚠️ **Warning:** These scripts start and stop the Node-RED addon via the Supervisor API.
> If you have other Node-RED flows unrelated to battery control, **they will also be
> affected**. Check your Node-RED flows before using these buttons.

A conflict guard fires automatically if both systems are detected running in Full control
at the same time — it disables HBA and creates a persistent HA notification so you can
recover cleanly.

`apply_defaults` sets the Node-RED addon slug to `a0d7b954_nodered` (the standard HAOS
slug). If your Node-RED addon uses a different slug, update
`input_text.hba_hbc_nodered_addon_slug` in Advanced Settings.

### Dynamic pricing

Two algorithms are available — both are faithful ports of the HBC implementation. See
**[docs.homebatterycontrol.com/05-setup-dynamic](https://docs.homebatterycontrol.com/05-setup-dynamic)**
for a full description of how they work and how to configure them.

**HBA-specific:** the Frank Energie sensor entity ID is configurable in the dashboard
under Advanced Settings (default matches HBC:
`sensor.frank_energie_prijzen_gemiddelde_elektriciteitsprijs_alle_uren_all_in`).
If your integration uses English entity names or you prefer a different price basis,
update the entity ID there — for example:
- `sensor.frank_energie_prices_average_electricity_price_all_hours_all_in` (English, all-in)
- `sensor.frank_energie_prices_current_electricity_market_price` (English, market price ex taxes)

---

## Feedback and maintenance

Feedback is welcome via [GitHub issues](../../issues).

That said: **I am not certain I will maintain this long-term.** This started as an
experiment. I will look at issues that are raised, but I cannot promise a timeline or
guaranteed fixes. If the original project incorporates any of this work, I consider
that the best possible outcome.
