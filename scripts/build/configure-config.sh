#!/bin/bash
# ============================================================
# 步骤 4: 生成本设备 .config
#
# 流程: make defconfig(基线) -> 清理本仓库自有符号的旧行 ->
#       追加 .config.seed -> make defconfig(收敛依赖)
#
# 用法: configure-config.sh
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

cd "$OPENWRT_DIR"

log ""
log "=== 步骤 4: 生成默认配置 ==="
make defconfig

log ""
log "=== 步骤 5: 预置本设备目标 + OpenClash + LuCI ==="

# 配置契约(自有符号清单 + 种子)由 generate-config-seed.sh 单一提供，
# 本地与 CI 共用同一份，避免两份拷贝再次漂移。
bash "${BUILD_LIB_DIR}/generate-config-seed.sh" "$OPENWRT_DIR"

# 先清掉自有符号的旧行,避免 "key 多次定义" 警告与旧值残留(幂等)。
while IFS= read -r sym; do
    [ -n "$sym" ] || continue
    sed -i "/^CONFIG_${sym}=/d; /^# CONFIG_${sym} is not set\$/d" .config
done < "$OPENWRT_DIR/.config.owned-symbols"

cat "$OPENWRT_DIR/.config.seed" >> .config
rm -f "$OPENWRT_DIR/.config.seed" "$OPENWRT_DIR/.config.owned-symbols"

make defconfig

log ""
log "  已自动选中:"
log "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
log "    LuCI (+ SSL,中文)"
log "    OpenClash 仅单独编译为 apk(不进固件) / Tailscale + luci-app-tailscale-community"
log "    zram 内存压缩 / iptables+nftables 双栈 / 核心 netfilter / wireguard 隧道 / QoS(cake/fq-pie)"
log "    tcpdump / conntrack / ipset / tc-full / ext4 / 诊断工具 (精简版,适配原厂 U-Boot 体积上限)"
log ""
log "  如需调整运行: make menuconfig"
