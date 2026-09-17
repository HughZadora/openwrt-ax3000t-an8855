#!/bin/bash
# ============================================================
# 构建产物体积校验 + 刷机清单汇总
#
# 背景:原厂 U-Boot 对 initramfs-FIT 有加载体积上限(实测 26MB 可启动,
# 27.9MB / 34MB 起不来,内核反复 panic/复位)。本脚本在固件编完后自动
# 校验 initramfs 产物是否落在安全阈值内,并打印可复制的刷机清单。
#
# 用法(通常由 setup.sh build 在 make 之后调用):
#   STRICT=1 scripts/check-image-size.sh <target-dir>
#     target-dir 例如: bin/targets/mediatek/filogic
#   STRICT=1 时超限即 exit 1(默认);STRICT=0 时仅告警。
# ============================================================

set -euo pipefail

# ---- 可调阈值 -------------------------------------------------
# 原厂 U-Boot 实测可启动上限 26MB;留 1MB 余量作为告警线。
STRICT="${STRICT:-1}"
HARD_LIMIT_MB="${HARD_LIMIT_MB:-26}"
WARN_LIMIT_MB="${WARN_LIMIT_MB:-25}"

# ---- 参数 ----------------------------------------------------
TARGET_DIR="${1:?用法: scripts/check-image-size.sh <target-dir>}"
[ -d "$TARGET_DIR" ] || { echo "[体积校验] 目录不存在: $TARGET_DIR" >&2; exit 1; }

HARD_LIMIT_BYTES=$((HARD_LIMIT_MB * 1024 * 1024))
WARN_LIMIT_BYTES=$((WARN_LIMIT_MB * 1024 * 1024))

fail=0

echo ""
echo "============================================================"
echo " 构建产物体积校验(initramfs-FIT 上限 ${HARD_LIMIT_MB}MB)"
echo "============================================================"

# 只关心 initramfs 的 **FIT 内核镜像**(*-initramfs-kernel.bin / *.itb):这是原厂 U-Boot
# 实际加载进 RAM 的文件,体积受上限约束。注意 *-initramfs-factory.ubi 是写给 NAND 的
# UBI 容器(含 UBI 头/擦除块对齐),比 FIT 大,U-Boot 不直接加载它,故不参与体积判定。
files=()
while IFS= read -r f; do
    files+=("$f")
done < <(find "$TARGET_DIR" -maxdepth 1 -type f \
    \( -name '*-initramfs-kernel.bin' -o -name '*-initramfs-kernel.itb' -o -name '*-initramfs.itb' \) \
    | sort)

if [ "${#files[@]}" -eq 0 ]; then
    echo "[体积校验] 未找到任何 initramfs 产物,请检查镜像是否成功生成。" >&2
    echo "[体积校验] 期望目录: $TARGET_DIR" >&2
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
        flag="临界(告警)"
    fi
    printf "  %-9s  %6s MB  %s\n" "$flag" "$size_mb" "$(basename "$f")"
done

echo ""
if [ "$fail" -eq 1 ]; then
    echo "❌ initramfs 超过原厂 U-Boot 加载上限(${HARD_LIMIT_MB}MB)。"
    echo "   请 make menuconfig 精简 kmod / 工具集后重编,或临时 STRICT=0 放行。"
    if [ "$STRICT" = "1" ]; then
        exit 1
    else
        echo "   (STRICT=0,继续但请知悉风险)"
    fi
else
    echo "✅ initramfs 体积在安全阈值内(≤ ${HARD_LIMIT_MB}MB)。"
fi

echo ""
echo "============================================================"
echo " 刷机清单"
echo "============================================================"
# 列出刷机相关产物(含 sha256)
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
