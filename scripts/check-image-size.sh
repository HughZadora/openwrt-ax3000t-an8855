#!/bin/bash
# ============================================================
# Build output size validation + flash checklist summary
#
# Background: the stock U-Boot has a load size limit for initramfs-FIT (measured 26MB boots,
# 27.9MB / 34MB fails to boot, kernel repeatedly panics/resets). This script automatically
# validates the initramfs output against the safe threshold after the build, and prints a copyable flash checklist.
#
# Usage (usually called by setup.sh build after make):
#   STRICT=1 scripts/check-image-size.sh <target-dir>
#     target-dir for example: bin/targets/mediatek/filogic
#   STRICT=1 exits 1 on over-limit (default); STRICT=0 warns only.
# ============================================================

set -euo pipefail

# ---- 可调阈值 -------------------------------------------------
# Stock U-Boot tested bootable limit 26MB; 1MB margin as the warning line.
STRICT="${STRICT:-1}"
HARD_LIMIT_MB="${HARD_LIMIT_MB:-26}"
WARN_LIMIT_MB="${WARN_LIMIT_MB:-25}"

# ---- 参数 ----------------------------------------------------
TARGET_DIR="${1:?用法: scripts/check-image-size.sh <target-dir>}"
[ -d "$TARGET_DIR" ] || { echo "[size-check] Directory not found: $TARGET_DIR" >&2; exit 1; }

HARD_LIMIT_BYTES=$((HARD_LIMIT_MB * 1024 * 1024))
WARN_LIMIT_BYTES=$((WARN_LIMIT_MB * 1024 * 1024))

fail=0

echo ""
echo "============================================================"
echo " Build output size validation (initramfs-FIT limit ${HARD_LIMIT_MB}MB)"
echo "============================================================"

# 只关心 initramfs 的 **FIT 内核镜像**(*-initramfs-kernel.bin / *.itb):这是原厂 U-Boot
# The file actually loaded into RAM, whose size is constrained by the limit. Note *-initramfs-factory.ubi is a UBI container
# container for NAND (with UBI header/erase-block alignment), larger than the FIT; U-Boot does not load it directly, so it is excluded from the size check.
files=()
while IFS= read -r f; do
    files+=("$f")
done < <(find "$TARGET_DIR" -maxdepth 1 -type f \
    \( -name '*-initramfs-kernel.bin' -o -name '*-initramfs-kernel.itb' -o -name '*-initramfs.itb' \) \
    | sort)

if [ "${#files[@]}" -eq 0 ]; then
    echo "[size-check] No initramfs output found; check whether the image was generated." >&2
    echo "[size-check] Expected directory: $TARGET_DIR" >&2
    exit 1
fi

for f in "${files[@]}"; do
    size=$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f")
    size_mb=$(awk -v s="$size" 'BEGIN{printf "%.1f", s/1048576}')
    flag="OK"
    if [ "$size" -gt "$HARD_LIMIT_BYTES" ]; then
        flag="超限(FAIL)"
        fail=1
    elif [ "$size" -gt "$WARN_LIMIT_BYTES" ]; then
        flag="critical (warning)"
    fi
    printf "  %-9s  %6s MB  %s\n" "$flag" "$size_mb" "$(basename "$f")"
done

echo ""
if [ "$fail" -eq 1 ]; then
    echo "❌ initramfs exceeds the stock U-Boot load limit (${HARD_LIMIT_MB}MB)."
    echo "   Use make menuconfig to trim kmod / tool set and rebuild, or temporarily pass with STRICT=0."
    if [ "$STRICT" = "1" ]; then
        exit 1
    else
        echo "   (STRICT=0, continuing but be aware of the risk)"
    fi
else
    echo "✅ initramfs size is within the safe threshold (≤ ${HARD_LIMIT_MB}MB)."
fi

echo ""
echo "============================================================"
echo " 刷机清单"
echo "============================================================"
# List flash-related outputs (with sha256)
for pat in '*-initramfs-factory.ubi' '*-squashfs-sysupgrade.bin'; do
    for f in "$TARGET_DIR"/*; do
        [ -e "$f" ] || continue
        case "$(basename "$f")" in
            $pat)
                printf "  %-6s  %s\n" "$(stat -c%s "$f" 2>/dev/null || stat -f%z "$f") bytes" "$(basename "$f")"
                printf "          sha256 %s\n" "$(sha256sum "$f" 2>/dev/null | cut -d' ' -f1)"
                ;;
        esac
    done
done
echo ""
