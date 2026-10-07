# Plan 007: VAPT tooling layer

## Status

- **Priority**: —
- **Effort**: —
- **Risk**: —
- **Depends on**: 001
- **Category**: vapt (dropped 2026-10-04, reinstated 2026-10-07)
- **Planned at**: 2026-10-04, initial architecture
- **State**: DROPPED 2026-10-04 (owner decision); reinstated 2026-10-07 and IN PROGRESS (see "Reinstatement"; the live status is the row in `plans/README.md`)

## Decision

The owner removed requirement 9 (security-testing tooling) from haseen's
scope. Nothing from it ships:

- no `vapt` layer;
- no package lists;
- no NixOS `haseen.vapt` options;
- no architecture rows.

Every reference was removed in the same commit that recorded this decision.

## Reinstatement (2026-10-07)

The decision above is kept as it was made. On 2026-10-07 the owner brought
optional security-tool provisioning back into scope, on the terms that make it
an optional layer rather than a requirement:

- no tools by default, explicit `--groups`/`--all` selection only;
- no AUR and no Omarchy package, provider or command dependency;
- the layer never runs a tool it installs, never enables or starts a service,
  and never executes an assessment;
- dry-run is offline and write-free.

The layer landed as `share/haseen/layers/vapt/` with `docs/vapt.md`,
`bin/haseen-vapt-{install,status,remove}` and the `tests/test-vapt*.sh`
suites. Requirement 10 in `docs/architecture.md` and the `vapt` row in its
layer table now describe it; the "no architecture rows" line above describes
the 2026-10-04 state only. Independent final review is outstanding.

Plan 083 extends this layer: ten more tool groups from oniomarchy's
categories, reviewed package aliases and dependency roles, canonical URL
identities, and later an opt-in signed package source.
