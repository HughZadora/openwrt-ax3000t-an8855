#!/bin/bash
# ============================================================
# 步骤 1: 准备 OpenWrt 源码树（克隆 + VERIFIED_COMMIT 锁定）
#
# 用法: prepare-source.sh [--branch <分支>] [--lock|--no-lock]
#   --branch 可为仓库分支名(master)或上游分支名(main/openwrt-24.10)，
#            由 env.sh 的 upstream_branch() 归一化后用于 git clone。
#   --lock   锁定到 patches/VERIFIED_COMMIT（仅上游 main 有意义）
#   --no-lock 跟随分支最新（PR 构建、非 main 分支用）
#   缺省: 上游 main 锁定；其它分支不锁定（与旧 setup.sh 行为一致）。
# ============================================================

set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/env.sh"

BRANCH="main"
LOCK=""

while [ $# -gt 0 ]; do
    case "$1" in
        --branch)
            [ $# -ge 2 ] || die "--branch 需带分支名,示例: --branch openwrt-24.10"
            BRANCH="$2"
            shift 2
            ;;
        --branch=*)
            BRANCH="${1#*=}"
            shift
            ;;
        --lock) LOCK=1; shift ;;
        --no-lock) LOCK=0; shift ;;
        *) die "未知参数: $1 (支持: --branch <分支> / --lock / --no-lock)" ;;
    esac
done

[ -n "$BRANCH" ] || die "--branch 分支名为空"
UPSTREAM="$(upstream_branch "$BRANCH")"

log ""
log "=== 步骤 1: 准备 OpenWrt 源码 (仓库分支: $BRANCH, 上游分支: $UPSTREAM) ==="

if [ ! -d "$OPENWRT_DIR" ]; then
    git clone --depth 1 --branch "$UPSTREAM" --single-branch \
        "$OPENWRT_GIT_URL" "$OPENWRT_DIR"
else
    log "  已存在 $OPENWRT_DIR,跳过克隆"
fi

# 缺省锁定策略：VERIFIED_COMMIT 记录的是上游 main 的已验证 commit，
# 其它分支（如 openwrt-24.10）历史不同，不能 checkout 该 sha。
if [ -z "$LOCK" ]; then
    if is_mainline_branch "$BRANCH"; then
        LOCK=1
    else
        LOCK=0
    fi
fi

if [ "$LOCK" != "1" ]; then
    if is_mainline_branch "$BRANCH"; then
        warn "未锁定 commit(--no-lock),跟随 main 最新,补丁可能漂移失效。"
    else
        log "  非 main 分支($UPSTREAM),跳过 commit 锁定"
    fi
    exit 0
fi

if ! is_mainline_branch "$BRANCH"; then
    warn "非 main 分支($UPSTREAM)无法使用 VERIFIED_COMMIT 锁定,已跳过。"
    exit 0
fi

if [ ! -f "$VERIFIED_COMMIT_FILE" ]; then
    warn "未找到 $VERIFIED_COMMIT_FILE,跟随 main 最新,补丁可能漂移失效。"
    exit 0
fi

OPENWRT_COMMIT="$(grep -vE '^\s*(#|$)' "$VERIFIED_COMMIT_FILE" | head -n1 | tr -d '[:space:]' || true)"
if [ -z "$OPENWRT_COMMIT" ]; then
    warn "VERIFIED_COMMIT 为空,跟随 main 最新,补丁可能漂移失效。"
    exit 0
fi

log "  锁定到已验证 commit: $OPENWRT_COMMIT"
git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_COMMIT" \
    || die "无法获取 commit $OPENWRT_COMMIT,检查 $VERIFIED_COMMIT_FILE"

git -C "$OPENWRT_DIR" checkout --force "$OPENWRT_COMMIT"

# 锁定后立即校验 HEAD，避免"看似锁定实则停留在别的 commit"。
HEAD_SHA="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
[ "$HEAD_SHA" = "$OPENWRT_COMMIT" ] \
    || die "checkout 后 HEAD($HEAD_SHA) 与 VERIFIED_COMMIT($OPENWRT_COMMIT) 不一致。"

log "  已锁定到: $HEAD_SHA"
