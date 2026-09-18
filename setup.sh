#!/bin/bash
# ============================================================
# One-click build script - Xiaomi Mi Router AX3000T (AN8855)
#
# This script builds from OpenWrt mainline (main, ~kernel 6.18).
#
# Important changes:
#   * Mainline OpenWrt natively supports the AN8855 switch chip (driver), but has no
#     standalone an8855 boot-layout target; the single-UBI target must be rebuilt
#     manually (xiaomi_mi-router-ax3000t-an8855). Patches in patches/ are applied automatically.
#   * Stock U-Boot + AN8855 can only boot persistently with a **single-UBI layout**;
#     the official stock dual-partition target (xiaomi_mi-router-ax3000t) falls back
#     to the recovery page on this device. Do not use it. See docs/reference/router-state.md §0.
#   * No custom fwx kernel patches; pure mainline.
#   * OpenClash (luci-app-openclash) is provided as a separate apk, not in the firmware
#     exceeds the stock U-Boot load size limit); apk add pulls luci-compat deps at install time.
#   * Kernel modules can only be built in at compile time (cannot be apk-installed); this script pre-seeds a **trimmed tool set**:
#     zram、iptables+nftables 双栈 + 核心 netfilter、wireguard/veth/tun 隧道、
#     QoS(cake/fq-pie)、ext4、tcpdump/conntrack/ipset/tc-full 等诊断工具。
#     The original "full tool set" contained 179 kmods, pushing initramfs-FIT to 27.9MB, exceeding the stock U-Boot
#     load limit (26MB boots) causing repeated panic/reset; trimmed to fit.
#
# 用法:
#   1) bash setup.sh                     # 只做克隆 + feeds + 配置 (main 分支)
#   2) bash setup.sh build               # 直接开始编译 (main 分支)
#   3) bash setup.sh --branch openwrt-24.10 [build]
#                                        # switch branch for building; non-main branches skip patches and commit locking
#   (--branch and build can be in any order; defaults to main, same behaviour as the old version)
# ============================================================

set -e

# Run bash syntax self-check on this script and its dependencies first, failing immediately on syntax errors to avoid crashing mid-build.
bash -n "$0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
bash -n "${SCRIPT_DIR}/scripts/check-image-size.sh"

# ---- Argument parsing: supports --branch <branch> and positional build, in any order ----
BRANCH="main"
BUILD_MODE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --branch)
            [ $# -ge 2 ] || { echo "  ❌ --branch requires a branch name, e.g.: bash setup.sh --branch openwrt-24.10" >&2; exit 1; }
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
    echo "  ❌ --branch branch name is empty" >&2
    exit 1
fi

export OPENWRT_DIR="$(pwd)/openwrt-ax3000t"
# The outer repository patches/ directory (with the an8855 target patches), relative to this script
export REPO_PATCH_DIR="$(cd "$(dirname "$0")" && pwd)/patches"
# This repository scripts/ directory (post-build size check etc.)
export SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)/scripts"
OPENCLASH_URL="https://github.com/vernesong/OpenClash.git"
OPENCLASH_CFG="src-git openclash ${OPENCLASH_URL}"

# Lock to a verified-buildable main commit (prevents mainline drift from invalidating patches).
# Value provided by patches/VERIFIED_COMMIT; blank follows main latest (not recommended).
# 切换/更新:构建前把新 sha 写进 patches/VERIFIED_COMMIT 并在 dry-run 全过后再 build。
if [ -f "$REPO_PATCH_DIR/VERIFIED_COMMIT" ]; then
    # Take the first non-empty, non-comment line as the commit sha
    OPENWRT_COMMIT="$(grep -vE '^\s*(#|$)' "$REPO_PATCH_DIR/VERIFIED_COMMIT" | head -n1 | tr -d '[:space:]' || true)"
else
    OPENWRT_COMMIT=""
fi

echo ""
echo "=== 步骤 1: 克隆 OpenWrt (分支: $BRANCH) ==="
if [ ! -d "$OPENWRT_DIR" ]; then
    git clone --depth 1 --branch "$BRANCH" --single-branch \
        https://git.openwrt.org/openwrt/openwrt.git "$OPENWRT_DIR"
