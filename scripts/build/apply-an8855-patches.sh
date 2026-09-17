#!/bin/bash
# ============================================================
# 步骤 2: 应用 AN8855 单 UBI 目标补丁（仅上游 main 需要）
#
# 背景: 主线 main 只有 stock 双分区 / ubootmod 目标，AN8855 + 原厂 U-Boot
#       需要独立的单 UBI 目标才能持久启动。补丁文件固化在 patches/ 下。
#       非 main 分支（如 openwrt-24.10）官方自带该目标，整体跳过。
#
# 用法: apply-an8855-patches.sh [--branch <分支>]
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

BRANCH="main"
while [ $# -gt 0 ]; do
	case "$1" in
	--branch)
		[ $# -ge 2 ] || die "--branch 需带分支名"
		BRANCH="$2"
		shift 2
		;;
	--branch=*)
		BRANCH="${1#*=}"
		shift
		;;
	*) die "未知参数: $1 (支持: --branch <分支>)" ;;
	esac
done

UPSTREAM="$(upstream_branch "$BRANCH")"

log ""
log "=== 步骤 2: 应用 an8855 单 UBI 目标补丁 ==="

[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

if ! is_mainline_branch "$BRANCH"; then
	log "  非 main 分支($UPSTREAM),官方自带 an8855 单 UBI 目标,跳过补丁应用"
	exit 0
fi

cd "$OPENWRT_DIR"

# 已应用则跳过,避免重复打补丁报错。
if grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
	log "  an8855 目标已存在,跳过打补丁"
	exit 0
fi

log "  复制 DTS ..."
cp "${REPO_PATCH_DIR}/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" \
	target/linux/mediatek/dts/

log "  应用 filogic.mk / platform.sh / 02_network 补丁 ..."
# 先 dry-run 全量校验,任一 hunk 不匹配(主线已漂移)则整体失败并给友好提示,
# 避免编到一半才因补丁问题崩溃。
for p in "${REPO_PATCH_DIR}"/*.patch; do
	log "    dry-run: $(basename "$p")"
	if ! patch -p1 --forward --dry-run -i "$p"; then
		printf '  ❌ 补丁 %s 无法应用:main 已漂移。\n' "$(basename "$p")" >&2
		printf '     方案A: 把 main 锁定到 %s 里的已验证 commit。\n' "$VERIFIED_COMMIT_FILE" >&2
		printf '     方案B: 手工修此补丁后重试。\n' >&2
		exit 1
	fi
done
for p in "${REPO_PATCH_DIR}"/*.patch; do
	patch -p1 --forward -i "$p"
done

log "  已应用 an8855 目标补丁"

# 应用后显式校验三个被改文件的關鍵符号确实出现,防止"看似成功实则没生效"。
if ! grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
	die "应用后 filogic.mk 未出现 an8855 目标,补丁未真正生效。"
fi
if ! grep -q "xiaomi,mi-router-ax3000t-an8855" target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh; then
	die "应用后 platform.sh 未出现 an8855 升级入口,补丁未真正生效。"
fi
if ! grep -q "xiaomi,mi-router-ax3000t-an8855" target/linux/mediatek/filogic/base-files/etc/board.d/02_network; then
	die "应用后 02_network 未出现 an8855 网口/MAC 规则,补丁未真正生效。"
fi

log "  补丁生效校验通过。"
