# 健康检查报告 — openwrt-ax3000t-an8855

> **日期**: 2026-09-18
> **范围**: 仓库整体（构建/脚本/CI/文档/补丁基线），依据 `rebuild-task.md` 的三阶段健康检查流程
> **基线**: 上游 OpenWrt `main` @ `928cd26bd938b8ac46b79e14f5f9f4b1d772abe8`（见 `patches/VERIFIED_COMMIT`）
> **方法**: 先验证后修改；只修能以证据确认的问题；不重构风格、不升级依赖、不改固件业务行为
> **状态**: active

---

## 1. 摘要

本次健康检查确认：仓库的核心构建链路是健康的——AN8855 补丁集在锁定的 OpenWrt 基线上可精确应用，
固件可完整编译，initramfs FIT 体积在 26 MiB 门限内，OpenClash 可作为独立 apk 产出。

修复的都是"确凿且可复现"的问题，其中最关键的一条是**本地与 CI 的配置契约出现两份拷贝并已漂移**：
两份 `.config` 种子相差一行 `CONFIG_PACKAGE_luci-app-openclash=m`，导致 CI 能产出 OpenClash apk，
而本地 `bash setup.sh build` 必然在最后一步失败。该问题（以及同一类"同一事实多份实现"的其它拷贝）
已通过把构建步骤收敛到 `scripts/build/` 解决。

无任何风格、洁癖或"现代化"改动；未升级 OpenWrt 基线，未改动固件包集合的意图与业务行为
（唯一的包集合变化是本地构建与 CI/发布产物对齐，见 §4.1）。

## 2. 项目识别（第一阶段）

| 项目 | 事实 |
| --- | --- |
| 类型 | OpenWrt 固件构建/发布仓库（无应用代码） |
| 技术栈 | Bash 编排 + OpenWrt mainline（内核 6.18）+ GitHub Actions；目标 MediaTek MT7981 / Airoha AN8855 |
| 包管理器 / 锁文件 | 无（无 `package.json`/lockfile/manifest）；唯一的"锁"是 `patches/VERIFIED_COMMIT`（上游 commit） |
| 构建入口 | `bash setup.sh`（准备）、`bash setup.sh build`（准备+编译）、`bash setup.sh --branch openwrt-24.10 build` |
| 校验入口 | `scripts/repository-check`、`scripts/check-image-size.sh`、`scripts/pull-request-check` |
| 测试 | 无自动化测试套件（无 test/spec 文件）；验证依赖构建 + 体积门 + 真机刷写 |
| 静态检查 | 未配置任何 lint / typecheck / formatter（仅有 `.editorconfig`、`.gitattributes`） |
| CI/CD | `.github/workflows/`：ci（矩阵构建）、release（semantic-release）、pull-request（PR 合约）、repository-baseline |
| 补丁基线 | `patches/0001-add-an8855-target.patch` + `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` |

## 3. 当前状态验证（第二阶段）

| 项 | 命令 | 结果 |
| --- | --- | --- |
| 依赖 | 无包管理器可跑；改用外部工作树的 `./scripts/feeds update -a` + `install -a` | 成功：feeds 索引全部创建（含 `openclash.index`）；`dl/` 预热 2.0 GB 后构建无下载失败 |
| 构建 | `bash setup.sh build`（仓库外独立工作树，见 §4.2） | 见 §4.2 结果 |
| 测试 | `git ls-files \| grep -icE '(^\|/)(test\|tests\|spec)(/\|\.\|$)'` | `0`：仓库无测试套件（事实，非缺陷；不新建测试体系） |
| 静态检查 | `bash -n setup.sh scripts/build/*.sh scripts/check-image-size.sh`；全部 workflow YAML 解析；`scripts/repository-check` | 全部通过；`repository-check` 退出码 0 |
| 补丁/基线一致性 | `patches/VERIFIED_COMMIT` 内容 vs 构建树 `git rev-parse HEAD`；补丁 dry-run/apply 输出 | 一致（均为 `928cd26…`）；dry-run 与 apply 均无 offset/FAILED，三个被改文件校验通过 |

说明：`actionlint`/`shellcheck`/`markdownlint-cli2`/`yamllint` 在本机与仓库中都不存在，仓库也未配置它们，
因此**不把它们当作门禁**（历史上 `docs/development/guide.md` 声称这些门禁存在，已改正）。

