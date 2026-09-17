# Development Guide — OpenWrt AX3000T AN8855

> **Date**: 2026-08-21
> **Author**: hugh
> **Scope**: infrastructure
> **Purpose**: Complete build environment, customization, troubleshooting, and contribution guide
> **Status**: active

---

This is the build and development guide. Runtime configuration, device state, and the
historical build/troubleshooting archive stay in their canonical documents
([home-router.md](../operations/home-router.md), [router-state.md](../reference/router-state.md),
[build-experience.md](../reports/build-experience.md)) and are linked, never copied, so every
fact has exactly one source of truth. For user onboarding, see [README.md](../../README.md).

---

## Build Environment

### Host Requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| OS | Linux x86_64 (WSL2 supported) | Ubuntu 22.04+ / Debian 12+ |
| RAM | 8 GB | 16 GB+ |
| Disk | 80 GB free | 150 GB+ (for ccache/sstate) |
| Proxy | SOCKS5 for China mainland | `ALL_PROXY=socks5h://host:port` |

### Required Packages

```bash
# Debian/Ubuntu
sudo apt update && sudo apt install -y \
    build-essential clang flex bison g++ gawk gcc-multilib g++-multilib \
    gettext git libncurses-dev libssl-dev python3-setuptools \
    rsync swig unzip zlib1g-dev file wget ccache

# Arch Linux
sudo pacman -S --needed base-devel gcc git ncurses openssl python3 rsync swig unzip zlib ccache
```

---

## Build Process Deep Dive

### What `setup.sh` Does

`setup.sh` only parses arguments and orders steps. Every step lives in `scripts/build/` and is
shared with CI, so the local build and CI cannot drift apart.

| Step | Script | What it does |
| --- | --- | --- |
| 1 | `prepare-source.sh` | Clone OpenWrt (repo branch `master` → upstream `main`) and lock to `patches/VERIFIED_COMMIT` |
| 2 | `apply-an8855-patches.sh` | Copy the AN8855 DTS, dry-run + apply the patch set, verify each touched file |
| 3 | `configure-feeds.sh` | Add the OpenClash feed, then `feeds update -a` + `feeds install -a` |
| 4 | `configure-config.sh` | `make defconfig`, clear the project-owned symbols, append the seed, `make defconfig` |
| 5 | `inject-firstboot-defaults.sh` | Install `99-router-home-custom` uci-defaults (LAN IP + open WiFi) |
| 6 | `compile-firmware.sh` | `make -j$(nproc) V=s \| tee build.log` (pipefail: a compile error fails the step) |
| 7 | `report-artifacts.sh gate` | initramfs FIT size gate (`STRICT=1`, ≤ 26 MiB) |
| 8 | `compile-openclash-apk.sh` | Build OpenClash separately as an apk and record its path |
| 9 | `report-artifacts.sh summary` | Final size gate + apk sha256 + flash checklist |

The `.config` contract (seed + project-owned symbol list) comes from
`scripts/build/generate-config-seed.sh`; that file, not the CI workflow, is the registry of
packages this project selects.

### Key Patch Details

