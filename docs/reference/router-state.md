# AX3000T AN8855 固件状态与升级参考

> 本文只保留可公开的硬件、固件布局和升级结论。真实家庭/办公室网络拓扑、Tailscale 节点、SSID、主机名、用户路径和运行时地址不记录在公开仓库。

## 1. 设备概要

| 项目 | 值 |
|---|---|
| 型号 | Xiaomi Mi Router AX3000T |
| 硬件版本 | AN8855 外挂交换芯片版本 |
| SoC | MediaTek MT7981 (Filogic 820), aarch64 Cortex-A53 |
| 内存 | 256 MB |
| 闪存 | 128 MB SPI-NAND |
| board_name | `xiaomi,mi-router-ax3000t-an8855` |
| U-Boot | 原厂 U-Boot |

## 2. 已验证的核心结论

主线 OpenWrt 的普通 AX3000T stock 目标采用双分区布局，而本项目验证可工作的 AN8855 方案采用单 UBI 布局。两者不能在未确认分区和 bootloader 行为的情况下直接互换。

项目曾验证：

- AN8855 单 UBI 目标可在原厂 U-Boot 下持久启动；
- 对应 DTS、设备定义、升级脚本和网络板级配置已通过项目补丁固化；
- 重新克隆上游 OpenWrt 后，应由项目脚本重新应用补丁，而不是依赖未提交的上游工作树修改；
- LuCI 26 不再以旧 Lua 模式运行，使用仍依赖 Lua 的应用时需要按上游兼容机制处理。

## 3. 单 UBI 布局参考

测试方案使用单 UBI 系统分区，内部包含：

| 卷 | 作用 |
|---|---|
| `kernel` | 内核镜像 |
| `fit` | FIT 内核 |
| `rootfs` | squashfs 只读根文件系统 |
| `rootfs_data` | 可写 overlay |

具体偏移、大小和生成方式以仓库中的 DTS、`filogic.mk` 补丁和构建脚本为准；这些项目文件是权威来源，本文不作为第二套配置源。

## 4. 固化文件

- `patches/main/`、`patches/24.10/`：各通道的设备定义、升级路径与网络板级规则补丁；
- `patches/common/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts`：AN8855 单 UBI DTS；
- `scripts/build-firmware`：仓库原生构建入口（解析上游、应用补丁、编译、校验、归档）；
- `patches/VERIFIED_COMMIT`：`main` 通道已验证的上游静态基线。

## 5. 升级原则

1. 在刷写前确认当前 board、分区布局和 bootloader；
2. 不把 stock 双分区固件当作 AN8855 单 UBI 固件直接 `sysupgrade`；
3. 需要跨布局迁移时，使用经过项目验证的 initramfs 过渡流程；
4. `sysupgrade -n` 表示不保留旧配置，使用前必须确认目标镜像和恢复路径；
5. 保留原厂恢复模式作为救援路径，不以强刷绕过校验作为常规方案。

设备厂商恢复页可能使用其默认管理地址；该地址属于设备通用信息，不代表本仓库维护者的当前家庭网络配置。

## 6. 构建与刷机验证

公开验证记录可以包含：

- 目标设备型号和 board name；
- 内核 / OpenWrt 基线；
- 镜像类型；
- 分区布局；
- 启动是否成功；
- LuCI、驱动、网络接口等功能性结果。

提交日志前必须删除或替换：

- PPPoE 用户名和密码；
- Wi‑Fi SSID 和密码；
- MAC 地址；
- 家庭或办公室实际地址规划；
- Tailscale IP、节点名、tailnet 成员和认证链接；
- SSH 主机清单；
- 本机用户名与绝对路径；
- 任何 token、key、cookie 或会话数据。

## 7. 运行时状态的归属

运行时网络状态不属于这个公开固件仓库。需要维护真实机器状态时，应写入受控的私有资产/控制面仓库，并由其自身的 secret scan、访问控制和生命周期规则保护。

本仓库只负责可复现的构建输入、补丁、通用操作说明和不含个人环境标识的技术结论。
