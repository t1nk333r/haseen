# Plan 001: Foundation: layer runner, CLI router, dry-run contract, fixtures

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW
- **Depends on**: —
- **Category**: core
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: DONE 2026-10-04

## Why this matters

Everything else is built on this. Without a single dry-run contract, a shared preflight and a layer interface, each slice would invent its own.

## Scope

- `share/haseen/lib/{common,preflight,packages,layers}.sh`. The dry-run contract is adapted from omacachy; ESP-first bootloader detection is ported from omacachy `install-omarchy-quattro.sh:327-438`.
- `bin/haseen`: longest-prefix router with `# haseen:` metadata. The convention comes from Omarchy and is MIT.
- `bin/haseen-layer-{list,status,apply,remove}` and `bin/haseen-doctor`.
- `install.sh`: copies the tree to `/usr/local` atomically and applies the default layers.
- `tests/run.sh` + `tests/lib.sh`: stub PATH plus six sysroot fixtures.
- `tools/lint.sh`: bash -n, shellcheck, luac, jq, qmllint.

## Acceptance

- `tools/lint.sh` passes with zero warnings.
- `tests/run.sh` passes: 28 checks covering the preflight matrix, router, dependency order, cycles, conflicts, the distro gate, manifest validation, dry-run purity, and the installer refusing NixOS.
- `haseen doctor` on the author's Omarchy laptop reports `omarchy / uefi / setup / limine / luks / intel`, which matches `bootctl status` and `lsblk`.

## Execution record

Executed 2026-10-04 in the initial commit. Lint and test output were captured at commit time.