## 4. 结构与脚本重组

### 4.1 为什么重组（以及唯一的包集合变化）

同一份"构建知识"在仓库里有 2~3 份实现，且已经发生真实漂移：

| 事实 | 修复前的位置 | 后果 |
| --- | --- | --- |
| `.config` 种子 | `setup.sh` 内联 + `scripts/generate-config-seed.sh` | 两份只差一行（本地那份缺 `CONFIG_PACKAGE_luci-app-openclash=m`）→ 本地 build 必然失败（A-1） |

修复前两份种子的原始差异（`git show 1f1d4b1:setup.sh` 的内联种子 vs
`scripts/build/generate-config-seed.sh` 生成的种子，已去掉注释与空行后排序比较）：

```diff
40a41
> CONFIG_PACKAGE_luci-app-openclash=m
```
| 自有符号清理表（~230 行） | `setup.sh` + `.github/workflows/ci.yml` | 双份维护，易再次漂移 |
| 首启 uci-defaults | `setup.sh` 内联 + `scripts/inject-firstboot-defaults.sh` | 逐字重复 |
| 补丁应用流程 | `setup.sh` + `ci.yml` | 双份 dry-run/apply/校验逻辑 |
| apk 路径查找 | `setup.sh`（硬编码架构目录）+ `ci.yml`（`find`） | 两套实现 |
| 路径推导 | `setup.sh` 用 `$(pwd)`，同文件其它路径用 `$(dirname $0)` | 从非仓库目录执行会把构建树建到当前目录（A-7） |

重组后：

```text
setup.sh                         # 只做参数解析 + 步骤编排
scripts/build/                   # 每个构建步骤一个脚本，本地与 CI 共用
  env.sh                         # 路径/常量/日志（唯一来源）
  prepare-source.sh              # 克隆 + VERIFIED_COMMIT 锁定（含锁定后 HEAD 校验）
  apply-an8855-patches.sh        # dry-run + 应用 + 三文件生效校验
  configure-feeds.sh             # OpenClash feed + feeds update/install
  configure-config.sh            # defconfig + 清理自有符号 + 追加种子 + defconfig
  generate-config-seed.sh        # .config 契约唯一来源（种子 + 自有符号清单）
  inject-firstboot-defaults.sh   # 首启定制
  compile-firmware.sh            # make（启用 pipefail）
  compile-openclash-apk.sh       # 单独编译 apk + 记录路径
  report-artifacts.sh            # 体积门（gate）/ 产物汇总（summary）
scripts/check-image-size.sh      # 路径不变（README/CI/文档引用）
scripts/repository-check         # 路径不变（AGENTS.md/project.yaml/CI 引用）
scripts/pull-request-check       # 路径不变
scripts/update-verified-commit.sh  # 只替换 sha 行，保留验证说明与产物记录
```

`.github/workflows/ci.yml` 删除了约 180 行内联重复逻辑，改为调用同一套脚本；所有 `run:` 块不再内联
GitHub context 插值（改用 `env:`），PR 事件下"不锁定 commit、仍应用补丁"的漂移检测语义保持不变。

**固件镜像内容没有变化（本轮实测）**：`CONFIG_PACKAGE_luci-app-openclash=m` 只把 OpenClash 及其运行依赖
（`dnsmasq-full`、`ruby`、`libyaml`、`unzip` 等）作为**模块包**编译出来，不进镜像。证据：

- 新构建与归档基线的 manifest 逐包比较为**空差异**（两边各 284 个包，完全相同）；
- 镜像里仍然是 `dnsmasq`（不是 `dnsmasq-full`），`kmod-nft-tproxy` 在基线与新构建中都存在
  （openclash feed 的 `Package/…/config` 默认值在基线构建时即已生效，与本次修复无关）；
- `initramfs-kernel.bin` 体积仅差 324 字节（21,720,248 vs 21,719,924）。

真正新增的只有镜像外的产物：`luci-app-openclash-0.47.156.apk`（7.8 MB，sha256
`7d862af45a9c540d96c39d578421acd938da543565ec4789d09d63821c2b5401`）。因此"不改动固件包集合与业务行为"这一约束成立，本地构建与 CI/发布产物现在也一致。

