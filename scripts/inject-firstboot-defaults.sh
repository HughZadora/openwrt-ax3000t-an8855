#!/bin/bash
# ============================================================
# Inject first-boot UCI defaults for AX3000T-AN8855
# Called from GitHub Actions CI workflow
# ============================================================

set -euo pipefail

OPENWRT_DIR="${1:?Usage: $0 <openwrt-dir>}"

UCIDEF_DIR="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults"
mkdir -p "$UCIDEF_DIR"

cat > "$UCIDEF_DIR/99-router-home-custom" <<'EOF'
#!/bin/sh
# 首次启动定制:
#   1) LAN default IP changed to 192.168.31.1 (Xiaomi convention)
#   2) WiFi enabled by default (2.4G / 5G, unencrypted) for cable-free configuration

# --- LAN IP ---
uci -q set network.lan.ipaddr='192.168.31.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q commit network

# --- WiFi 启用 + 开放 SSID ---
# The 2.4G and 5G wifi-device sections are typically radio0 / radio1
for radio in radio0 radio1; do
    [ -n "$(uci -q get wireless.$radio)" ] || continue
    uci -q set wireless.$radio.disabled='0'

    iface="$(uci -q get wireless.$radio | sed -n 's/.*\(default_radio[0-9]*\).*/\1/p')"
    [ -z "$iface" ] && iface="default_$radio"
    if [ -n "$(uci -q get wireless.$iface)" ]; then
        uci -q set wireless.$iface.disabled='0'
        uci -q set wireless.$iface.encryption='none'
        case "$radio" in
            radio0) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T' ;;
            radio1) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T-5G' ;;
        esac
    fi
done
uci -q commit wireless

# 立即生效
wifi reload 2>/dev/null

exit 0
EOF

chmod +x "$UCIDEF_DIR/99-router-home-custom"
echo "Injected: $UCIDEF_DIR/99-router-home-custom"