| File | Purpose |
|------|---------|
| `patches/0001-add-an8855-target.patch` | Adds `Device/xiaomi_mi-router-ax3000t-an8855` to `target/linux/mediatek/image/filogic.mk`; sets `CI_UBIPART="ubi"` in `platform.sh`; adds AN8855 LAN/WAN/MAC rules in `02_network` |
| `patches/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | Defines single UBI partition: `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }` (112MB @ 0x600000) |

### Curated Kernel Module Set

Pre-selected in `defconfig` to fit <26MB initramfs FIT limit:

| Category | Modules |
|----------|---------|
| Memory | `kmod-zram`, `zram-swap` |
| Firewall/NAT | `kmod-ipt-core`, `kmod-nft-*`, `kmod-nf-nathelper` |
| Tunnels | `kmod-wireguard`, `kmod-tun`, `kmod-veth`, `kmod-tcp-bbr` |
| QoS | `kmod-sched-cake`, `kmod-sched-fq-pie`, `tc-full` |
| Filesystem | `kmod-fs-ext4` |
| Diagnostics | `tcpdump`, `conntrack`, `ipset`, `ip-full`, `ip-bridge`, `iperf3`, `ethtool`, `mtr`, `nlbwmon` |

**Excluded** (to fit size budget): USB/storage kmods (btrfs, xfs, usb-core, etc.), exotic tunnels (l2tp, team, macsec), heavy filesystems.

### Image Size Validation

```bash
# Runs automatically in setup.sh build mode; manual:
scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic
```

Validates `*-initramfs-kernel.bin` (FIT) ≤ 26MB. **Excludes** `*-initramfs-factory.ubi` (UBI container, not loaded by U-Boot directly).

---

## Customization

### Changing Target Profile

```bash
cd openwrt-ax3000t
make menuconfig
# Target System: MediaTek Ralink ARM
# Subtarget: Filogic 820/830 (MT7981/MT7986)
# Target Profile: Xiaomi Mi Router AX3000T (AN8855)  ← MUST SELECT THIS
```

### Adding Kernel Modules

```bash
make menuconfig
# Kernel modules → [category] → select desired kmods
# Rebuild: make -j$(nproc) V=s
```

### Switching to OpenWrt 24.10 Stable

```bash
# 24.10 has official AN8855 target; no patches needed
bash setup.sh --branch openwrt-24.10 build
```

**Behavior difference**:
- `main`: clones main + locks `VERIFIED_COMMIT` + applies AN8855 patches
- `openwrt-24.10`: clones 24.10 branch, **skips commit lock & patches** (official target exists)

**SNAPSHOT vs stable (see issue #4)**:
- `main` builds always report `SNAPSHOT rXXXX` in LuCI / `/etc/openwrt_release`.
  That string comes from the upstream branch and is expected, not a flash failure.
- Snapshot is the default because the AN8855 switch support and related Filogic
  fixes are newest on `main`; the `openwrt-24.10` branch reports a stable version
  string but carries an older kernel and package set.
- Snapshot caveat: the package feed tracks a rolling snapshot, so `apk update`
  results drift over time; keep the firmware and the separately built OpenClash
  APK from the same build.

### Custom Feed / Package

```bash
# Add to feeds.conf before ./scripts/feeds update -a
src-git custom https://github.com/user/repo.git

# Or add to package/feeds/ manually, then:
./scripts/feeds install -a -p custom
```

---

## Troubleshooting

### Build Failures

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `fakeroot` hangs at `package/libs/toolchain/compile` | Stale `faked` daemon | `kill -9 $(pgrep -f 'faked\|fakeroot')` |
| Download <10 KB/s | No proxy configured | `export ALL_PROXY=socks5h://host:port` |
| `find: relative path in PATH` (WSL) | Windows PATH pollution | `PATH=$(echo "$PATH" \| tr ':' '\n' \| grep -v '^/mnt/' \| tr '\n' ':') make ...` |
| `GnuTLS recv error (-110)` | Direct GitHub connection failed | Use proxy; or `git config --global url."https://github.com/".insteadOf git://github.com/` |
| `Patch failed! No file to patch` (kernel prepare) | `PATCH_DIR` env var collision | `setup.sh` uses `REPO_PATCH_DIR` — ensure not overridden |
| `No more mirrors to give up` | Corrupted download in `dl/` | `rm dl/<bad-file>*` and retry |

### Runtime Issues (Post-Flash)

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| Sysupgrade → bootloop to recovery | Wrong target (dual-partition) | Must use `xiaomi_mi-router-ax3000t-an8855` single-UBI |
| OpenClash installed but no LuCI menu | Missing Lua runtime (LuCI 26) | `apk add luci-compat && /etc/init.d/uhttpd restart` |
| `fw_printenv` missing | `uboot-envtools` not configured | Not needed; stock U-Boot managed by upgrade scripts |
| Tailscale `logged out` | WAN down → no control plane | Restore WAN; `tailscaled` auto-reconnects via `procd respawn` |

### Image Size Issues