### 4.2 全新完整构建（仓库外独立工作树）

- 快照：提交 `11c3b88`（重组提交）的工作树内容；此后仅改了注释/文档，不影响任何构建输出
- 工作树：`/home/hugh/Projects/ax3000t-rebuild`（仓库外；`dl/` 用硬链接预热，源码树为干净的
  `928cd26` 检出，`build_dir`/`staging_dir`/`bin` 均为空）
- 命令：`bash setup.sh build`（本轮重组后的脚本）
- 对照基线：`/home/hugh/Projects/ax3000t-baseline-20260917`（重组前本地构建产物 + sha256）
- 执行记录（第一次尝试失败，非仓库缺陷）：首轮把 `bash setup.sh build` 的 stdout 直接接到后台任务，
  `make V=s` 的详细输出在 18 分钟内就超过运行器 20 MB 的任务输出上限而被终止（日志里没有任何编译错误，
  已确认只有已知的 `(ignored)` 子 make 噪音）。修法是让包装脚本把 `make` 的详细输出重定向进
  `run-full-build.log`，只在任务 stdout 打印阶段行与退出码；随后在同一工作树断点续跑（make 增量），
  这也是最终的验收构建。教训：`V=s` 的日志必须落盘，不能进后台任务 stdout。

> 本轮构建的退出码、产物体积与 sha256 在构建结束后填入（见 §7 附：产物测量）。

## 5. 问题分类（第三/四阶段）

### A 类：已确认的问题（全部已修）

