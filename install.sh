#!/usr/bin/env bash
# Home Battery Assistant — install / update script
#
# Usage (from your Home Assistant /config directory):
#   bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/marstek-venus-rs485-hba/main/install.sh)
#
# To install a specific version:
#   HBA_VERSION=v4.10.0-r1 bash <(curl -fsSL https://raw.githubusercontent.com/Dennis-Q/marstek-venus-rs485-hba/main/install.sh)
#
# Tip: use the SSH add-on (community) to get a terminal on your HA instance.

set -euo pipefail

REPO="Dennis-Q/marstek-venus-rs485-hba"
VERSION="${HBA_VERSION:-}"
CONFIG_DIR="$(pwd)"

# ── Colour / output helpers ───────────────────────────────────────────────────

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
ok()   { echo -e "  ${GREEN}✓${RESET} $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
say()  { echo "    $*"; }
hr()   { echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; }
ask()  { local _a; read -rp "  ? $* [y/N] " _a; [[ "${_a,,}" == "y" ]]; }

# ── Sanity checks ─────────────────────────────────────────────────────────────

if ! command -v curl &>/dev/null; then
    echo "ERROR: curl is required but not found. Install it and retry."
    exit 1
fi

if [ ! -f "${CONFIG_DIR}/configuration.yaml" ]; then
    echo "ERROR: configuration.yaml not found in $(pwd)."
    echo "Run this script from your Home Assistant config directory (/config)."
    exit 1
fi

# ── Version resolution ────────────────────────────────────────────────────────

if [ -z "$VERSION" ]; then
    LATEST=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
             | grep '"tag_name"' | cut -d'"' -f4 2>/dev/null || true)
    if [ -n "$LATEST" ]; then
        VERSION="$LATEST"
    else
        VERSION="main"
        warn "No releases found — installing from main branch."
        echo ""
    fi
fi

BASE_URL="https://raw.githubusercontent.com/${REPO}/${VERSION}"

# ── Download helper ───────────────────────────────────────────────────────────

download() {
    local src="$1" dst="$2"
    curl -fsSL "${BASE_URL}/${src}" -o "${dst}"
}

# ── Header ────────────────────────────────────────────────────────────────────

echo ""
hr
echo "  Home Battery Assistant — installer"
echo "  Version : ${VERSION}"
echo "  Target  : ${CONFIG_DIR}"
hr
echo ""

# ── Create directories ────────────────────────────────────────────────────────

mkdir -p "${CONFIG_DIR}/packages"
mkdir -p "${CONFIG_DIR}/lovelace"

# ── Core HBA files — always overwrite ────────────────────────────────────────
# Safe to overwrite on every update; no user-editable content in these files.

echo "Core files:"

CORE_FILES=(
    packages/hba_helpers.yaml
    packages/hba_strategies_core.yaml
    packages/hba_strategy_charge_pv.yaml
    packages/hba_strategy_charge_sell.yaml
    packages/hba_strategy_dynamic.yaml
    packages/hba_strategy_dynamic_v2.yaml
    packages/hba_strategy_others.yaml
    packages/hba_strategy_self_consumption.yaml
    packages/hba_strategy_timed.yaml
    lovelace/battery_assistant.yaml
)

for f in "${CORE_FILES[@]}"; do
    download "$f" "${CONFIG_DIR}/${f}"
    ok "$f"
done

echo ""

# ── HBC coexistence file ──────────────────────────────────────────────────────
# Overwrite if already present (must stay in sync with core files on update).
# Ask on fresh install — only needed if HBC / Node-RED is or was installed.

COEX="packages/hba_hbc_coexistence.yaml"
if [ -f "${CONFIG_DIR}/${COEX}" ]; then
    download "$COEX" "${CONFIG_DIR}/${COEX}"
    ok "${COEX} (updated)"
    echo ""
elif ask "Install HBC coexistence file? (only needed if you have or previously had Home Battery Control / Node-RED)"; then
    download "$COEX" "${CONFIG_DIR}/${COEX}"
    ok "${COEX}"
    echo ""
