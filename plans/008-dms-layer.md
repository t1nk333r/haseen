# Plan 008: DMS optional layer and shell switch

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: 005
- **Category**: shell
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 4. DMS and the haseen shell both claim `org.freedesktop.Notifications`, the polkit agent and the lock, so only one of them can run at a time.

## Scope

- `layers/dms` installs `dms-shell` with `--assume-installed dms-shell-compositor`.
- Conflicts drop-in.
- `bin/haseen-shell-use`.
- `layers/dms/ipc-translate`.

## Acceptance

- `haseen shell use dms|haseen` switches units cleanly (fixture test plus a live check of the unit files).
- The binds keep working through `ipc-translate`.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
