#!/bin/bash
# ============================================================
# 步骤 8: 单独编译 OpenClash 为 apk（不进固件，装时 apk add）
#
# 用法: compile-openclash-apk.sh
#
# 结果: 编译成功后把 apk 的绝对路径写入 $OPENCLASH_APK_PATH_FILE
#       （默认 <openwrt-dir>/.openclash-apk-path），供 CI 读取，
#       避免 CI 与 setup.sh 各自再实现一遍 apk 路径查找。
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

cd "$OPENWRT_DIR"

log ""
log "=== 步骤 8: 单独编译 OpenClash 为 apk(不进固件,装时 apk add) ==="
log "  运行: make package/feeds/openclash/luci-app-openclash/compile V=s"

rm -f "$OPENCLASH_APK_PATH_FILE"
make package/feeds/openclash/luci-app-openclash/compile V=s 2>&1 | tee -a build.log

# 路径不写死架构目录(不同 OpenWrt 分支/feed 会变)，直接按名字查找。
APK_PATH="$(find "$OPENWRT_DIR/bin/packages" -type f -name 'luci-app-openclash*.apk' -print -quit 2>/dev/null || true)"

if [ -z "$APK_PATH" ]; then
    warn "未生成 OpenClash apk(bin/packages 下没有 luci-app-openclash*.apk)。"
    warn "常见原因: .config 里 CONFIG_PACKAGE_luci-app-openclash 未设为 =m"
    warn "          (种子见 scripts/build/generate-config-seed.sh)，或 openclash feed 未安装成功。"
    exit 1
fi

log "  OpenClash apk 已生成:"
ls -lh "$APK_PATH" | sed 's/^/    /'
printf '%s\n' "$APK_PATH" > "$OPENCLASH_APK_PATH_FILE"
