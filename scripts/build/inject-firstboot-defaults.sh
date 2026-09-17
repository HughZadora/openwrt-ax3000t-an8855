#!/bin/bash
# ============================================================
# 步骤 6: 注入首次启动定制（LAN 192.168.31.1 / WiFi 默认开启）
#
# 用法: inject-firstboot-defaults.sh [<openwrt-dir>]
#       省略参数时使用 env.sh 的 OPENWRT_DIR（默认 <repo>/openwrt-ax3000t）
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

if [ $# -ge 1 ] && [ -n "${1:-}" ]; then
	OPENWRT_DIR="$1"
fi
[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

UCIDEF_DIR="$OPENWRT_DIR/package/base-files/files/etc/uci-defaults"
mkdir -p "$UCIDEF_DIR"

log ""
log "=== 步骤 6: 注入首次启动定制(IP 192.168.31.1 / WiFi 自动开启) ==="

cat >"$UCIDEF_DIR/99-router-home-custom" <<'EOF'
#!/bin/sh
# 首次启动定制:
#   1) LAN 默认 IP 改为 192.168.31.1 (Xiaomi 习惯)
#   2) WiFi 默认开启 (2.4G / 5G,无加密),方便无网线时连接配置

# --- LAN IP ---
uci -q set network.lan.ipaddr='192.168.31.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q commit network

# --- WiFi 启用 + 开放 SSID ---
# 2.4G 与 5G 的 wifi-device section 通常是 radio0 / radio1
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

log "  已注入: $UCIDEF_DIR/99-router-home-custom"
log "  首次启动: LAN=192.168.31.1, WiFi SSID: OpenWrt-AX3000T / OpenWrt-AX3000T-5G (无加密)"
log "  请尽快在 LuCI 中设置 root 密码与 WiFi 加密!"
