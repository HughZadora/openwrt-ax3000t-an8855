#!/bin/bash
# ============================================================
# 步骤 7: 编译固件（固件本体不含 OpenClash）
#
# 用法: compile-firmware.sh
#
# 说明: OpenWrt 的 make 输出量极大，故写入 <openwrt-dir>/build.log。
#       本脚本启用 pipefail，make 失败会立即以 make 的退出码失败，
#       不会被 tee 的成功状态掩盖（历史问题: setup.sh 只有 set -e，
#       编译错误被吞掉，失败原因被推迟到后续体积校验，误导诊断）。
# ============================================================

set -euo pipefail
BUILD_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./env.sh
source "${BUILD_LIB_DIR}/env.sh"

[ -d "$OPENWRT_DIR" ] || die "OpenWrt 源码树不存在: $OPENWRT_DIR（先执行 prepare-source.sh）"

cd "$OPENWRT_DIR"

log ""
log "=== 步骤 7: 开始编译(固件不含 OpenClash) ==="
log "  运行: make -j\$(nproc) V=s | tee build.log"
make -j"$(nproc)" V=s 2>&1 | tee build.log
