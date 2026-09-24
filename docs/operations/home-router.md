# Xiaomi AX3000T (AN8855) OpenWrt / Tailscale 配置说明

> 本文是可公开的操作说明。真实家庭/办公室网络地址、Tailscale 节点标识、Wi‑Fi SSID、PPPoE 凭证和设备名称不属于公开仓库内容。

## 项目目标

记录 Xiaomi Mi Router AX3000T（AN8855 交换芯片版本）在 OpenWrt 下的通用配置方法，包括：

- PPPoE 上网；
- 同一 WAN 口访问光猫管理网；
- Tailscale 子网路由；
- firewall4 / nftables 转发；
- 双频 Wi‑Fi 基础配置。

运行时资产与真实网络拓扑应保存在私有控制面或密码管理器中，不在本公开仓库固化。

## 设备与环境

- 型号：Xiaomi Mi Router AX3000T（AN8855）
- 架构：`aarch64_cortex-a53`
- 系统：OpenWrt SNAPSHOT / 对应项目构建版本
- 登录账户：`root`

以下示例统一使用占位符：

- `<LAN_IP>`：路由器 LAN 地址
- `<LAN_CIDR>`：家庭局域网网段
- `<MODEM_IP>`：光猫管理地址
- `<MODEM_SIDE_IP>`：路由器访问光猫使用的静态地址
- `<TAILSCALE_IP>`：本节点 Tailscale 地址
- `<WIFI_SSID>`：无线网络名称

## 单臂 PPPoE + 光猫管理

WAN 接口负责 PPPoE，上面可再建立一个静态 `Modem` 接口访问光猫管理网。不要把 PPPoE 用户名或密码写入仓库。

```sh
uci set network.Modem.device='wan'
uci set network.Modem.proto='static'
uci set network.Modem.ipaddr='<MODEM_SIDE_IP>'
uci set network.Modem.netmask='255.255.255.0'
uci commit network

uci add firewall zone
uci set firewall.@zone[-1].name='modem'
uci set firewall.@zone[-1].network='Modem'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci set firewall.@zone[-1].masq='1'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='modem'
uci commit firewall
```

DSA 设备上，静态管理接口应绑定实际 WAN 从端口，而不是未经验证地绑定 CPU master 设备。是否配置 gateway 应按现场路由表验证，避免抢占 PPPoE 默认路由。

## Tailscale 子网路由

不要把真实 Tailscale IP、节点名、auth key 或 tailnet 成员信息写入公开文档。

```sh
tailscale up \
  --accept-dns=false \
  --advertise-routes=<LAN_CIDR> \
  --snat-subnet-routes=false

uci set network.tailscale='interface'
uci set network.tailscale.ifname='tailscale0'
uci set network.tailscale.proto='none'
uci commit network

uci add firewall zone
uci set firewall.@zone[-1].name='tailscale'
uci set firewall.@zone[-1].network='tailscale'
uci set firewall.@zone[-1].input='ACCEPT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='ACCEPT'
uci commit firewall

uci add firewall forwarding
uci set firewall.@forwarding[-1].src='tailscale'
uci set firewall.@forwarding[-1].dest='lan'
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='lan'
uci set firewall.@forwarding[-1].dest='tailscale'
uci commit firewall
```

远端客户端需要接受子网路由，并且对应路由需要在 Tailscale 控制面审批。是否启用 Tailscale SSH、MagicDNS、SNAT 等能力应按实际安全边界决定。

## Wi‑Fi 基础配置

公开仓库只保留通用参数，不记录真实 SSID 或无线密码。

```sh
uci set wireless.radio0.country=CN
uci set wireless.radio1.country=CN
uci set wireless.default_radio0.ssid='<WIFI_SSID>'
uci set wireless.default_radio1.ssid='<WIFI_SSID>'
uci set wireless.default_radio0.encryption='sae-mixed'
uci set wireless.default_radio1.encryption='sae-mixed'
uci set wireless.default_radio0.key='<WIFI_PASSWORD>'
uci set wireless.default_radio1.key='<WIFI_PASSWORD>'
uci commit wireless
wifi reload
```

`<WIFI_PASSWORD>` 只能在设备本地或受控密钥存储中设置，不得提交到 Git。

## 防火墙原则

- WAN 入站默认拒绝；
- 只开放明确需要的 zone / forwarding；
- Tailscale 与 LAN 是否双向互访应按使用需求配置；
- 不因排障临时关闭防火墙后把该状态固化为默认；
- 对外文档只描述规则，不保存真实资产清单。

## 验证

在目标设备上验证，而不是把运行时输出完整提交到公开仓库：

```sh
ubus call system board
ip route
uci show network
uci show firewall
tailscale status
```

提交日志前先删除或替换：公网/内网地址、Tailscale 地址与节点名、MAC、PPPoE 账户、SSID、密码、认证链接和 auth key。

## 信息边界

公开仓库可以保存：硬件型号、OpenWrt 构建方法、通用配置模式、故障机理和无身份属性的测试结论。

公开仓库不保存：真实家庭/办公室拓扑、机器名、用户路径、SSID、远端节点、账户标识、凭证、认证 URL 或可定位个人环境的运行时快照。
