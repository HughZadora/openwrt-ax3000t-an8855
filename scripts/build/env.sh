#!/bin/bash
# ============================================================
# 构建步骤共享环境（由各步骤脚本 source，不直接执行）
#
# 统一定义路径、常量与日志函数。历史上这些内容在 setup.sh 与 CI
# 工作流里各存一份拷贝（$(pwd) 推导路径、OpenClash feed 地址、
# 补丁目录、VERIFIED_COMMIT 文件名），两份拷贝已经发生过漂移，
# 故集中到本文件，作为唯一来源。
#
# 覆盖顺序: 环境变量(CI 会显式传入) > 仓库内默认值。
# 默认值全部相对仓库根，不再依赖调用者的当前工作目录。
# ============================================================

# 本文件位于 <repo>/scripts/build，故仓库根是其上两级。
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${BUILD_LIB_DIR}/../.." && pwd)}"

REPO_PATCH_DIR="${REPO_PATCH_DIR:-${REPO_ROOT}/patches}"
OPENWRT_DIR="${OPENWRT_DIR:-${REPO_ROOT}/openwrt-ax3000t}"
OPENWRT_GIT_URL="${OPENWRT_GIT_URL:-https://git.openwrt.org/openwrt/openwrt.git}"
OPENCLASH_URL="${OPENCLASH_URL:-https://github.com/vernesong/OpenClash.git}"
VERIFIED_COMMIT_FILE="${VERIFIED_COMMIT_FILE:-${REPO_PATCH_DIR}/VERIFIED_COMMIT}"
# OpenClash apk 路径的落盘位置（编译步骤写入，CI 与汇总步骤读取）
OPENCLASH_APK_PATH_FILE="${OPENCLASH_APK_PATH_FILE:-${OPENWRT_DIR}/.openclash-apk-path}"
# 固件产物目录（与 OpenWrt 目标目录结构绑定）
TARGET_DIR="${TARGET_DIR:-${OPENWRT_DIR}/bin/targets/mediatek/filogic}"

log() { printf '%s\n' "$*"; }
warn() { printf '  ⚠️  %s\n' "$*" >&2; }
die() {
    printf '  ❌ %s\n' "$*" >&2
    exit 1
}

# 仓库分支名 -> 上游 OpenWrt 分支名。
# 本仓库 master 跟踪上游 main（上游 master 只是别名），其余分支同名。
upstream_branch() {
    case "${1:-}" in
        master) printf 'main' ;;
        *) printf '%s' "${1:-}" ;;
    esac
}

# 需要 an8855 补丁与 commit 锁定的分支：仅上游 main。
is_mainline_branch() {
    [ "$(upstream_branch "${1:-}")" = "main" ]
}
