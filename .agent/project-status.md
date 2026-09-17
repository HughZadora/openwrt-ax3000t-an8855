# Project Status

> **Date**: 2026-09-18
> **Status**: active
> **Authoritative sources**: repository state and `docs/` (routing: `docs/INDEX.yaml`)

## Current State

OpenWrt mainline (kernel 6.18) firmware build for the Xiaomi Mi Router AX3000T AN8855 variant.
CI/CD, semantic-release, and VERIFIED_COMMIT auto-update are implemented and live. The
2026-09 health check, its findings (A/B/C), and the fixes are recorded in
`docs/reports/health-check-2026-09.md`.

## Key Facts

- Single-UBI AN8855 target is mandatory for stock U-Boot; the dual-partition stock target
  bootloops on this hardware.
- initramfs FIT must stay ≤ 26 MiB; enforced by `scripts/check-image-size.sh` with `STRICT=1`.
- OpenClash is compiled as a standalone apk (`CONFIG_PACKAGE_luci-app-openclash=m`) and is not
  part of the firmware image.
- The build config contract (seed + owned symbols) is
  `scripts/build/generate-config-seed.sh`, shared by local builds and CI.
- `CONFIG_VERSION_REPO` (USTC mirror) is inert in a plain source build because it sits behind
  `CONFIG_IMAGEOPT`/`CONFIG_VERSIONOPT`; built images keep the upstream
  `downloads.openwrt.org` feeds.

## Known Limits

- No automated firmware or hardware testing; verification relies on flashing the device.
- CI has no persisted ccache, so every run is a cold build against a 180-minute job timeout.

## Next Steps

1. Decide whether to keep, fix, or drop the inert USTC-mirror configuration (see the health
   check report).
2. Consider CI ccache persistence if build times approach the job timeout.