fi
# Commit locking only applies to main (VERIFIED_COMMIT records the verified main-branch commit).
# Other branches (e.g. openwrt-24.10) have different history and cannot checkout that sha directly, so locking is skipped.
if [ "$BRANCH" = "main" ] && [ -n "$OPENWRT_COMMIT" ]; then
    echo "  锁定到已验证 commit: $OPENWRT_COMMIT"
    git -C "$OPENWRT_DIR" fetch --depth 1 origin "$OPENWRT_COMMIT" \
        || { echo "  无法获取 commit $OPENWRT_COMMIT,检查 patches/VERIFIED_COMMIT" >&2; exit 1; }
    git -C "$OPENWRT_DIR" checkout --force "$OPENWRT_COMMIT"
elif [ "$BRANCH" = "main" ]; then
    echo "  ⚠️ OPENWRT_COMMIT not set (patches/VERIFIED_COMMIT missing), following main latest, patches may drift."
else
    echo "  Non-main branch ($BRANCH), skipping commit locking and an8855 patches, following branch latest."
fi

cd "$OPENWRT_DIR"

echo ""
echo "=== 步骤 2: 添加 OpenClash feed ==="
# 注意:必须把 feed 加到官方的 feeds.conf.default(含 luci/packages 等官方源),
# rather than only creating feeds.conf (that would make OpenWrt only recognise feeds.conf and drop the official sources).
if [ ! -f feeds.conf ]; then
    cp feeds.conf.default feeds.conf
fi
if ! grep -q "OpenClash" feeds.conf; then
    cat >> feeds.conf <<EOF
# OpenClash (Clash/Mihomo 客户端)
${OPENCLASH_CFG}
EOF
    echo "  已添加: ${OPENCLASH_CFG}"
else
    echo "  OpenClash feed 已存在,跳过"
fi

echo ""
echo "=== Step 2.5: Apply the an8855 single-UBI target patches (main branch only, critical!) ==="
# Mainline main only has stock dual-partition / ubootmod targets; AN8855 + stock U-Boot requires
# a standalone single-UBI target to boot persistently. Patch files are frozen in the outer repository patches/.
# If already applied (device already defined in filogic.mk), skip to avoid duplicate patch errors.
# Non-main branches (e.g. openwrt-24.10) ship the an8855 single-UBI target natively; no patches needed, skip entirely.
if [ "$BRANCH" != "main" ]; then
    echo "  Non-main branch ($BRANCH), ships the an8855 single-UBI target, skipping patch application"
elif grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
    echo "  an8855 target already exists, skipping patch application"
