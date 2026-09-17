#!/bin/bash
# ============================================================
# 生成本仓库的 .config 契约（单一来源）
#
# 输出两个文件到 <输出目录>（默认当前目录 = OpenWrt 源码树根）:
#   .config.seed            追加到 .config 的种子（目标 / 包 / 精简工具集）
#   .config.owned-symbols   本仓库负责的符号清单，configure-config.sh 会先
#                           删除这些符号的旧行再追加种子，保证重复运行幂等
#
# 这两个文件是本仓库唯一一份配置契约: 本地 setup.sh 与 CI 都调用本脚本，
# 不再各存一份拷贝。历史问题: 两份拷贝曾相差一行
# CONFIG_PACKAGE_luci-app-openclash=m，导致 CI 能产出 OpenClash apk 而本地
# setup.sh build 在最后一步失败。
#
# 用法: generate-config-seed.sh [<输出目录>]
# ============================================================

set -euo pipefail

OUT_DIR="${1:-.}"
[ -d "$OUT_DIR" ] || { printf '输出目录不存在: %s\n' "$OUT_DIR" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 1) .config 种子
#    含 OpenClash =m: 只编译为独立 apk,不进固件(避免 initramfs 超过原厂
#    U-Boot 加载上限)。注意 luci-app-openclash 的 feed Makefile 用
#    "default y if PACKAGE_luci-app-openclash" 声明了 kmod-inet-diag /
#    kmod-nft-tproxy 与 dnsmasq-full nftset 变体，因此 CI 与本地固件都会
#    带上这些 OpenClash 运行所需的组件。
#
#    下面的 CONFIG_VERSIONOPT / CONFIG_VERSION_REPO(USTC 镜像)只写在这里做
#    记录: 两者受 CONFIG_IMAGEOPT 门控，普通源码构建的 .config 无法打开它们，
#    因此实际固件的 feeds 仍指向 downloads.openwrt.org。详见
#    docs/reports/health-check-2026-09.md(待决策项 U1)。
# ---------------------------------------------------------------------------
cat > "$OUT_DIR/.config.seed" <<'CONFIG_EOF'
CONFIG_TARGET_mediatek=y
CONFIG_TARGET_mediatek_filogic=y
CONFIG_TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855=y

CONFIG_VERSIONOPT=y
CONFIG_VERSION_REPO="https://mirrors.ustc.edu.cn/openwrt/snapshots"

CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_LUCI_LANG_zh_Hans=y

# CONFIG_PACKAGE_luci-mod-dsl is not set
# CONFIG_PACKAGE_luci-i18n-dsl-zh-cn is not set

CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
# Build OpenClash as a standalone APK, but do not include it in the firmware image.
CONFIG_PACKAGE_luci-app-openclash=m
CONFIG_PACKAGE_luci-app-nlbwmon=y

CONFIG_PACKAGE_tailscale=y
CONFIG_PACKAGE_luci-app-tailscale-community=y

CONFIG_PACKAGE_kmod-zram=y
CONFIG_PACKAGE_zram-swap=y

CONFIG_PACKAGE_iptables=y
CONFIG_PACKAGE_iptables-nft=y
CONFIG_PACKAGE_ip6tables-nft=y
CONFIG_PACKAGE_xtables-legacy=y
CONFIG_PACKAGE_xtables-nft=y

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

CONFIG_PACKAGE_kmod-wireguard=y
CONFIG_PACKAGE_kmod-veth=y
CONFIG_PACKAGE_kmod-tun=y
CONFIG_PACKAGE_kmod-tcp-bbr=y

CONFIG_PACKAGE_kmod-sched-core=y
CONFIG_PACKAGE_kmod-sched-cake=y
CONFIG_PACKAGE_kmod-sched-fq-pie=y

CONFIG_PACKAGE_kmod-fs-ext4=y

CONFIG_PACKAGE_conntrack=y
CONFIG_PACKAGE_ipset=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_ip-bridge=y
CONFIG_PACKAGE_tc-full=y

