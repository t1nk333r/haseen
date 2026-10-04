# Plan 007: VAPT layer (BlackArch, contained by default)

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM
- **Depends on**: 001
- **Category**: security
- **Planned at**: 2026-10-04, initial architecture (docs/architecture.md)
- **State**: PLANNED

## Why this matters

Requirement 9. A Kali-like toolset without turning the host into Kali. BlackArch is ported from waydots `lib/security.sh`, keeping its pinned `strap.sh`.

## Scope

- `layers/vapt`: container mode (a distrobox from the BlackArch image, the default) and host mode (pinned strap plus a group allow-list).
- `bin/haseen-vapt-{list,install,enter}`.

## Acceptance

- Fixture tests for both modes.
- The strap checksum is enforced.
- Dry-run is pure.

## Execution record

_Filled in by the executor: what changed, which evidence ran, what was rejected and why._