| # | 现象 | 证据 | 根因 | 最小修复 | 复跑验证 |
| --- | --- | --- | --- | --- | --- |
| A-1 | 本地 `bash setup.sh build` 必然在步骤 8 失败：OpenClash apk 不存在 | `bin/packages/aarch64_cortex-a53/openclash/` 为空；`.config` 中该符号为 `# CONFIG_PACKAGE_luci-app-openclash is not set`（当时的 `.config` 已被本轮 run 重新生成，行号不再可复现，符号状态可由 `patches/VERIFIED_COMMIT` 与重构前的 `setup.sh` 内联种子核对）；`build.log` 止于该步骤（compile 耗时 0.08s）；无步骤 9 输出 | `setup.sh` 内联种子与 `scripts/generate-config-seed.sh` 两份拷贝相差一行 `CONFIG_PACKAGE_luci-app-openclash=m` | 种子收敛到单一来源（`scripts/build/generate-config-seed.sh`），本地与 CI 共用；apk 路径查找也收敛到一处 | 见 §4.2：`bash setup.sh build` 走到步骤 8/9 并产出 apk |
| A-2 | 文档声称存在并不存在的门禁与文件，会误导后续 agent | `docs/development/guide.md` 引用 `README.zh.md`（×3）、`DEVELOPMENT.md`、`python3 .config/opencode/gates/...`、`actionlint`、`shellcheck`、`markdownlint-cli2`、`yaml-lint`、`.agents/config.yaml`、`.opencode/skill-config.yaml`；仓库与机器上均不存在 | 文档抄自另一个项目的模板，从未与本仓库核对 | 改为本仓库真实门禁表（bash -n / repository-check / pull-request-check / 体积门 / 完整构建），删除无效引用 | `grep -rn` 复查：`docs/`、`README.md`、`.github/` 中无残留（`.agent/plans/active/*` 作为历史保留，其正文仍含旧名，属有意保留的历史记录） |
| A-3 | 文档描述 CI 触发频率错误 | guide 写 "daily cron (02:00 UTC)"，`ci.yml` 实为 `0 2 1 * *`（每月 1 日） | 文档与 workflow 漂移 | 文档改为"每月 1 日"，并补上另外两个 workflow 的真实触发条件 | 文档与 `ci.yml` 逐项对照 |
| A-4 | 被跟踪的 agent 交接状态整体失真 | `.agent/project-state.md`/`project-status.md`/`state.yaml`：声称 `README.zh.md`/`DEVELOPMENT.md` 存在、CI/CD 未配置、`AGENT-MANAGED` block 存在、`reviewed_commit 1c5eff5`、`expires_at 2026-08-28` 已过期；引用的 `/home/hugh/agent-config/AGENTS.md` 不存在；仓库内外无任何消费者 | 上一任维护者的 agent 状态长期未同步 | 三份状态改写为可核验的事实，并明确"`docs/` 才是真相来源"；`plans/active/*` 保留为历史（不删除） | 三份文件内容与本报告/仓库当前状态逐条一致；`state.yaml` 通过 YAML 解析 |
| A-5 | 编译失败会被掩盖 | `setup.sh` 为 `set -e` + `make … \| tee build.log`（无 `pipefail`）：`bash -c 'set -e; false \| tee /dev/null; echo continued'` 会继续执行 | 缺少 `pipefail`，管道的退出码取自 `tee` | `compile-firmware.sh` 用 `set -euo pipefail`，make 失败即以 make 的退出码失败 | 对照组实验：旧写法继续执行、新写法立即失败（exit=1） |
| A-6 | `README` 产物清单与实际产物不符 | README 写 `*-initramfs.itb`；实际产物是 `*-initramfs-kernel.bin`（体积门脚本也只认 `kernel.bin/.itb`） | 文档按旧命名书写 | README 改为实际文件名 | 与 `bin/targets/mediatek/filogic/` 实际产物对照 |
| A-7 | 构建树路径依赖调用者当前目录 | `setup.sh` 用 `OPENWRT_DIR="$(pwd)/openwrt-ax3000t"`，而同文件 `REPO_PATCH_DIR`/`SCRIPT_DIR` 用 `$(dirname $0)` | 路径推导不一致 | 路径统一由 `scripts/build/env.sh` 相对仓库根推导（仍可用环境变量覆盖，CI 语义不变） | 从外部工作树、任意 CWD 执行 `bash <repo>/setup.sh` 均指向同一构建树（本轮外部构建即为该路径） |
| A-8 | 同一事实存在多份实现（重复代码），并已造成 A-1 | 种子、符号清理表、首启 defaults、补丁流程、apk 查找各 2 份 | 本地与 CI 各写一份，无共享模块 | 构建步骤全部收敛到 `scripts/build/`，CI 调用同一脚本 | 见 §4.1 的对照表；`ci.yml` 从 352 行降到 187 行且无内联重复逻辑 |
| A-9 | `CONFIG_VERSION_REPO`（USTC 镜像）是无效配置，固件仍指向 `downloads.openwrt.org` | 旧构建产物 rootfs 的 `/etc/apk/repositories.d/distfeeds.list` 全为 `https://downloads.openwrt.org/snapshots/...`；`make defconfig` 后 `.config` 为 `# CONFIG_VERSIONOPT is not set` | `VERSIONOPT`/`VERSION_REPO` 位于 `package/base-files/image-config.in`，受 `CONFIG_IMAGEOPT` 门控（`menuconfig VERSIONOPT … if IMAGEOPT`），普通源码 `.config` 无法打开 | **未改行为**：改正文档与种子注释，说明实际行为；是否改配置留作待决策项 U1（会改变固件内 apk 源地址） | 文档/注释不再声称镜像生效；旧产物证据留档 |

### B 类：已记录、未修（有证据但无故障）

