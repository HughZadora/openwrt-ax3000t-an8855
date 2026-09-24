# Development Guide — OpenWrt AX3000T AN8855

Development-facing guide for building, customizing, and troubleshooting this
firmware repository.

Authoritative owners for the facts this guide does not own:

- onboarding and flashing: [README.md](../../README.md)
- runtime configuration patterns: [home-router.md](../operations/home-router.md)
- device/firmware state and upgrade rules: [router-state.md](../reference/router-state.md)
- downstream patch ownership: [patches/README.md](../../patches/README.md)
- build/release entrypoints: [scripts/README.md](../../scripts/README.md)

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
    rsync swig unzip zlib1g-dev file wget ccache ruby

# Arch Linux
sudo pacman -S --needed base-devel gcc git ncurses openssl python3 rsync swig unzip zlib ccache ruby ruby-erb
```

The `openwrt-24.10` channel also builds a **host Ruby** (3.3.x) whose
`encdb.h` step requires the `erb` standard library. Debian/Ubuntu's `ruby`
package includes it; Arch Linux splits it into `ruby-erb`. The host Ruby
build uses whichever `ruby` is first in `PATH`, so a host Ruby that ships
without `erb` fails late in the build with `cannot load such file -- erb`.

### Build Performance

| Strategy | First build | Rebuild (ccache) |
|----------|-------------|------------------|
| `-j$(nproc)` | 2–6 hours | 30 min |
| ccache hit rate | ~13% | 60%+ |
| `ALL_PROXY` | 1.2 KB/s → 34 MB/s | n/a |

## Build Process Deep Dive

### What `scripts/build-firmware` Does

Single repository-native build entrypoint (`--channel main` or
`--channel openwrt-24.10`):

```bash
# Resolve the upstream channel to an exact SHA (main defaults to the
# static recovery lock in patches/VERIFIED_COMMIT; --upstream-sha
# overrides explicitly), clone, copy the shared DTS, dry-run then apply
# patches/<channel>/, verify the target entries, update/install feeds,
# seed the config, inject first-boot defaults...
./scripts/build-firmware --channel main --prepare-only

# ...then compile, validate images + size gate, collect channel-prefixed
# assets and write build-manifest.json.
./scripts/build-firmware --channel main
```

Upstream source/build trees live under `build/` (ignored state).

```bash
# Stage 1 (conceptual): resolve upstream SHA, prepare source/feeds/config
# Stage 2: compile firmware + OpenClash package
# Stage 3: validate images, enforce the 26 MiB initramfs gate
# Stage 4: record build-manifest.json (repo SHA, upstream SHA, artifacts)
```

### Key Patch Details

| File | Purpose |
|------|---------|
| `patches/main/0001-add-an8855-target.patch` | Adds `Device/xiaomi_mi-router-ax3000t-an8855` to `filogic.mk`; sets `CI_UBIPART="ubi"` in `platform.sh`; adds AN8855 LAN/WAN/MAC rules in `02_network` (main channel) |
| `patches/24.10/0001-add-an8855-target.patch` | Same target adapted for 24.10 (its `platform.sh` single-UBI group differs) |
| `patches/common/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | Shared single UBI partition: `partition@600000 { label="ubi"; reg=<0x600000 0x7000000> }` (112MB @ 0x600000) |
| `patches/README.md` | Module ownership: why each delta is still required downstream |
| `patches/VERIFIED_COMMIT` | Static recovery lock for the main channel (intentional updates only; builds never mutate it) |

### Curated Kernel Module Set

Pre-selected in `defconfig` to fit the 26 MiB initramfs FIT limit:

| Category | Modules |
|----------|---------|
| Memory | `kmod-zram`, `zram-swap` |
| Firewall/NAT | `kmod-ipt-core`, `kmod-nft-*`, `kmod-nf-nathelper` |
| Tunnels | `kmod-wireguard`, `kmod-tun`, `kmod-veth`, `kmod-tcp-bbr` |
| QoS | `kmod-sched-cake`, `kmod-sched-fq-pie`, `tc-full` |
| Filesystem | `kmod-fs-ext4` |
| Diagnostics | `tcpdump`, `conntrack`, `ipset`, `ip-full`, `ip-bridge`, `iperf3`, `ethtool`, `mtr`, `nlbwmon` |

**Excluded** (to fit the size budget): USB/storage kmods (btrfs, xfs,
usb-core, etc.), exotic tunnels (l2tp, team, macsec), heavy filesystems.

### Image Size Validation

```bash
# Runs automatically in the build stage; manual:
STRICT=1 ./scripts/check-image-size.sh build/upstream-main/bin/targets/mediatek/filogic
```

