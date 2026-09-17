#!/bin/bash
# ============================================================
# 步骤 3: 添加 OpenClash feed，并更新/安装全部 feeds
#
# 用法: configure-feeds.sh
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

cd "$OPENWRT_DIR"

log ""
log "=== 步骤 3: 添加 OpenClash feed 并更新 feeds ==="

# 注意:必须把 feed 加到官方的 feeds.conf.default(含 luci/packages 等官方源),
# 而不是只新建 feeds.conf(那会让 OpenWrt 只认 feeds.conf 而丢掉官方源)。
if [ ! -f feeds.conf ]; then
	cp feeds.conf.default feeds.conf
fi
if grep -q "OpenClash" feeds.conf; then
	log "  OpenClash feed 已存在,跳过"
else
	cat >>feeds.conf <<EOF
# OpenClash (Clash/Mihomo 客户端)
src-git openclash ${OPENCLASH_URL}
EOF
	log "  已添加: src-git openclash ${OPENCLASH_URL}"
fi

./scripts/feeds update -a
./scripts/feeds install -a
