# Plan 007: VAPT tooling layer

## Status

- **Priority**: —
- **Effort**: —
- **Risk**: —
- **Depends on**: 001
- **Category**: dropped
- **Planned at**: 2026-10-04, initial architecture
- **State**: DROPPED 2026-10-04 (owner decision)

## Decision

The owner removed requirement 9 (security-testing tooling) from haseen's
scope. Nothing from it ships:

- no `vapt` layer;
- no package lists;
- no NixOS `haseen.vapt` options;
- no architecture rows.

Every reference was removed in the same commit that recorded this decision.
