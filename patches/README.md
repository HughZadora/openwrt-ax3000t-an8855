# patches

## Responsibility

Owns the downstream deltas that upstream OpenWrt does not provide: the
`xiaomi_mi-router-ax3000t-an8855` single-UBI board target and the bounded
compatibility shims required to build it per channel.

Upstream OpenWrt provides the AN8855 *switch driver* on both channels, but
**neither** `main` nor `openwrt-24.10` defines an
`xiaomi_mi-router-ax3000t-an8855` single-UBI *board target* (verified
2026-09-22 against upstream HEADs: only the stock `ax3000t` and
`ax3000t-ubootmod` devices exist). The board target therefore stays a
downstream delta until upstream gains an equivalent.

## Edit here

| Path | Role |
| --- | --- |
| `common/mt7981b-xiaomi-mi-router-ax3000t-an8855.dts` | Shared single-UBI device tree. Its only upstream include (`mt7981b-xiaomi-mi-router-ax3000t.dtsi`) exists on both channels. |
| `main/0001-add-an8855-target.patch` | Main-channel target patch. Applies cleanly (zero offsets) at `VERIFIED_COMMIT`. |
| `24.10/0001-add-an8855-target.patch` | Adapted, not copied: the 24.10 `platform.sh` upgrade structure differs (its single-UBI group is `cudy,wr3000h-v1\|wr3000p-v1`). Generated against upstream `openwrt-24.10` HEAD with zero offsets and zero fuzz. |
| `24.10/0002-host-libsepol-c17-compat.patch` | Bounded host-only compatibility shim. |
| `VERIFIED_COMMIT` | Static recovery lock for the main channel. |

`scripts/build-firmware` copies the shared DTS and dry-runs then applies
`patches/<channel>/` before compiling. Advancing `VERIFIED_COMMIT` is an
intentional repository change: resolve upstream to an exact SHA, dry-run the
patches, complete a channel build, then record the SHA with its verification
note. Builds never mutate it.

## Boundaries

- One delta per demonstrated upstream gap. Do not carry patches merely because
  they exist, and do not drop them merely because upstream names something
  similar.
- Each entry is classified `required-downstream`, `equivalent-upstream`,
  `backport`, or `local-policy`. All entries here are `required-downstream`.
- The libsepol shim is host-only: upstream 24.10 pins host libsepol 3.5, whose
  `conditional.h` declares `uint32_t bool` and fails on C23-default host
  compilers. It adds `HOST_CFLAGS += -std=gnu17` to that one package Makefile,
  so target firmware flags and the `main` channel are untouched. **Removal
  condition:** delete it once the tracked 24.10 source no longer needs it
  (libsepol updated or backported to C23-compatible source, or the branch
  retired).
- No upstream working-tree edits: a fresh clone must be reproducible by
  applying these files, never by relying on uncommitted changes.
- Fail loud, not silent: the entrypoint dry-runs every channel patch, so an
  upstream context change breaks the build instead of persisting unnoticed.

## Maintenance

Update this README when a patch is added or removed, when a delta's ownership
status changes (for example upstream gains the target), or when a removal
condition is met. Full-compile proof comes from a local channel build, not
from this ledger.
