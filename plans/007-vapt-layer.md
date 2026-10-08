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
suites. Requirement 11 in `docs/architecture.md` and the `vapt` row in its
layer table now describe it; the "no architecture rows" line above describes
the 2026-10-04 state only. Independent final review is outstanding.

The layer sets `LAYER_PICKABLE=false` (contract in `share/haseen/lib/layers.sh`),
so the interactive install picker never offers it and drops it from a saved
choice. Applied without groups it refuses, which once aborted the installer
after the earlier layers had applied (plan 087 batch B). `./install.sh
--vapt-groups` remains the installer route, and `--pick` with it is refused.
Shell activation seeds only the owned link `~/.config/haseen/vapt/shell.sh`.
The layer never edits `~/.bashrc` or `~/.zshrc`; it reuses an rc or shell-rc
include that already sources the link and otherwise prints the exact line to
add (plan 087 batch C, `docs/vapt.md`).

Plan 087 extends this layer with ten more tool groups from oniomarchy's
categories, reviewed package aliases and dependency roles, canonical URL
identities, and the opt-in private signed oniomarchy package source (slice 1B,
implemented).
