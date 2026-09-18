#!/bin/bash
# ============================================================
# Update VERIFIED_COMMIT from CI after successful master build
#
# This script extracts the current OpenWrt commit SHA from the
# built source tree and updates patches/VERIFIED_COMMIT, then
# commits and pushes the change.
#
# Usage: scripts/update-verified-commit.sh <openwrt-dir> <patch-dir>
# ============================================================

set -euo pipefail

OPENWRT_DIR="${1:?Usage: $0 <openwrt-dir> <patch-dir>}"
REPO_PATCH_DIR="${2:?Usage: $0 <openwrt-dir> <patch-dir>}"
DRY_RUN="${DRY_RUN:-0}"

# Get the current commit SHA from the OpenWrt checkout
cd "$OPENWRT_DIR"
CURRENT_SHA=$(git rev-parse HEAD)
SHORT_SHA=$(git rev-parse --short HEAD)

echo "Current OpenWrt commit: $CURRENT_SHA ($SHORT_SHA)"

# Read existing VERIFIED_COMMIT
EXISTING_SHA=""
if [ -f "$REPO_PATCH_DIR/VERIFIED_COMMIT" ]; then
    EXISTING_SHA=$(grep -vE '^\s*(#|$)' "$REPO_PATCH_DIR/VERIFIED_COMMIT" | head -n1 | tr -d '[:space:]' || true)
    echo "Existing VERIFIED_COMMIT: $EXISTING_SHA"
fi

# Check if already up to date
if [ "$CURRENT_SHA" = "$EXISTING_SHA" ]; then
    echo "✅ VERIFIED_COMMIT already up to date ($SHORT_SHA)"
    exit 0
fi

echo "📝 Updating VERIFIED_COMMIT: ${EXISTING_SHA:-'(empty)'} → $CURRENT_SHA"

if [ "$DRY_RUN" = "1" ]; then
    echo "DRY-RUN: Would write $CURRENT_SHA to $REPO_PATCH_DIR/VERIFIED_COMMIT"
    echo "DRY-RUN: Would commit and push"
    exit 0
fi

# Write new VERIFIED_COMMIT
cat > "$REPO_PATCH_DIR/VERIFIED_COMMIT" <<EOF
# VERIFIED_COMMIT - Auto-updated by CI on successful master build
# Last updated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Build: ${GITHUB_RUN_ID:-local}
# Commit: $CURRENT_SHA
$CURRENT_SHA
EOF

echo "✅ Written to $REPO_PATCH_DIR/VERIFIED_COMMIT"

# Configure git for CI commit
cd "$(dirname "$REPO_PATCH_DIR")"  # Back to repo root
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"

# Check if there are changes to commit
if git diff --quiet "$REPO_PATCH_DIR/VERIFIED_COMMIT"; then
    echo "No changes to commit"
    exit 0
fi

# Commit and push
git add "$REPO_PATCH_DIR/VERIFIED_COMMIT"
git commit -m "ci: update VERIFIED_COMMIT to $SHORT_SHA

Auto-updated after successful master build (${GITHUB_RUN_ID:-local}).
OpenWrt commit: $CURRENT_SHA"

echo "✅ Committed VERIFIED_COMMIT update"

# Push to origin
git push origin HEAD:master

echo "✅ Pushed VERIFIED_COMMIT update to master"