# OpenWrt AX3000T (AN8855)

![CI](https://github.com/HughZadora/openwrt-ax3000t-an8855/actions/workflows/ci.yml/badge.svg)
![License](https://img.shields.io/badge/license-GPL--2.0-blue.svg)

Build reproducible OpenWrt firmware for the Xiaomi Mi Router AX3000T with the
AN8855 switch variant. The project produces a single-UBI firmware target for
stock U-Boot, includes Tailscale in the image, and publishes OpenClash as a
separate APK so the initramfs remains within the bootloader limit.

## Important warning

This firmware is for the **AX3000T AN8855 hardware variant**. Do not flash it
to an unrelated AX3000T variant. The AN8855 target uses a single UBI layout;
the standard dual-partition target can boot into recovery or fail to persist.
Flashing firmware can permanently damage a router. Keep a recovery path and
verify the exact hardware before proceeding.

## Supported builds

One repository control branch (`main`) selects between two upstream
source channels, which are inputs -- not long-lived repository branches:

| Channel | Upstream branch | Target handling |
| --- | --- | --- |
| `main` | OpenWrt `main` | Applies the repository AN8855 patch set (`patches/main/`) at the exact SHA recorded in `patches/VERIFIED_COMMIT` (static recovery lock). |
| `openwrt-24.10` | OpenWrt `openwrt-24.10` | Applies the adapted repository AN8855 patch set (`patches/24.10/`) at the resolved branch SHA. |

Upstream provides the AN8855 switch driver on both channels but no
single-UBI board target, so the board target stays a downstream delta on
both (see `patches/README.md` for the ownership ledger).

> **Note:** `main`-channel builds are OpenWrt snapshots by design: they
> compile upstream OpenWrt `main` at the locked SHA, which is why the
> version string is a snapshot. After flashing, LuCI and
> `/etc/openwrt_release` report `SNAPSHOT rXXXX` instead of a stable
> version number -- this is expected, not a flash failure (see issue #4).
> Snapshot is the default because the AN8855 switch support and related
> Filogic fixes are newest there; the `openwrt-24.10` channel is older but
> reports a stable version string. See the
> [development guide](docs/development/guide.md) for the tradeoff.

The build includes Tailscale, LuCI, `luci-compat`, networking and diagnostic
packages, WireGuard, QoS modules, zram, and a curated filesystem/module set.
OpenClash is built separately as an APK.

## Quick start

### Requirements

- Linux x86_64 or WSL2
- At least 8 GB RAM and 80 GB free disk space
- Bash, Git, and a working OpenWrt build environment
- Optional proxy for domestic downloads:
  `export ALL_PROXY=socks5h://host:port`

### Prepare and build

```sh
git clone https://github.com/HughZadora/openwrt-ax3000t-an8855.git
cd openwrt-ax3000t-an8855

# Validate the channel contract without compiling (resolve, patch,
# feeds, defconfig). Needs only git/patch/standard shell.
./scripts/build-firmware --channel main --prepare-only

# Or run the full build (needs the OpenWrt toolchain; takes hours).
./scripts/build-firmware --channel main
```

For the 24.10 channel, replace `main` with `openwrt-24.10`.

`scripts/build-firmware` is the single repository-native build entrypoint.
Firmware is built locally; CI runs only the cheap project gates. Upstream
source and build trees live under `build/` (ignored state).

The first full build may take several hours and requires substantial disk space.

## Build outputs

Firmware images, the OpenClash package, checksums, and a build manifest
are collected under:

```text
build/out-main/
build/out-openwrt-24.10/
```

Asset names carry the channel (`main-...`, `openwrt-24.10-...`). Each
directory contains:

- `<channel>-*-initramfs-factory.ubi` -- temporary RAM boot image;
- `<channel>-*-squashfs-sysupgrade.bin` -- persistent sysupgrade image;
- `<channel>-luci-app-openclash.*` -- OpenClash package (format follows
  the channel feed: `.apk` on both current channels);
- `SHA256SUMS.txt`;
- `build-manifest.json` -- channel, upstream branch, exact upstream SHA,
  repository SHA, timestamps.

## Flashing

The recommended sequence is initramfs first, then persistent sysupgrade:

```sh
# From the stock/recovery system.
scp openwrt-*-initramfs-factory.ubi root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'mtd -f write /tmp/openwrt-*-initramfs-factory.ubi ubi && reboot'

# After the router boots the RAM system.
scp openwrt-*-squashfs-sysupgrade.bin root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'sysupgrade -n /tmp/openwrt-*-squashfs-sysupgrade.bin'
```

After the first boot, set a root password and configure Wi-Fi encryption before
connecting the router to an untrusted network. Install OpenClash separately:

```sh
scp luci-app-openclash-*.apk root@192.168.31.1:/tmp/
ssh root@192.168.31.1 \
  'apk add /tmp/luci-app-openclash-*.apk luci-compat'
```

## Repository layout

```text
patches/                         Per-channel AN8855 deltas + ownership ledger
scripts/build-firmware           Repository-native build entrypoint
scripts/publish-release          Publish locally built firmware as one release
scripts/check-image-size.sh      Initramfs size validation
scripts/generate-config-seed.sh  Reproducible package/config seed
scripts/inject-firstboot-defaults.sh  First-boot defaults
build/                           Ignored upstream source/build/output trees
docs/                            Durable development/operations references
.github/workflows/               Cheap project gates and the PR contract
```

## Common commands

| Task | Command |
| --- | --- |
| Validate repository | `./scripts/repository-check` |
| Validate channel contract (no compile) | `./scripts/build-firmware --channel main --prepare-only` |
| Full build | `./scripts/build-firmware --channel main` |
| Build OpenWrt 24.10 | `./scripts/build-firmware --channel openwrt-24.10` |
| Configure packages | `cd build/upstream-main && make menuconfig` |
| Compile OpenClash | `cd build/upstream-main && make package/feeds/openclash/luci-app-openclash/compile V=s` |
| Validate initramfs size | `STRICT=1 scripts/check-image-size.sh build/upstream-main/bin/targets/mediatek/filogic` |
| Publish a release | `./scripts/publish-release --dry-run` then `./scripts/publish-release` |

## Building and releasing

Firmware is built locally with `scripts/build-firmware` and published with
`scripts/publish-release`. Automatic GitHub Actions firmware builds are
retired: the round-trip debug cycle was too long, so a periodic local build
is preferred.

```sh
./scripts/build-firmware --channel main
./scripts/build-firmware --channel openwrt-24.10
./scripts/publish-release   # tag defaults to the current UTC month (vYY.MM)
```

`scripts/publish-release` stages both channels' images, OpenClash packages
and build manifests, writes `SHA256SUMS.txt`, and creates one immutable
GitHub Release targeting the commit recorded in the build manifests. It
refuses to overwrite an existing tag, and `--dry-run` verifies the inputs
without publishing anything.

A release means **built**, never physically accepted -- see the manual
acceptance contract in the release notes before flashing anything.

GitHub Actions defines only the cheap project-native gates
(`repository-check`, patch-ledger consistency, entrypoint contract) plus the
PR body contract; the workflows are currently disabled in repository
settings.

## Constraints

- The stock bootloader requires the AN8855 single-UBI layout.
- The initramfs FIT image must remain at or below 26 MiB.
- OpenClash is intentionally not included in the firmware image.
- The standard AX3000T/MT7531 target is not interchangeable with this target.
- OpenWrt source and build outputs are local ignored artifacts, not repository
  state.
- Real household/office network topology and live router state belong to the private Homelab source of truth, not this public firmware repository.

## Documentation

- [Development guide](docs/development/guide.md)
- [Router operations](docs/operations/home-router.md)
- [Router firmware reference](docs/reference/router-state.md)

## License

GPL-2.0, consistent with OpenWrt.

## Validation

Run the project-native repository validation locally:

```sh
./scripts/repository-check
```
