# Agent Instructions

## Product

This repository builds and releases reproducible OpenWrt firmware for the Xiaomi AX3000T AN8855 hardware variant.

It owns firmware build inputs, downstream AN8855 patches, build/release workflows, generic flashing/recovery guidance, and hardware-specific technical conclusions. Real household/office network topology and runtime device state belong to the private Homelab repository, not here.

## Architecture

- One repository control branch selects two upstream source channels: OpenWrt `main` and `openwrt-24.10`.
- `scripts/build-firmware` is the repository-native build entry point.
- `scripts/publish-release` publishes locally built firmware as an immutable GitHub Release; automatic Actions firmware builds are retired.
- `patches/README.md` is the ownership/removal ledger for downstream patches.
- Build trees and generated outputs live under ignored local state; they are not repository truth.
- A GitHub Release proves built artifacts, not physical flash acceptance.

Global Agent governance comes from Agent Charter. Workstation tooling comes from Workstations. Do not recreate either layer here.

## Working rules

- Inspect the relevant build script, patch ledger, workflows, and current upstream evidence before non-trivial changes.
- Verify a reported failure before modifying patches or build behavior; prefer the smallest bounded fix with an explicit removal condition.
- Prefer upstream OpenWrt behavior and mechanisms. Downstream patches exist only for demonstrated gaps.
- Never put real SSIDs, passwords, PPPoE credentials, Tailscale identities/IPs, private hostnames, local user paths, tokens, keys, or private network inventory in this public repository.
- Keep real runtime/router state in Homelab. Public documentation may contain only generic configuration patterns and hardware/firmware facts safe for publication.
- Do not add a generic repository standard, cross-repository canon, custom control plane, second build framework, or mandatory documentation taxonomy.
- Preserve one control branch and the two explicit upstream source channels unless a new Architect decision changes that model.
- Repository mutations use isolated Git task state and durable branch/commit/PR evidence under the global Agent Charter contract.

## Validation

Run the repository-native validation first:

```sh
./scripts/repository-check
```

For build-affecting changes, also prove the relevant channel preparation path:

```sh
./scripts/build-firmware --channel main --prepare-only
./scripts/build-firmware --channel openwrt-24.10 --prepare-only
```

Full firmware builds are expensive. Run them detached (background or another durable execution surface) rather than blocking an interactive session, and report the resulting artifacts, checksums, and build manifests as evidence.

Do not claim a firmware release is physically accepted until the applicable real-device flash/recovery checks have been performed.