else
    echo "  复制 DTS ..."
    cp "${REPO_PATCH_DIR}/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts" \
       target/linux/mediatek/dts/
    echo "  Applying filogic.mk / platform.sh / 02_network patches ..."
    # Dry-run full validation first; if any hunk fails to match (mainline drifted), fail entirely with a friendly message,
    # avoiding a crash mid-build due to patch issues.
    for p in "${REPO_PATCH_DIR}"/*.patch; do
        echo "    dry-run: $(basename "$p")"
        if ! patch -p1 --forward --dry-run -i "$p"; then
            echo "  ❌ Patch $(basename "$p") cannot be applied: main has drifted." >&2
            echo "     方案A: 把 main 锁定到 patches/VERIFIED_COMMIT 里的已验证 commit。" >&2
            echo "     Plan B: fix this patch manually and retry." >&2
            exit 1
        fi
    done
    for p in "${REPO_PATCH_DIR}"/*.patch; do
        patch -p1 --forward -i "$p"
    done
    echo "  an8855 target patches applied"
    # After application, explicitly verify key symbols appeared, preventing "looks successful but did nothing".
    if ! grep -q "Device/xiaomi_mi-router-ax3000t-an8855" target/linux/mediatek/image/filogic.mk; then
        echo "  ❌ After application, filogic.mk does not contain the an8855 target; patch did not take effect." >&2
        exit 1
    fi
    if ! grep -q "xiaomi,mi-router-ax3000t-an8855" target/linux/mediatek/filogic/base-files/lib/upgrade/platform.sh; then
        echo "  ❌ After application, platform.sh does not contain the an8855 upgrade entry; patch did not take effect." >&2
        exit 1
    fi
    echo "  Patch effectiveness verification passed."
fi

echo ""
echo "=== 步骤 3: 更新并安装 feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo ""
echo "=== 步骤 4: 生成默认配置 ==="
make defconfig

echo ""
echo "=== 步骤 5: 预置本设备目标 + OpenClash + LuCI ==="
# Seed .config with standard Kconfig symbols, then run defconfig to auto-resolve dependencies.
# (符号名遵循 OpenWrt metadata 约定:
#    CONFIG_TARGET_<target>_<subtarget>_DEVICE_<device>)
# Clear any potentially existing related lines first, avoiding "key defined multiple times" warnings/overwrites.
# Clear all symbols we are about to write, ensuring the script is re-runnable (multiple runs do not produce duplicate keys).
for s in \
    TARGET_mediatek TARGET_mediatek_filogic \
    TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855 \
    VERSIONOPT VERSION_REPO \
    PACKAGE_luci PACKAGE_luci-ssl LUCI_LANG_zh_Hans \
    PACKAGE_luci-compat PACKAGE_luci-lua-runtime \
    PACKAGE_luci-mod-dsl PACKAGE_luci-i18n-dsl-zh-cn \
    PACKAGE_luci-app-openclash PACKAGE_luci-app-nlbwmon \
    PACKAGE_tailscale PACKAGE_luci-app-tailscale-community \
    PACKAGE_iptables PACKAGE_iptables-nft PACKAGE_ip6tables-nft \
    PACKAGE_xtables-legacy PACKAGE_xtables-nft \
    PACKAGE_iptables-mod-extra PACKAGE_iptables-mod-conntrack-extra \
    PACKAGE_iptables-mod-ipopt PACKAGE_iptables-mod-iprange \
    PACKAGE_iptables-mod-filter PACKAGE_iptables-mod-hashlimit \
    PACKAGE_iptables-mod-nat-extra PACKAGE_iptables-mod-trace \
    PACKAGE_iptables-mod-u32 PACKAGE_iptables-mod-ipset \
    PACKAGE_kmod-ipt-core PACKAGE_kmod-ipt-extra \
    PACKAGE_kmod-ipt-nat PACKAGE_kmod-ipt-nat-extra PACKAGE_kmod-ipt-nat6 \
    PACKAGE_kmod-ipt-conntrack PACKAGE_kmod-ipt-conntrack-extra \
    PACKAGE_kmod-ipt-conntrack-label PACKAGE_kmod-ipt-ipopt \
    PACKAGE_kmod-ipt-iprange PACKAGE_kmod-ipt-filter \
    PACKAGE_kmod-ipt-hashlimit PACKAGE_kmod-ipt-ipset \
    PACKAGE_kmod-ipt-offload PACKAGE_kmod-ipt-raw PACKAGE_kmod-ipt-raw6 \
    PACKAGE_kmod-ipt-u32 PACKAGE_kmod-ipt-physdev \
    PACKAGE_kmod-ipt-rpfilter PACKAGE_kmod-ipt-socket \
    PACKAGE_kmod-ipt-tee PACKAGE_kmod-ipt-tproxy \
    PACKAGE_kmod-ipt-checksum PACKAGE_kmod-ipt-led \
    PACKAGE_kmod-ipt-nflog PACKAGE_kmod-ipt-nfqueue \
    PACKAGE_kmod-ipt-cluster PACKAGE_kmod-ipt-ipsec \
    PACKAGE_kmod-ipt-debug \
    PACKAGE_kmod-nft-bridge PACKAGE_kmod-nft-compat \
    PACKAGE_kmod-nft-connlimit PACKAGE_kmod-nft-queue \
    PACKAGE_kmod-nft-socket PACKAGE_kmod-nft-dup-inet \
    PACKAGE_kmod-nft-netdev PACKAGE_kmod-nft-xfrm PACKAGE_kmod-nft-arp \
    PACKAGE_kmod-nf-nat6 PACKAGE_kmod-nf-ipt PACKAGE_kmod-nf-ipt6 \
    PACKAGE_kmod-nf-ipvs PACKAGE_kmod-nf-ipvs-ftp PACKAGE_kmod-nf-ipvs-sip \
    PACKAGE_kmod-nf-nathelper \
    PACKAGE_kmod-nf-nathelper-amanda PACKAGE_kmod-nf-nathelper-broadcast \
    PACKAGE_kmod-nf-nathelper-extra PACKAGE_kmod-nf-nathelper-h323 \
    PACKAGE_kmod-nf-nathelper-irc PACKAGE_kmod-nf-nathelper-netbios \
    PACKAGE_kmod-nf-nathelper-pptp PACKAGE_kmod-nf-nathelper-sane \
    PACKAGE_kmod-nf-nathelper-sip PACKAGE_kmod-nf-nathelper-snmp \
    PACKAGE_kmod-nf-nathelper-tftp PACKAGE_kmod-nf-conncount \
    PACKAGE_kmod-nf-socket PACKAGE_kmod-nf-dup-inet \
    PACKAGE_kmod-nfnetlink-cthelper PACKAGE_kmod-nfnetlink-cttimeout \
    PACKAGE_kmod-nfnetlink-log PACKAGE_kmod-nfnetlink-queue \
    PACKAGE_kmod-gre PACKAGE_kmod-gre6 PACKAGE_kmod-ipip \
    PACKAGE_kmod-sit PACKAGE_kmod-ip6-tunnel PACKAGE_kmod-ip-vti \
    PACKAGE_kmod-ip6-vti PACKAGE_kmod-iptunnel4 PACKAGE_kmod-iptunnel6 \
    PACKAGE_kmod-vxlan PACKAGE_kmod-geneve PACKAGE_kmod-fou \
    PACKAGE_kmod-fou6 PACKAGE_kmod-udptunnel4 PACKAGE_kmod-udptunnel6 \
    PACKAGE_kmod-wireguard PACKAGE_kmod-veth PACKAGE_kmod-l2tp \
    PACKAGE_kmod-l2tp-eth PACKAGE_kmod-l2tp-ip PACKAGE_kmod-pppol2tp \
    PACKAGE_kmod-ppp-synctty PACKAGE_kmod-bonding PACKAGE_kmod-team \
    PACKAGE_kmod-team-mode-activebackup PACKAGE_kmod-team-mode-broadcast \
    PACKAGE_kmod-team-mode-loadbalance PACKAGE_kmod-team-mode-random \
    PACKAGE_kmod-team-mode-roundrobin PACKAGE_kmod-macsec \
    PACKAGE_kmod-mpls PACKAGE_kmod-vrf PACKAGE_kmod-sctp \
    PACKAGE_kmod-tcp-bbr PACKAGE_kmod-tcp-hybla PACKAGE_kmod-tcp-scalable \
    PACKAGE_kmod-netem PACKAGE_kmod-ipsec PACKAGE_kmod-ipsec4 \
    PACKAGE_kmod-ipsec6 PACKAGE_kmod-xfrm-interface \
    PACKAGE_kmod-sched-core PACKAGE_kmod-sched-cake \
    PACKAGE_kmod-sched-fq-pie PACKAGE_kmod-sched-skbprio \
    PACKAGE_kmod-sched-flower PACKAGE_kmod-sched-bpf \
    PACKAGE_kmod-sched-pie PACKAGE_kmod-sched-red \
    PACKAGE_kmod-sched-prio PACKAGE_kmod-sched-drr \
    PACKAGE_kmod-sched-mqprio PACKAGE_kmod-sched-mqprio-common \
    PACKAGE_kmod-sched-ctinfo PACKAGE_kmod-sched-connmark \
    PACKAGE_kmod-sched-ipset PACKAGE_kmod-sched-act-vlan \
    PACKAGE_kmod-sched-act-police PACKAGE_kmod-sched-act-sample \
    PACKAGE_kmod-fs-ext4 PACKAGE_kmod-fs-f2fs PACKAGE_kmod-fs-exfat \
    PACKAGE_kmod-fs-vfat PACKAGE_kmod-fs-msdos PACKAGE_kmod-fs-ntfs3 \
    PACKAGE_kmod-fs-isofs PACKAGE_kmod-fs-hfsplus PACKAGE_kmod-fs-udf \
    PACKAGE_kmod-fs-configfs PACKAGE_kmod-fs-exportfs \
    PACKAGE_kmod-fs-btrfs PACKAGE_kmod-fs-xfs \
    PACKAGE_kmod-usb-storage PACKAGE_kmod-usb-storage-uas \
    PACKAGE_kmod-usb-storage-extras PACKAGE_kmod-usb-printer \
    PACKAGE_kmod-usb-serial PACKAGE_kmod-usb-serial-ch341 \
    PACKAGE_kmod-usb-serial-ftdi PACKAGE_kmod-usb-serial-cp210x \
    PACKAGE_kmod-usb-serial-pl2303 PACKAGE_kmod-usb-serial-option \
    PACKAGE_kmod-usb-serial-wwan PACKAGE_kmod-usb-net-cdc-eem \
    PACKAGE_kmod-usb-net-cdc-ether PACKAGE_kmod-usb-net-cdc-mbim \
    PACKAGE_kmod-usb-net-cdc-ncm PACKAGE_kmod-usb-net-cdc-subset \
    PACKAGE_kmod-usb-net-huawei-cdc-ncm PACKAGE_kmod-usb-gadget \
    PACKAGE_kmod-usb-gadget-eth PACKAGE_kmod-usb-gadget-serial \
    PACKAGE_kmod-usb-gadget-mass-storage \
    PACKAGE_kmod-nls-cp437 PACKAGE_kmod-nls-cp850 PACKAGE_kmod-nls-cp852 \
    PACKAGE_kmod-nls-cp866 PACKAGE_kmod-nls-cp932 PACKAGE_kmod-nls-cp936 \
    PACKAGE_kmod-nls-cp950 PACKAGE_kmod-nls-iso8859-1 \
    PACKAGE_kmod-nls-iso8859-15 PACKAGE_kmod-nls-utf8 \
    PACKAGE_kmod-nls-ucs2-utils \
    PACKAGE_kmod-softdog PACKAGE_kmod-mtdoops PACKAGE_kmod-fixed-phy \
    PACKAGE_kmod-phylink PACKAGE_kmod-of-mdio PACKAGE_kmod-input-evdev \
    PACKAGE_kmod-input-gpio-keys PACKAGE_kmod-input-gpio-keys-polled \
    PACKAGE_kmod-input-uinput PACKAGE_kmod-leds-pwm PACKAGE_kmod-leds-uleds \
    PACKAGE_kmod-zram PACKAGE_zram-swap \
    PACKAGE_conntrack PACKAGE_conntrackd PACKAGE_ipset \
    PACKAGE_ip-full PACKAGE_tc-full PACKAGE_ip-bridge \
    PACKAGE_tcpdump PACKAGE_iperf3 PACKAGE_ethtool PACKAGE_mtr-json \
    PACKAGE_nlbwmon PACKAGE_curl PACKAGE_wget-ssl PACKAGE_nano \
    PACKAGE_openssl-util PACKAGE_openssh-client PACKAGE_coreutils \
    PACKAGE_htop PACKAGE_iftop; do
    sed -i "/^CONFIG_$s=/d; /^# CONFIG_${s} is not set\$/d" .config
done
cat >> .config <<'EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

# Package source (apk) mirror: switch to USTC for faster domestic downloads
# Note: VERSION_* lives under the VERSIONOPT menu; CONFIG_VERSIONOPT=y must be set first
CONFIG_VERSIONOPT=y
CONFIG_VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/snapshots"

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# Remove unused default LuCI modules (useless for a router; keeps the menu clean)
# CONFIG_PACKAGE_luci-mod-dsl is not set
# CONFIG_PACKAGE_luci-i18n-dsl-zh-cn is not set

# ⚠️ OpenClash is no longer built into the firmware: its apk is ~8MB (with clash core), pushing initramfs-FIT
# beyond the stock U-Boot load size limit (26MB boots, 34MB does not). Instead it is compiled separately as a
# package; install with `apk add luci-app-openclash` from the apk source. When needed, the last step
# make package/.../compile produces it separately.
# ── But luci-compat (+luci-lua-runtime) must be kept: luci-base rendering depends on its
#    luci.ucodebridge module; missing it reports "module 'luci.ucodebridge' not found".
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
# CONFIG_PACKAGE_luci-app-openclash=y
CONFIG_PACKAGE_luci-app-nlbwmon=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y


# ================= Tool set (trimmed, size-controlled to fit the stock U-Boot) =================
# Background: 5a26684 added 179 kmods at once, pushing initramfs-FIT to 27.9MB, exceeding the stock
# U-Boot load limit (26MB boots, 27.9MB does not, kernel repeatedly panics/resets). Only
# core commonly-used modules are kept; heavy filesystems (btrfs/xfs/ntfs3 etc.), USB drivers, unusual tunnels/protocols,
# extra sched variants and boot-risk items (mtdoops/softdog/phylink/of-mdio/fixed-phy),
# are removed, bringing initramfs back within 26MB. Additional features can be selected in make menuconfig,
# or compiled as a separate apk and installed.
# --- zram:内存压缩 ---
CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y

# --- 防火墙:iptables + nftables 双栈(fw4 默认 nftables) ---
CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_ip6tables-nft=y
CONFIG_PACKAGE_xtables-legacy=y
CONFIG_PACKAGE_xtables-nft=y

# --- nftables/iptables 内核模块(核心,OpenClash 兼容/Tailscale 常用) ---
CONFIG_PACKAGE_kmod-ipt-core=y
CONFIG_PACKAGE_kmod-ipt-nat=y
CONFIG_PACKAGE_kmod-ipt-nat6=y
CONFIG_PACKAGE_kmod-ipt-conntrack=y
CONFIG_PACKAGE_kmod-ipt-ipset=y
CONFIG_PACKAGE_kmod-ipt-offload=y
CONFIG_PACKAGE_kmod-nft-bridge=y
CONFIG_PACKAGE_kmod-nft-compat=y
CONFIG_PACKAGE_kmod-nft-netdev=y
CONFIG_PACKAGE_kmod-nf-ipt=y
CONFIG_PACKAGE_kmod-nf-ipt6=y
CONFIG_PACKAGE_kmod-nf-nathelper=y
CONFIG_PACKAGE_kmod-nf-nathelper-extra=y
CONFIG_PACKAGE_kmod-nf-nathelper-pptp=y
CONFIG_PACKAGE_kmod-nf-nathelper-tftp=y
CONFIG_PACKAGE_kmod-nf-conncount=y

# --- 隧道/虚拟网卡(常用) ---
CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

# --- QoS / tc (keeps cake/fq-pie; others as needed) ---
CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-fq-pie=y

# --- Filesystem (ext4 only; heavy filesystems removed to control size) ---
CONFIG_PACKAGE_kmod-fs-ext4=y

# --- 连接跟踪 / IP 集 / 路由 / 流量工具 ---
CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ip-bridge=y
CONFIG_PACKAGE_tc-full=y

# --- 网络诊断/抓包 ---
CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_mtr-json=y
CONFIG_PACKAGE_nlbwmon=y

# --- 基础实用工具 ---
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iftop=y
EOF
make defconfig

echo ""
echo "  Auto-selected:"
echo "    Target Profile -> Xiaomi Mi Router AX3000T (AN8855, 单 UBI, 原厂 U-Boot)"
echo "    LuCI (+ SSL, Chinese)"
echo "    OpenClash compiled only as a separate apk (not in firmware) / Tailscale + luci-app-tailscale-community"
echo "    zram 内存压缩 / iptables+nftables 双栈 / 核心 netfilter / wireguard 隧道 / QoS(cake/fq-pie)"
echo "    tcpdump / conntrack / ipset / tc-full / ext4 / diagnostic tools (trimmed, fits the stock U-Boot size limit)"
echo ""
echo "  如需调整运行: make menuconfig"

echo ""
echo "=== 步骤 6: 注入首次启动定制(IP 192.168.31.1 / WiFi 自动开启) ==="
UCIDEF_DIR="package/base-files/files/etc/uci-defaults"
mkdir -p "$UCIDEF_DIR"
cat > "$UCIDEF_DIR/99-router-home-custom" <<'EOF'
#!/bin/sh
# 首次启动定制:
#   1) LAN default IP changed to 192.168.31.1 (Xiaomi convention)
#   2) WiFi enabled by default (2.4G / 5G, unencrypted) for cable-free configuration

# --- LAN IP ---
uci -q set network.lan.ipaddr='192.168.31.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q commit network

# --- WiFi 启用 + 开放 SSID ---
# The 2.4G and 5G wifi-device sections are typically radio0 / radio1
for radio in radio0 radio1; do
    [ -n "$(uci -q get wireless.$radio)" ] || continue
    uci -q set wireless.$radio.disabled='0'

    iface="$(uci -q get wireless.$radio | sed -n 's/.*\(default_radio[0-9]*\).*/\1/p')"
    [ -z "$iface" ] && iface="default_$radio"
    if [ -n "$(uci -q get wireless.$iface)" ]; then
        uci -q set wireless.$iface.disabled='0'
        uci -q set wireless.$iface.encryption='none'
        case "$radio" in
            radio0) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T' ;;
            radio1) uci -q set wireless.$iface.ssid='OpenWrt-AX3000T-5G' ;;
        esac
    fi
