# Plan 002: Secure Boot layer for Windows dual boot

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH (firmware keys)
- **Depends on**: 001
- **Category**: security
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 8. Anti-cheat on Windows (Vanguard, FACEIT, EA Javelin) requires Secure Boot to be on. Neither Omarchy nor omacachy enrolls keys: Omarchy's manual tells users to turn Secure Boot off.

## Scope

- `share/haseen/layers/secureboot/`: `layer.sh`, a pacman hook and a re-sign script.
- `bin/haseen-secureboot-{status,setup,sign}`.
- See docs/architecture.md §8 for the full model.

## Acceptance

- Fixture tests for Limine and systemd-boot, Setup Mode and enabled, with and without Windows on the ESP.
- Dry-run is pure.
- Refuses outside Setup Mode.
- Typed confirmation is required.
- The BitLocker warning is printed when Windows is present.
- Microsoft and firmware-builtin keys are always enrolled.
- Real-hardware enrollment is an owner acceptance step (plan 014).

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