CONFIG_PACKAGE_tcpdump=y
CONFIG_PACKAGE_iperf3=y
CONFIG_PACKAGE_ethtool=y
CONFIG_PACKAGE_mtr-json=y
CONFIG_PACKAGE_nlbwmon=y

CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_wget-ssl=y
CONFIG_PACKAGE_nano=y
CONFIG_PACKAGE_openssl-util=y
CONFIG_PACKAGE_openssh-client=y
CONFIG_PACKAGE_coreutils=y
CONFIG_PACKAGE_htop=y
CONFIG_PACKAGE_iftop=y
CONFIG_EOF

# ---------------------------------------------------------------------------
# 2) 本仓库自有符号清单（sed 清理用，不含 CONFIG_ 前缀）
#    用途: 重复运行 setup.sh / CI 时，先删掉这些符号的旧行，避免
#    "key 多次定义" 警告与旧值残留，再追加种子。
# ---------------------------------------------------------------------------
cat > "$OUT_DIR/.config.owned-symbols" <<'SYMBOLS_EOF'
TARGET_mediatek
TARGET_mediatek_filogic
TARGET_mediatek_filogic_DEVICE_xiaomi_mi-router-ax3000t-an8855
VERSIONOPT
VERSION_REPO
PACKAGE_luci
PACKAGE_luci-ssl
LUCI_LANG_zh_Hans
PACKAGE_luci-compat
PACKAGE_luci-lua-runtime
PACKAGE_luci-mod-dsl
PACKAGE_luci-i18n-dsl-zh-cn
PACKAGE_luci-app-openclash
PACKAGE_luci-app-nlbwmon
PACKAGE_tailscale
PACKAGE_luci-app-tailscale-community
PACKAGE_iptables
PACKAGE_iptables-nft
PACKAGE_ip6tables-nft
PACKAGE_xtables-legacy
PACKAGE_xtables-nft
PACKAGE_iptables-mod-extra
PACKAGE_iptables-mod-conntrack-extra
PACKAGE_iptables-mod-ipopt
PACKAGE_iptables-mod-iprange
PACKAGE_iptables-mod-filter
PACKAGE_iptables-mod-hashlimit
PACKAGE_iptables-mod-nat-extra
PACKAGE_iptables-mod-trace
PACKAGE_iptables-mod-u32
PACKAGE_iptables-mod-ipset
PACKAGE_kmod-ipt-core
PACKAGE_kmod-ipt-extra
PACKAGE_kmod-ipt-nat
PACKAGE_kmod-ipt-nat-extra
PACKAGE_kmod-ipt-nat6
PACKAGE_kmod-ipt-conntrack
PACKAGE_kmod-ipt-conntrack-extra
PACKAGE_kmod-ipt-conntrack-label
PACKAGE_kmod-ipt-ipopt
PACKAGE_kmod-ipt-iprange
PACKAGE_kmod-ipt-filter
PACKAGE_kmod-ipt-hashlimit
PACKAGE_kmod-ipt-ipset
PACKAGE_kmod-ipt-offload
PACKAGE_kmod-ipt-raw
PACKAGE_kmod-ipt-raw6
PACKAGE_kmod-ipt-u32
PACKAGE_kmod-ipt-physdev
PACKAGE_kmod-ipt-rpfilter
PACKAGE_kmod-ipt-socket
PACKAGE_kmod-ipt-tee
PACKAGE_kmod-ipt-tproxy
PACKAGE_kmod-ipt-checksum
PACKAGE_kmod-ipt-led
PACKAGE_kmod-ipt-nflog
PACKAGE_kmod-ipt-nfqueue
PACKAGE_kmod-ipt-cluster
PACKAGE_kmod-ipt-ipsec
PACKAGE_kmod-ipt-debug
PACKAGE_kmod-nft-bridge
PACKAGE_kmod-nft-compat
PACKAGE_kmod-nft-connlimit
PACKAGE_kmod-nft-queue
PACKAGE_kmod-nft-socket
PACKAGE_kmod-nft-dup-inet
PACKAGE_kmod-nft-netdev
PACKAGE_kmod-nft-xfrm
PACKAGE_kmod-nft-arp
PACKAGE_kmod-nf-nat6
PACKAGE_kmod-nf-ipt
PACKAGE_kmod-nf-ipt6
PACKAGE_kmod-nf-ipvs
PACKAGE_kmod-nf-ipvs-ftp
PACKAGE_kmod-nf-ipvs-sip
PACKAGE_kmod-nf-nathelper
PACKAGE_kmod-nf-nathelper-amanda
PACKAGE_kmod-nf-nathelper-broadcast
PACKAGE_kmod-nf-nathelper-extra
PACKAGE_kmod-nf-nathelper-h323
PACKAGE_kmod-nf-nathelper-irc
PACKAGE_kmod-nf-nathelper-netbios
PACKAGE_kmod-nf-nathelper-pptp
PACKAGE_kmod-nf-nathelper-sane
PACKAGE_kmod-nf-nathelper-sip
PACKAGE_kmod-nf-nathelper-snmp
PACKAGE_kmod-nf-nathelper-tftp
PACKAGE_kmod-nf-conncount
PACKAGE_kmod-nf-socket
PACKAGE_kmod-nf-dup-inet
PACKAGE_kmod-nfnetlink-cthelper
PACKAGE_kmod-nfnetlink-cttimeout
PACKAGE_kmod-nfnetlink-log
PACKAGE_kmod-nfnetlink-queue
PACKAGE_kmod-gre
PACKAGE_kmod-gre6
PACKAGE_kmod-ipip
PACKAGE_kmod-sit
PACKAGE_kmod-ip6-tunnel
PACKAGE_kmod-ip-vti
PACKAGE_kmod-ip6-vti
PACKAGE_kmod-iptunnel4
PACKAGE_kmod-iptunnel6
PACKAGE_kmod-vxlan
PACKAGE_kmod-geneve
PACKAGE_kmod-fou
PACKAGE_kmod-fou6
PACKAGE_kmod-udptunnel4
PACKAGE_kmod-udptunnel6
PACKAGE_kmod-wireguard
PACKAGE_kmod-veth
PACKAGE_kmod-l2tp
PACKAGE_kmod-l2tp-eth
PACKAGE_kmod-l2tp-ip
PACKAGE_kmod-pppol2tp
PACKAGE_kmod-ppp-synctty
PACKAGE_kmod-bonding
PACKAGE_kmod-team
PACKAGE_kmod-team-mode-activebackup
PACKAGE_kmod-team-mode-broadcast
PACKAGE_kmod-team-mode-loadbalance
PACKAGE_kmod-team-mode-random
PACKAGE_kmod-team-mode-roundrobin
PACKAGE_kmod-macsec
PACKAGE_kmod-mpls
PACKAGE_kmod-vrf
PACKAGE_kmod-sctp
PACKAGE_kmod-tcp-bbr
PACKAGE_kmod-tcp-hybla
PACKAGE_kmod-tcp-scalable
PACKAGE_kmod-netem
PACKAGE_kmod-ipsec
PACKAGE_kmod-ipsec4
PACKAGE_kmod-ipsec6
PACKAGE_kmod-xfrm-interface
PACKAGE_kmod-sched-core
PACKAGE_kmod-sched-cake
PACKAGE_kmod-sched-fq-pie
PACKAGE_kmod-sched-skbprio
PACKAGE_kmod-sched-flower
PACKAGE_kmod-sched-bpf
PACKAGE_kmod-sched-pie
PACKAGE_kmod-sched-red
PACKAGE_kmod-sched-prio
PACKAGE_kmod-sched-drr
PACKAGE_kmod-sched-mqprio
PACKAGE_kmod-sched-mqprio-common
PACKAGE_kmod-sched-ctinfo
PACKAGE_kmod-sched-connmark
PACKAGE_kmod-sched-ipset
PACKAGE_kmod-sched-act-vlan
PACKAGE_kmod-sched-act-police
PACKAGE_kmod-sched-act-sample
PACKAGE_kmod-fs-ext4
PACKAGE_kmod-fs-f2fs
PACKAGE_kmod-fs-exfat
PACKAGE_kmod-fs-vfat
PACKAGE_kmod-fs-msdos
PACKAGE_kmod-fs-ntfs3
PACKAGE_kmod-fs-isofs
PACKAGE_kmod-fs-hfsplus
PACKAGE_kmod-fs-udf
PACKAGE_kmod-fs-configfs
PACKAGE_kmod-fs-exportfs
PACKAGE_kmod-fs-btrfs
PACKAGE_kmod-fs-xfs
PACKAGE_kmod-usb-storage
PACKAGE_kmod-usb-storage-uas
PACKAGE_kmod-usb-storage-extras
PACKAGE_kmod-usb-printer
PACKAGE_kmod-usb-serial
PACKAGE_kmod-usb-serial-ch341
PACKAGE_kmod-usb-serial-ftdi
PACKAGE_kmod-usb-serial-cp210x
PACKAGE_kmod-usb-serial-pl2303
PACKAGE_kmod-usb-serial-option
PACKAGE_kmod-usb-serial-wwan
PACKAGE_kmod-usb-net-cdc-eem
PACKAGE_kmod-usb-net-cdc-ether
PACKAGE_kmod-usb-net-cdc-mbim
PACKAGE_kmod-usb-net-cdc-ncm
PACKAGE_kmod-usb-net-cdc-subset
PACKAGE_kmod-usb-net-huawei-cdc-ncm
PACKAGE_kmod-usb-gadget
PACKAGE_kmod-usb-gadget-eth
PACKAGE_kmod-usb-gadget-serial
PACKAGE_kmod-usb-gadget-mass-storage
PACKAGE_kmod-nls-cp437
PACKAGE_kmod-nls-cp850
PACKAGE_kmod-nls-cp852
PACKAGE_kmod-nls-cp866
PACKAGE_kmod-nls-cp932
PACKAGE_kmod-nls-cp936
PACKAGE_kmod-nls-cp950
PACKAGE_kmod-nls-iso8859-1
PACKAGE_kmod-nls-iso8859-15
PACKAGE_kmod-nls-utf8
PACKAGE_kmod-nls-ucs2-utils
PACKAGE_kmod-softdog
PACKAGE_kmod-mtdoops
PACKAGE_kmod-fixed-phy
PACKAGE_kmod-phylink
PACKAGE_kmod-of-mdio
PACKAGE_kmod-input-evdev
PACKAGE_kmod-input-gpio-keys
PACKAGE_kmod-input-gpio-keys-polled
PACKAGE_kmod-input-uinput
PACKAGE_kmod-leds-pwm
PACKAGE_kmod-leds-uleds
PACKAGE_kmod-zram
PACKAGE_zram-swap
PACKAGE_conntrack
PACKAGE_conntrackd
PACKAGE_ipset
PACKAGE_ip-full
PACKAGE_tc-full
PACKAGE_ip-bridge
PACKAGE_tcpdump
PACKAGE_iperf3
PACKAGE_ethtool
PACKAGE_mtr-json
PACKAGE_nlbwmon
PACKAGE_curl
PACKAGE_wget-ssl
PACKAGE_nano
PACKAGE_openssl-util
PACKAGE_openssh-client
PACKAGE_coreutils
PACKAGE_htop
PACKAGE_iftop
SYMBOLS_EOF

printf '  已生成 %s/.config.seed 与 %s/.config.owned-symbols (%s 个自有符号)\n' \
    "$OUT_DIR" "$OUT_DIR" "$(grep -c . "$OUT_DIR/.config.owned-symbols")"