| # | 风险 | 证据/说明 | 不修理由 |
| --- | --- | --- | --- |
| B-1 | `.gitignore` 的 `*.bin` 会连带忽略任何合法的 `.bin` 入库需求 | `.gitignore` 含 `*.bin`/`*.img` | 当前无用例；删除规则会削弱"不提交固件产物"的保护 |
| B-2 | 本地残留分支 `fix/pr-workflow`、`fix/publish-release-assets` 未合并且仅存在于本地 | `git branch --merged master` 未包含二者；同主题提交已通过 PR #6/#7 进入 `master`（未逐一比对内容是否完全一致，故只记录不删除） | 属"历史价值对象"，只记录不删除（范围约束） |
| B-3 | CI 配置了 ccache 但没有持久化缓存，180 分钟 job 超时对全新构建偏紧 | `ci.yml` 仅 `ccache --max-size` + `PATH`，无 `actions/cache`；README 称首次构建需数小时 | 无失败证据；新增缓存属新增基础设施，超出本次范围 |
| B-4 | `scripts/update-verified-commit.sh` 以 `git push origin HEAD:master` 直推 | 脚本第 61 行起 | CI 权限模型如此设计（已在 workflow 中限制为非 PR + 成功 + master）；无故障证据 |
| B-5 | CI 依赖仓库设置（Actions 读写权限）才能回推 VERIFIED_COMMIT | `permissions: contents: write` + 脚本 push | 属仓库设置而非代码问题，已在 `docs/development/guide.md` 的"Required Repository Settings"中说明 |
| B-6 | 仓库内的 OpenWrt 构建树（21 GB） | `openwrt-ax3000t/` 被忽略，仍在磁盘上 | 设计如此（本地构建树），删除与否不属本次范围 |
| B-8 | 本机与 CI 的宿主构建依赖不完全一致：本机缺 `swig`、`ccache`、`python3-setuptools`（CI 的 `Install dependencies` 装了 swig/ccache，未装 setuptools） | `command -v swig/ccache` 为空、`python3 -c "import setuptools"` 失败；本机 OpenWrt 源码树未使用 swig（所选包中无任何包引用它） | 已确认本轮所选包不需要 swig；ccache 仅影响速度；本轮构建未出现 setuptools 相关错误。属环境差异，记录而非修仓库 |
| B-7 | 固件自带 `dnsmasq`，而 OpenClash apk 声明依赖 `dnsmasq-full`；两者是互斥变体，README 里的 `apk add … luci-app-openclash-*.apk` 在真机上可能因冲突失败 | 新构建 `.config`：`CONFIG_PACKAGE_dnsmasq-full=m`（模块包，不进镜像）；固件 manifest：`dnsmasq - 2.93-r3`（镜像内）；openclash feed Makefile：`DEPENDS:=+dnsmasq-full …` | 无真机可验证（本环境不能刷机）；属上游 feed 的既定行为，非本次改动引入。真机安装失败时先 `apk del dnsmasq` 或改用 `--force-*`，或把 `dnsmasq-full` 提为镜像内 =y（会改变固件包集合，需你决策） |

### 无害构建噪音（不改）

完整构建日志中会出现形如 `make[4]: *** [GNUmakefile:108: abort-due-to-no-makefile] Error 1`
（host libtool）与 `make[5]: *** [Makefile:3163: uninstall] Error 1`（host elfutils）的输出。
它们紧随 `make[3]: […].prepared/…: Error 2 (ignored)` 这样的标记，即 **OpenWrt 构建系统显式忽略**
的清理/探测失败（对不存在文件 `rm -f`、对非空目录 `rmdir`），不影响产物。按 rebuild-task 的要求
把无害 warning 与真实错误区分开：本轮不把它们当作待修问题，也不在其中加入"确认过没问题"的补丁。

### 其他说明

- 本轮把本地工具状态（`.pi/`、`rebuild-task.md`）加入 `.gitignore`：它们不是仓库状态，
  此前会让 `git status` 一直显示未跟踪杂物；未触及任何项目代码。

### C 类：仅风格/洁癖，未处理

- 脚本命名风格不统一（`scripts/repository-check`、`scripts/pull-request-check` 无扩展名，其余为 `*.sh`）——路径是外部契约，不动。
- `docs/` 下的空占位目录（`adr/architecture/deployment/plans/proposals/runbooks` 仅有 `.keep`）——`repository-check` 要求这些 section 存在，保留。
- 中文注释密度、表格排版、`.editorconfig` 具体取值等。

## 6. 待决策与后续

| 编号 | 事项 | 需要你决定什么 |
| --- | --- | --- |
| U1 | USTC 镜像配置无效（A-9）。当前固件 feeds 指向 `downloads.openwrt.org` | 选项一：保持现状（已按现状改正文档/注释）；选项二：改构建配置让镜像真正生效（会改变固件内 apk 源地址，需要重编） |
| U2 | CI 无 ccache 持久化（B-3） | 是否加 `actions/cache`（新增 CI 基础设施） |
| U3 | 本地残留分支与 21 GB 构建树（B-2/B-6） | 是否清理 |
| U4 | 本轮所有改动都在本地分支 `fix/rebase-verified-commit`；未推送、未开 PR | 是否需要推送/开 PR（PR 合约要求正文引用 issue） |

## 7. 附：产物与复跑验证

### 7.0 如何复现本轮检查

