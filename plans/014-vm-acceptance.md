# Plan 014: End-to-end acceptance on a real CachyOS guest

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: 001-012
- **Category**: release
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: BLOCKED: no qemu, no sudo and no docker access on the author's laptop session (2026-10-04)

## Why this matters

Fixture tests prove the plan logic, not the result. omacachy learned this in its plans 016/017.

## Scope

A CachyOS VM (OVMF with Secure Boot in Setup Mode, and a Windows ESP stub) running `./install.sh --layers base,desktop,theme,shell,secureboot`.

## Acceptance

- The guest boots with Secure Boot enabled.
- The desktop logs in.
- `haseen doctor` is all green.
- Screenshot evidence.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
