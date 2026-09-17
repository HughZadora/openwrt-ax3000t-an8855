# Project State

> **Date**: 2026-09-18
> **Author**: maintainer (auto-maintained notes; `docs/` is the source of truth)
> **Scope**: openwrt-ax3000t-an8855
> **Purpose**: short handoff pointer; durable knowledge lives in `docs/` (routing: `docs/INDEX.yaml`)
> **Status**: active

## Entry Points

- Prepare source/feeds/config: `bash setup.sh`
- Full build: `bash setup.sh build`
- Repository baseline: `scripts/repository-check`
- PR body contract: `scripts/pull-request-check <body-file>`
- Image size gate: `scripts/check-image-size.sh openwrt-ax3000t/bin/targets/mediatek/filogic`
- Tests: none (no automated firmware or hardware test suite; verification = build + size gate + flash)
- Documentation: `README.md`, `docs/development/guide.md`, `docs/operations/home-router.md`,
  `docs/reference/router-state.md`, `docs/reports/`

## Structure

- `setup.sh` — argument parsing and step order only
- `scripts/build/*.sh` — one script per build step, shared by `setup.sh` and
  `.github/workflows/ci.yml`
- `patches/` — AN8855 single-UBI target patch set plus the `VERIFIED_COMMIT` lock
- `.github/workflows/` — ci / release / pull-request / repository-baseline

## Verified Facts (2026-09-18)

- OpenWrt baseline: `928cd26bd938b8ac46b79e14f5f9f4b1d772abe8` (upstream `main`); see
  `patches/VERIFIED_COMMIT`
- Repository baseline check: pass (`scripts/repository-check`)
- No lint/typecheck/formatter toolchain is tracked (this file previously claimed gates that
  do not exist)
- `README.zh.md` and `DEVELOPMENT.md` do not exist; `README.md` is the only onboarding document
- Local full build runs in an out-of-repo worktree; results and findings are in
  `docs/reports/health-check-2026-09.md`

## Notes

- `.agent/plans/active/*` are historical plans from 2026-08-21 whose work is complete; kept as
  history, not as pending work.
- This file is not authoritative. When it disagrees with the repository or `docs/`, the
  repository wins.
