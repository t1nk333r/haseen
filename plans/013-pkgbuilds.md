# Plan 013: PKGBUILDs for the stable layers

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: LOW
- **Depends on**: 001-012
- **Category**: packaging
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED (later phase, owner decision 2026-10-04)

## Why this matters

The owner chose 'installer now, PKGBUILDs later'. Packaging moves PREFIX to /usr and hands updates to pacman.

## Scope

`pkg/haseen/PKGBUILD` and friends.

## Acceptance

`makepkg` builds the package, `namcap` is clean, and the installer refuses to run when the package is installed.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
