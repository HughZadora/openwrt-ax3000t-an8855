#!/bin/bash
# ============================================================
# 步骤 9: 产物体积门禁与汇总
#
# 用法: report-artifacts.sh <gate|summary>
#   gate     编译后立即执行的 initramfs 体积门禁(STRICT=1)，超限即失败
#   summary  最终汇总: 体积门禁 + OpenClash apk sha256 + 刷机清单
#
# 体积判定逻辑与刷机清单在 scripts/check-image-size.sh（路径稳定入口）。
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

MODE="${1:-}"
case "$MODE" in
gate | summary) ;;
*) die "用法: report-artifacts.sh <gate|summary>" ;;
esac

[ -d "$TARGET_DIR" ] || die "产物目录不存在: $TARGET_DIR（固件是否编译成功?）"

if [ "$MODE" = "gate" ]; then
	log ""
	log "=== 步骤 9: initramfs 体积门禁(原厂 U-Boot 上限) ==="
	if ! STRICT=1 bash "${REPO_ROOT}/scripts/check-image-size.sh" "$TARGET_DIR"; then
		printf '  ❌ initramfs 超限,停止 OpenClash 编译以避免在坏产物上继续。\n' >&2
		exit 1
	fi
	exit 0
fi

log ""
log "=== 步骤 9: 产物汇总(体积门禁 + sha256) ==="
STRICT=1 bash "${REPO_ROOT}/scripts/check-image-size.sh" "$TARGET_DIR"

log "  OpenClash apk:"
if [ -f "$OPENCLASH_APK_PATH_FILE" ]; then
	APK_PATH="$(cat "$OPENCLASH_APK_PATH_FILE")"
	printf '    %s  %s\n' "$(sha256sum "$APK_PATH" | cut -d' ' -f1)" "$(basename "$APK_PATH")"
else
	warn "未找到 $OPENCLASH_APK_PATH_FILE(是否跳过了 OpenClash 编译步骤?)"
fi

for f in "$TARGET_DIR"/*.manifest; do
	[ -e "$f" ] || continue
	log "  固件包清单: $(basename "$f")"
done
log ""