fi

# ── hba_config.yaml — first install only ─────────────────────────────────────
# Contains the user's P1 sensor definition. Never overwritten after initial
# install to avoid losing their configuration.

CONFIG_PKG="packages/hba_config.yaml"
if [ ! -f "${CONFIG_DIR}/${CONFIG_PKG}" ]; then
    download "$CONFIG_PKG" "${CONFIG_DIR}/${CONFIG_PKG}"
    ok "${CONFIG_PKG} (created)"
    warn "Edit packages/hba_config.yaml to define your P1 meter sensor."
    echo ""
else
    say "packages/hba_config.yaml already exists — skipped (your config is preserved)."
    echo ""
fi

# ── Marstek battery files — ask if none found ─────────────────────────────────
# If the user already has marstek files (with their IPs set), skip entirely.
# On a fresh install, offer to download them and prompt for battery count.

MARSTEK_FOUND=false
for _f in "${CONFIG_DIR}"/packages/marstek_m*.yaml; do
    [ -f "$_f" ] && MARSTEK_FOUND=true && break
done

if [ "$MARSTEK_FOUND" = false ]; then
    echo "Marstek battery files:"
    say "No marstek_m*.yaml files found."
    echo ""
    if ask "Download Marstek Modbus TCP files?"; then
        BAT_COUNT=0
        while [ "$BAT_COUNT" -lt 1 ] || [ "$BAT_COUNT" -gt 6 ]; do
            read -rp "  ? How many batteries do you have? (1–6): " BAT_COUNT
            BAT_COUNT=$(echo "$BAT_COUNT" | tr -d '[:space:]')
        done
        echo ""
        for n in $(seq 1 "$BAT_COUNT"); do
            download "packages/marstek_m${n}_modbus_tcp.yaml" \
                     "${CONFIG_DIR}/packages/marstek_m${n}_modbus_tcp.yaml"
            ok "packages/marstek_m${n}_modbus_tcp.yaml"
        done
        echo ""
        warn "Edit each marstek_m*.yaml and replace the IP placeholder with your battery's IP."
        echo ""
    fi
else
    say "Marstek files already present — skipped."
    echo ""
fi

# ── configuration.yaml checks ─────────────────────────────────────────────────

CONF="${CONFIG_DIR}/configuration.yaml"
NEEDS_ACTION=false

if ! grep -q "include_dir_named packages" "$CONF" 2>/dev/null; then
    warn "Packages directory not included in configuration.yaml. Add:"
    echo ""
    echo "      homeassistant:"
    echo "        packages: !include_dir_named packages"
    echo ""
    NEEDS_ACTION=true
fi

if ! grep -q "home-battery-assistant" "$CONF" 2>/dev/null; then
    warn "Dashboard not registered in configuration.yaml. Add:"
    echo ""
    echo "      lovelace:"
    echo "        dashboards:"
    echo "          home-battery-assistant:"
    echo "            mode: yaml"
    echo "            title: Home Battery Assistant"
    echo "            icon: mdi:battery-charging"
    echo "            filename: lovelace/battery_assistant.yaml"
    echo ""
    NEEDS_ACTION=true
fi

# ── Done ──────────────────────────────────────────────────────────────────────

hr
echo "  Done! Next steps:"
echo ""
if [ "$NEEDS_ACTION" = true ]; then
echo "  1. Update configuration.yaml (see warnings above)"
echo "  2. Edit packages/hba_config.yaml — define your P1 meter sensor"
echo "  3. Edit packages/marstek_m*.yaml — set your battery IP addresses"
echo "  4. Restart Home Assistant"
echo "  5. Open the Home Battery Assistant dashboard and run onboarding"
else
echo "  1. Edit packages/hba_config.yaml if you changed your P1 sensor setup"
echo "  2. Restart Home Assistant (or reload YAML)"
echo "  3. Check the dashboard — run onboarding if this is a fresh install"
fi
echo ""
hr
echo ""