done
uci -q commit wireless

# 立即生效
wifi reload 2>/dev/null

exit 0
EOF
chmod +x "$UCIDEF_DIR/99-router-home-custom"
echo "  已注入: $UCIDEF_DIR/99-router-home-custom"
echo "  首次启动: LAN=192.168.31.1, WiFi SSID: OpenWrt-AX3000T / OpenWrt-AX3000T-5G (无加密)"
echo "  Please set the root password and WiFi encryption in LuCI as soon as possible!"

if [ "$BUILD_MODE" = "1" ]; then
    echo ""
    echo "=== Step 7: Start build (firmware does not include OpenClash) ==="
    echo "  运行: make -j\$(nproc) V=s | tee build.log"
    make -j"$(nproc)" V=s 2>&1 | tee build.log

    echo ""
    echo "=== Step 7.5: initramfs size validation (stock U-Boot limit) ==="
    TARGET_DIR="$OPENWRT_DIR/bin/targets/mediatek/filogic"
    STRICT=1 bash "${SCRIPT_DIR}/check-image-size.sh" "$TARGET_DIR" \
        || { echo "  ❌ initramfs over limit, stopping OpenClash build to avoid continuing on a bad output." >&2; exit 1; }

    echo ""
echo "=== Step 8: Build OpenClash separately as an apk (not in firmware, install with apk add) ==="
    echo "  运行: make package/feeds/openclash/luci-app-openclash/compile V=s"
    make package/feeds/openclash/luci-app-openclash/compile V=s 2>&1 | tee -a build.log
    # 校验 apk 确实生成
    APK_GLOB="$OPENWRT_DIR/bin/packages/aarch64_cortex-a53/openclash/luci-app-openclash-*.apk"
    if ! ls $APK_GLOB >/dev/null 2>&1; then
        echo "  ❌ 未生成 OpenClash apk(路径:$APK_GLOB),请检查 openclash feed 是否安装成功。" >&2
        exit 1
    fi
    echo "  OpenClash apk 已生成:"
    ls -lh $APK_GLOB

    echo ""
echo "=== Step 9: Output summary (size validation + sha256) ==="
    STRICT=1 bash "${SCRIPT_DIR}/check-image-size.sh" "$TARGET_DIR"
    echo ""
    echo "  OpenClash apk:"
    for f in $APK_GLOB; do
        printf "    %s  %s\n" "$(sha256sum "$f" | cut -d' ' -f1)" "$(basename "$f")"
    done
    echo ""
else
    echo ""
    echo "============================================"
    echo "  准备完成!请执行:"
    echo "    make menuconfig   # fine-tune packages (target pre-seeded)"
    echo "    make -j\$(nproc) V=s | tee build.log"
    echo "============================================"
fi
