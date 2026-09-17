#!/bin/bash
# ============================================================
# Update VERIFIED_COMMIT from CI after successful master build
#
# 只替换文件中第一个非注释行(commit sha)，保留文件头的验证说明与
# "上次验证"记录。历史上本脚本用 heredoc 整体重写该文件，会把
# patches/VERIFIED_COMMIT 自带的维护说明和产物记录覆盖掉，导致
# 该文件的"人工验证契约"在 CI 运行后消失。
#
# Usage: scripts/update-verified-commit.sh <openwrt-dir> <patch-dir>
#   DRY_RUN=1 只打印将要做的变更
# ============================================================

set -euo pipefail

OPENWRT_DIR="${1:?Usage: $0 <openwrt-dir> <patch-dir>}"
REPO_PATCH_DIR="${2:?Usage: $0 <openwrt-dir> <patch-dir>}"
DRY_RUN="${DRY_RUN:-0}"

VERIFIED_COMMIT_FILE="$REPO_PATCH_DIR/VERIFIED_COMMIT"

# Get the current commit SHA from the OpenWrt checkout
CURRENT_SHA="$(git -C "$OPENWRT_DIR" rev-parse HEAD)"
SHORT_SHA="$(git -C "$OPENWRT_DIR" rev-parse --short HEAD)"

echo "Current OpenWrt commit: $CURRENT_SHA ($SHORT_SHA)"

# Read existing VERIFIED_COMMIT
EXISTING_SHA=""
if [ -f "$VERIFIED_COMMIT_FILE" ]; then
    EXISTING_SHA="$(grep -vE '^\s*(#|$)' "$VERIFIED_COMMIT_FILE" | head -n1 | tr -d '[:space:]' || true)"
    echo "Existing VERIFIED_COMMIT: $EXISTING_SHA"
fi

# Check if already up to date
if [ "$CURRENT_SHA" = "$EXISTING_SHA" ]; then
    echo "✅ VERIFIED_COMMIT already up to date ($SHORT_SHA)"
    exit 0
fi

echo "📝 Updating VERIFIED_COMMIT: ${EXISTING_SHA:-'(empty)'} → $CURRENT_SHA"

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY-RUN: Would write $CURRENT_SHA to $VERIFIED_COMMIT_FILE"
    echo "DRY-RUN: Would commit and push"
    exit 0
fi

if [ ! -f "$VERIFIED_COMMIT_FILE" ]; then
    printf '# OpenWrt main 已验证 commit 基准\n%s\n' "$CURRENT_SHA" > "$VERIFIED_COMMIT_FILE"
else
    # 替换第一个非注释行；若文件里还没有 commit 行，则追加一行。
    tmp="$(mktemp)"
    awk -v sha="$CURRENT_SHA" '
        !replaced && $0 !~ /^[[:space:]]*(#|$)/ { print sha; replaced=1; next }
        { print }
        END { if (!replaced) print sha }
    ' "$VERIFIED_COMMIT_FILE" > "$tmp"
    mv "$tmp" "$VERIFIED_COMMIT_FILE"
fi

echo "✅ Written to $VERIFIED_COMMIT_FILE (注释与验证记录保持不变)"

# Configure git for CI commit
cd "$(dirname "$REPO_PATCH_DIR")"  # Back to repo root
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Check if there are changes to commit
if git diff --quiet "$VERIFIED_COMMIT_FILE"; then
    echo "No changes to commit"
    exit 0
fi

# Commit and push
git add "$VERIFIED_COMMIT_FILE"
git commit -m "ci: update VERIFIED_COMMIT to $SHORT_SHA

Auto-updated after successful master build (${GITHUB_RUN_ID:-local}).
OpenWrt commit: $CURRENT_SHA"

echo "✅ Committed VERIFIED_COMMIT update"

git push origin HEAD:master

echo "✅ Pushed VERIFIED_COMMIT update to master"