```sh
# 1) 静态/仓库级检查（无需构建，秒级）
bash -n setup.sh scripts/* scripts/build/*
./scripts/repository-check
printf '## Summary\n\nx\n\n## Validation\n\nCloses #1\n' > /tmp/pr-body
./scripts/pull-request-check /tmp/pr-body

# 2) 仓库外独立工作树的「全新完整构建」（本次执行方式）
EXT=/home/hugh/Projects/ax3000t-rebuild
mkdir -p "$EXT"
rsync -a --exclude openwrt-ax3000t/ --exclude .git/ --exclude .pi/ \
      --exclude rebuild-task.md /path/to/repo/ "$EXT"/
git clone --local /path/to/repo/openwrt-ax3000t "$EXT/openwrt-ax3000t"   # 干净源码树,无构建产物
mkdir -p "$EXT/openwrt-ax3000t/dl" && cp -al /path/to/repo/openwrt-ax3000t/dl/. "$EXT/openwrt-ax3000t/dl/"
( cd "$EXT" && bash setup.sh build )     # 步骤 1..9，产物与结论见 §7.2

# 3) 收尾核对
git -C "$EXT/openwrt-ax3000t" rev-parse HEAD      # 应等于 patches/VERIFIED_COMMIT 内容
scripts/check-image-size.sh "$EXT/openwrt-ax3000t/bin/targets/mediatek/filogic"
```



### 7.1 对照基线（重组前本地构建，2026-09-17）

| 产物 | 体积 | sha256 |
| --- | --- | --- |
| `…-initramfs-kernel.bin` | 21,719,924 B（20.7 MiB，≤ 26 MiB） | `5e86cf983ead009b334eeaa226f3a24d587701f712ae16e6aa1a8189fc788d5c` |
| `…-initramfs-factory.ubi` | 23,461,888 B | `d14654c5b3c0211efe745a4d351fee8b338774dca5885bde9e88e9f02878000d` |
| `…-squashfs-sysupgrade.bin` | 23,316,776 B | `647a5de558582befbe858381d4fcc4076e3e2b9592b529c1b5c235f2799fd897` |

（归档目录 `/home/hugh/Projects/ax3000t-baseline-20260917`，含 `SHA256SUMS.txt`；该基线缺少 OpenClash apk，即 A-1。）

### 7.2 本轮全新构建结果

> 本轮独立工作树的完整构建（`bash setup.sh build` 退出码 0，耗时约 16 分钟，含断点续跑）；
> 数据来自 `run-full-build.log` 与实际产物。

| 项 | 结果 |
| --- | --- |
| `bash setup.sh build` 退出码 | 0（见 run-full-build.log 末行） |
| initramfs FIT 体积门（STRICT=1） | 通过：20.7 MiB ≤ 26 MiB |
| `…-initramfs-kernel.bin` | 21,720,248 B（20.7 MiB） | sha256 `8c50f15952142b876da0a441e919bf1d586434be7b659b645c7fe26e335d089e` |
| `…-initramfs-factory.ubi` | 23,461,888 B（22.4 MiB） | sha256 `afc3c66b402b163a1221cea169966d8cbcc20465ac46ef37d52e55a0dd79677f` |
| `…-squashfs-sysupgrade.bin` | 23,316,776 B（22.2 MiB） | sha256 `40ebf28bfa4463b3f462e7e7cfb166fec1bcb283e4cbc58f1cb2679c78f2910b` |
| `luci-app-openclash-0.47.156.apk` | 8,163,392 B（7.8 MiB） | sha256 `7d862af45a9c540d96c39d578421acd938da543565ec4789d09d63821c2b5401` |

### 7.3 复跑验证清单（本次实际执行）

```sh
bash -n setup.sh scripts/* scripts/build/*                 # 语法门，全部通过
./scripts/repository-check                                  # exit 0
scripts/pull-request-check <样例 PR body>                   # Pull Request contract passed
scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic   # 体积门
bash setup.sh build                                         # 仓库外独立工作树完整构建
python3 -c "import yaml; yaml.safe_load(...)"               # 4 个 workflow + 配置 YAML 解析
```

对照实验（A-5）：`set -e` 下 `false | tee` 会继续执行；`set -eo pipefail` 下立即失败。