```bash
# Check current initramfs size
ls -lh bin/targets/mediatek/filogic/*initramfs-kernel.bin

# If >26MB: reduce kmods in menuconfig
# Common culprits: kmod-fs-*, kmod-usb-*, kmod-crypto-*
```

---

## Router Runtime Configuration

Canonical source: [home-router.md](../operations/home-router.md) — network topology, UCI
configuration, WiFi settings, and stability tuning of the running router.

## Device State Reference

Canonical source: [router-state.md](../reference/router-state.md) — hardware, flash
partitions, UBI volumes, and the single-UBI upgrade path.

## Historical Build Experience

Canonical source: [build-experience.md](../reports/build-experience.md) — WSL fixes, proxy
notes, performance baselines, and past image-size incidents.

## Contribution Workflow

### Before PR

```bash
# 1. Fast local checks (no build required)
bash -n setup.sh scripts/build/*.sh scripts/check-image-size.sh
scripts/repository-check

# 2. Full build (firmware + size gate + OpenClash apk)
bash setup.sh build

# 3. Update docs when a user-facing command, path, or behavior changes
#    (README.md, this guide, docs/reference/router-state.md, ...)
```

`scripts/pull-request-check <body-file>` validates the PR body contract (issue reference,
`## Summary`, `## Validation`).

### Commit Convention

Conventional Commits:
- `feat:` new feature
- `fix:` bug fix
- `docs:` documentation only
- `refactor:` code restructure
- `chore:` build/tooling
- `ci:` CI config

Example: `fix(patches): correct AN8855 MAC address extraction`

### PR Checklist

- [ ] Build passes (`bash setup.sh build`)
- [ ] Image size ≤26MB initramfs
- [ ] Docs updated (README/DEVELOPMENT if user-facing)
- [ ] No secrets in diff
- [ ] Conventional commit message

---

## Architecture Decisions

| Decision | Rationale | Reference |
|----------|-----------|-----------|
| Single UBI target on mainline | Stock U-Boot + AN8855 only boots single UBI | `docs/reference/router-state.md` §0 |
| OpenClash as APK not in firmware | initramfs >26MB with OpenClash → U-Boot load fail | `README.md` FAQ |
| Curated kmod set | 179 kmods → 27.9MB initramfs (fail); curated → ~25MB | `docs/reports/build-experience.md` §6.3 |
| USTC mirror intended, not applied | `CONFIG_VERSION_REPO` sits behind `CONFIG_IMAGEOPT` / `CONFIG_VERSIONOPT`, which a plain source `.config` cannot enable, so built images keep the upstream `downloads.openwrt.org` feeds | `docs/reports/health-check-2026-09.md` |
| `VERIFIED_COMMIT` lock | Prevent mainline drift breaking patches | `setup.sh` §75-83 |
| `REPO_PATCH_DIR` not `PATCH_DIR` | Avoids OpenWrt kernel.mk variable collision | `docs/reports/build-experience.md` §9 |

---

## Verification Gates

No lint, typecheck, or formatter toolchain is tracked in this repository (no Node, Python, or
shell-linter config). These are the gates that actually exist:

| Gate | Command | Scope |
| --- | --- | --- |
| Shell syntax | `bash -n setup.sh scripts/build/*.sh scripts/check-image-size.sh` | every build script |
| Repository baseline | `scripts/repository-check` | required files, docs sections, tracking hygiene |
| PR body contract | `scripts/pull-request-check <body-file>` | issue reference, Summary, Validation |
| Patch applicability | `bash setup.sh` (dry-run path) or a CI `master` build | AN8855 patch set vs upstream `main` |
| Image size | `scripts/check-image-size.sh <target-dir>` (`STRICT=1`) | initramfs FIT ≤ 26 MiB |
| Full build | `bash setup.sh build` | firmware + OpenClash apk |

`actionlint`, `shellcheck`, and `markdownlint-cli2` are not installed or configured here. Run
them manually if you have them; they are not part of the repository contract.

## CI/CD Pipeline

### Overview

This project uses GitHub Actions for continuous integration and semantic-release for automated versioning.

### Workflows