Validates `*-initramfs-kernel.bin` (FIT) ≤ 26 MiB. **Excludes**
`*-initramfs-factory.ubi` (UBI container, not loaded by U-Boot directly).

## Customization

### Changing Target Profile

```bash
cd build/upstream-main
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

### Switching to the OpenWrt 24.10 channel

```bash
./scripts/build-firmware --channel openwrt-24.10
```

Upstream 24.10 provides the AN8855 switch driver but, like main, no
single-UBI board target -- the adapted `patches/24.10/` delta applies
there (see `patches/README.md`). The 24.10 channel reports a stable
version string where main reports a snapshot.

**Behavior difference**:
- `main`: clones `main`, pins the `patches/VERIFIED_COMMIT` static recovery lock, applies `patches/main/`
- `openwrt-24.10`: clones the `openwrt-24.10` branch at its floating HEAD (no static lock), applies the adapted `patches/24.10/`

**SNAPSHOT vs stable**:
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

## Troubleshooting

### Build Failures

| Symptom | Diagnosis | Fix |
|---------|-----------|-----|
| `fakeroot` hangs at `package/libs/toolchain/compile` | Stale `faked` daemon | `kill -9 $(pgrep -f 'faked\|fakeroot')` |
| Download <10 KB/s | No proxy configured | `export ALL_PROXY=socks5h://host:port` |
| `find: relative path in PATH` (WSL) | Windows PATH pollution | `PATH=$(echo "$PATH" \| tr ':' '\n' \| grep -v '^/mnt/' \| tr '\n' ':') make ...` |
| `GnuTLS recv error (-110)` | Direct GitHub connection failed | Use proxy; or `git config --global url."https://github.com/".insteadOf git://github.com/` |
| `Patch failed! No file to patch` (kernel prepare) | An OpenWrt-internal make variable (`PATCH_DIR`, `FILES_DIR`, `KDIR`) is pre-defined in the environment | Unset it; never export names OpenWrt's Makefiles define |
| `No more mirrors to give up` | Corrupted download in `dl/` | `rm dl/<bad-file>*` and retry |
| `cannot load such file -- erb` during the host Ruby build (24.10) | Host Ruby lacks the `erb` stdlib | Install it (Debian/Ubuntu `ruby`, Arch `ruby-erb`) or put a Ruby that provides `erb` first in `PATH` |

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

# If >26 MiB: reduce kmods in menuconfig
# Common culprits: kmod-fs-*, kmod-usb-*, kmod-crypto-*
```

## Contribution Workflow

### Before PR

```bash
# 1. Validate the affected channel contracts (no compilation)
./scripts/build-firmware --channel main --prepare-only
./scripts/build-firmware --channel openwrt-24.10 --prepare-only

# 2. Run the repository gates
./scripts/repository-check

# 3. Full builds run locally; see README "Building and releasing".
```

### Commit Convention

Conventional Commits (`feat:`, `fix:`, `docs:`, `refactor:`, `chore:`,
`ci:`). Release history lives in tags and GitHub Releases, not in a changelog
file.

### PR Checklist

- [ ] Affected channel contracts validated (`--prepare-only`)
- [ ] Image size gate understood (initramfs FIT ≤ 26 MiB enforced in build)
- [ ] Docs updated where a user-facing fact changed
- [ ] No secrets or personal environment data in the diff

## Verification

### Local Gates

```bash
# Repository validation
./scripts/repository-check

# Entrypoint + script syntax
bash -n scripts/build-firmware
for s in scripts/*.sh scripts/*-check; do sh -n "$s" 2>/dev/null || bash -n "$s"; done

# Channel contracts without compiling
./scripts/build-firmware --channel main --prepare-only
./scripts/build-firmware --channel openwrt-24.10 --prepare-only
```

### CI

GitHub Actions defines only the cheap project-native gates
(`repository-check`, patch-ledger consistency, entrypoint contract) plus the
PR body contract. Firmware is never compiled in CI: automatic Actions builds
are retired because the round-trip debug cycle was too long. The workflows are
currently disabled in repository settings.

## References

- [README.md](../../README.md) — onboarding, flashing, build/release commands
- [home-router.md](../operations/home-router.md) — runtime configuration patterns
- [router-state.md](../reference/router-state.md) — device/firmware state
- [patches/README.md](../../patches/README.md) — downstream patch ownership
- [scripts/README.md](../../scripts/README.md) — build/release entrypoints
- OpenWrt Build System: https://openwrt.org/docs/guide-developer/build-system/start
