#!/bin/bash
# ============================================================
# 一键构建脚本 - Xiaomi Mi Router AX3000T (AN8855)
#
# 本脚本基于 OpenWrt 主线 (main, ~内核 6.18) 编译。
#
# 重要变化:
#   * 主线 OpenWrt 已原生支持 AN8855 交换芯片 (驱动),但**没有**独立的
#     an8855 启动布局目标,必须手工重建单 UBI 目标
#     (xiaomi_mi-router-ax3000t-an8855)。patches/ 里的补丁会自动打上。
#   * 原厂 U-Boot + AN8855 只能用**单 UBI 布局**才能持久启动;
#     官方 stock 双分区目标 (xiaomi_mi-router-ax3000t) 在本机会落回恢复页,
#     勿用。详见 docs/reference/router-state.md §0。
#   * 无自定义 fwx 内核补丁,保持纯净主线。
#   * OpenClash (luci-app-openclash) 以独立 apk 提供,不进固件(避免 initramfs
#     超过原厂 U-Boot 加载体积上限);装时 apk add 并自动拉 luci-compat 等依赖。
#   * 内核模块只能编译期打入(无法 apk 安装),本脚本预置了**精简工具集**:
#     zram、iptables+nftables 双栈 + 核心 netfilter、wireguard/veth/tun 隧道、
#     QoS(cake/fq-pie)、ext4、tcpdump/conntrack/ipset/tc-full 等诊断工具。
#     原"完整工具集"含 179 个 kmod,使 initramfs-FIT 达 27.9MB,超过原厂 U-Boot
#     加载上限(26MB 可启动)导致反复 panic/复位,已精简以适配。
#
# 本脚本只做参数解析与步骤编排,每个步骤在 scripts/build/ 下单独成文件,
# 并与 .github/workflows/ci.yml 共用同一套实现(避免本地与 CI 两份拷贝漂移)。
#
# 用法:
#   1) bash setup.sh                     # 只做克隆 + feeds + 配置 (main 分支)
#   2) bash setup.sh build               # 直接开始编译 (main 分支)
#   3) bash setup.sh --branch openwrt-24.10 [build]
#                                        # 换分支编译;非 main 分支跳过补丁与 commit 锁定
#   (--branch 与 build 可任意顺序;默认 main,行为与旧版一致)
# ============================================================

set -e

# 先做自身与全部构建步骤的 bash 语法自检,语法错误第一时间失败,避免编到一半才崩。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_LIB_DIR="${SCRIPT_DIR}/scripts/build"
bash -n "$0"
for s in "${BUILD_LIB_DIR}"/*.sh; do
	bash -n "$s"
done

# ---- 参数解析:支持 --branch <分支> 与位置参数 build,任意顺序 ----
BRANCH="main"
BUILD_MODE=0
while [ $# -gt 0 ]; do
	case "$1" in
	--branch)
		[ $# -ge 2 ] || {
			echo "  ❌ --branch 需带分支名,示例: bash setup.sh --branch openwrt-24.10" >&2
			exit 1
		}
		BRANCH="$2"
		shift 2
		;;
	--branch=*)
		BRANCH="${1#*=}"
		shift
		;;
	build)
		BUILD_MODE=1
		shift
		;;
	*)
		echo "  ❌ 未知参数: $1 (支持: build / --branch <分支>)" >&2
		exit 1
		;;
	esac
done
if [ -z "$BRANCH" ]; then
	echo "  ❌ --branch 分支名为空" >&2
	exit 1
fi

# ---- 步骤编排 ----
# 路径(OpenWrt 源码树 / patches / OpenClash feed)由 scripts/build/env.sh
# 统一推导: 默认相对本仓库根目录,不再依赖调用者的当前工作目录。
bash "${BUILD_LIB_DIR}/prepare-source.sh" --branch "$BRANCH"
bash "${BUILD_LIB_DIR}/apply-an8855-patches.sh" --branch "$BRANCH"
bash "${BUILD_LIB_DIR}/configure-feeds.sh"
bash "${BUILD_LIB_DIR}/configure-config.sh"
bash "${BUILD_LIB_DIR}/inject-firstboot-defaults.sh"

if [ "$BUILD_MODE" = "1" ]; then
	bash "${BUILD_LIB_DIR}/compile-firmware.sh"
	bash "${BUILD_LIB_DIR}/report-artifacts.sh" gate
	bash "${BUILD_LIB_DIR}/compile-openclash-apk.sh"
	bash "${BUILD_LIB_DIR}/report-artifacts.sh" summary
else
	echo ""
	echo "============================================"
	echo "  准备完成!请执行:"
	echo "    make menuconfig   # 可微调软件包(目标已预置)"
	echo "    make -j\$(nproc) V=s | tee build.log"
	echo "============================================"
fi