| Workflow | File | Triggers | Purpose |
|----------|------|----------|---------|
| **CI Build** | `.github/workflows/ci.yml` | Push/PR to `master`/`openwrt-24.10`, monthly cron (02:00 UTC on the 1st), manual dispatch | Build firmware + OpenClash apk, validate image size, upload artifacts |
| **Release** | `.github/workflows/release.yml` | Successful CI run on `master`, manual dispatch (dry-run) | semantic-release: analyze commits → version → tag → GitHub Release with artifacts |
| **Pull Request** | `.github/workflows/pull-request.yml` | Any pull request | PR body contract + repository baseline (reusable workflow) |
| **Repository Baseline** | `.github/workflows/repository-baseline.yml` | `workflow_call`, push to `master` | Runs `scripts/repository-check` |

### CI Build Details

**Matrix builds**:
- `master` branch (this repo; clones upstream `main`): Full pipeline with VERIFIED_COMMIT lock + AN8855 patches
- `openwrt-24.10` branch: Build without VERIFIED_COMMIT lock (official AN8855 target exists)

**Artifacts** (90-day retention):
- `*-initramfs-factory.ubi` — Flash via recovery/mtd
- `*-squashfs-sysupgrade.bin` — Sysupgrade from running OpenWrt
- `luci-app-openclash-*.apk` — Install via `apk add`
- `SHA256SUMS.txt` — Checksums for verification

**Image size gate**: `scripts/check-image-size.sh` runs with `STRICT=1` — build fails if initramfs > 26MB.

**VERIFIED_COMMIT auto-update**: On successful `master` builds (non-PR), CI extracts the OpenWrt commit SHA and updates `patches/VERIFIED_COMMIT`, committing and pushing back to `master`.

### Release Process

1. Push conventional commits to `master` (e.g., `feat: add new kmod`, `fix: patch drift`)
2. CI builds and validates → passes
3. `release.yml` triggers `semantic-release`
4. semantic-release:
   - Analyzes commits since last tag
   - Determines version bump (major/minor/patch)
   - Generates changelog (updates `CHANGELOG.md`)
   - Creates git tag `vX.Y.Z`
   - Creates GitHub Release with firmware + APK artifacts
   - Commits `CHANGELOG.md` update

**Commit conventions** (enforced by semantic-release):
- `feat:` → minor version
- `fix:` `perf:` `refactor:` `docs:` `build:` → patch version
- `chore:` `ci:` `style:` `test:` → no release
- `BREAKING CHANGE:` footer → major version

### Manual Release (if needed)

```bash
# Dry-run to preview
npx semantic-release --dry-run --no-ci

# Force release (bypasses commit analysis)
npx semantic-release --no-ci --branch master
```

### Local CI Testing

```bash
# Repository baseline (required files, docs sections, tracking hygiene)
scripts/repository-check

# PR body contract
scripts/pull-request-check <body-file>

# Test semantic-release config (needs the repo's git history)
npx semantic-release --dry-run --no-ci

# Run the image size check locally
scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic
```

Workflow syntax is only validated by GitHub when the workflow runs; `actionlint` is not
installed here.

### Required Repository Settings

1. **Actions permissions**: Settings → Actions → General → Allow all actions and reusable workflows
2. **Workflow permissions**: Settings → Actions → General → Workflow permissions → "Read and write permissions" (for VERIFIED_COMMIT push, semantic-release tag/release)
3. **Branch protection** (recommended): Protect `master` → Require status checks → `ci.yml` build job

---

## References

- [README.md](../../README.md) — User onboarding (English)
- [`scripts/build/`](../../scripts/build/) — one script per build step, shared with CI
- [home-router.md](../operations/home-router.md) — Router runtime config (Tailscale, network)
- [build-experience.md](../reports/build-experience.md) — Build troubleshooting archive
- [router-state.md](../reference/router-state.md) — Device partition/UBI/firmware state
- OpenWrt Build System: https://openwrt.org/docs/guide-developer/build-system/start
- AX3000T Forum: https://forum.openwrt.org/t/openwrt-support-for-router-home/180490