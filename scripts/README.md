# scripts

## Responsibility

Owns the repository-native build, release, configuration, and validation
entrypoints. Everything that compiles, publishes, or gates firmware is driven
from here, so local execution and any future CI use the same contract.

## Edit here

| Script | Role |
| --- | --- |
| `build-firmware` | Build entrypoint: resolve the channel to an exact upstream SHA, prepare source/feeds/config, compile, run the size gate, and write channel-prefixed artifacts plus `build-manifest.json`. `--prepare-only` validates the contract without compiling. |
| `publish-release` | Publish locally built firmware as one immutable GitHub Release: verifies both channels' assets and manifests, rejects a channel/commit mismatch, refuses to overwrite an existing tag, writes `SHA256SUMS.txt`, and targets the repository commit recorded in the manifests. `--dry-run` verifies without publishing. |
| `generate-config-seed.sh` | Writes the reproducible `.config` seed (target, initramfs compression, curated package set, mirrors) consumed by `build-firmware`. |
| `inject-firstboot-defaults.sh` | Installs the first-boot `uci-defaults` (LAN address, Wi-Fi enabled without a key) into the prepared upstream tree. |
| `check-image-size.sh` | Enforces the 26 MiB initramfs FIT limit and prints the flashing manifest. Called by `build-firmware` with `STRICT=1`. |
| `repository-check` | Project-native validation: required files, shell syntax, SHA-pinned external Actions, no tracked build output. |
| `pull-request-check` | PR body contract: references an issue and has `## Summary` and `## Validation` sections. |

## Boundaries

- `build-firmware` is the only supported build path. Do not add a second build
  framework or duplicate its channel logic elsewhere.
- Builds never mutate the repository: no `VERIFIED_COMMIT` updates, no release
  commits. `publish-release` is a separate, explicit publication step.
- Never export variable names OpenWrt's Makefiles define (`PATCH_DIR`,
  `FILES_DIR`, `KDIR`); a collision silently redirects kernel patch paths.
- Keep generated state under the ignored `build/` tree, not in the repository.
- Do not hardcode personal environment values; the seed and first-boot
  defaults stay generic.

## Maintenance

Update this README when a script is added, removed, or changes its contract,
and when `build-firmware`/`publish-release` usage changes materially. Keep the
per-script detail in the scripts themselves; this README is orientation only.
