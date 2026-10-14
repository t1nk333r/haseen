# Plan 007: VAPT tooling layer

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (root package transactions and shared pacman keyring trust; `docs/vapt.md`)
- **Depends on**: 001
- **Category**: vapt (dropped 2026-10-04, reinstated 2026-10-07)
- **Planned at**: 2026-10-04, initial architecture
- **State**: DROPPED 2026-10-04 (owner decision); reinstated 2026-10-07; DONE 2026-10-12 (merged as PR #39), amended 2026-10-13 (plan 090)

## Decision (2026-10-04)

The owner removed requirement 9 (security-testing tooling) from haseen's
scope: no `vapt` layer, package lists, NixOS `haseen.vapt` options or
architecture rows. Every reference was removed in the commit that recorded
this decision.

## Reinstatement (2026-10-07)

The owner brought optional security-tool provisioning back as an optional
layer, not a requirement:

- no tools by default, explicit `--groups`/`--all` selection only;
- no AUR and no Omarchy package, provider or command dependency;
- the layer never runs a tool it installs, never enables or starts a service,
  and never executes an assessment;
- dry-run is offline and write-free.

It is `share/haseen/layers/vapt/` with `docs/vapt.md`,
`bin/haseen-vapt-{install,status,remove}` and the `tests/test-vapt*.sh`
suites; requirement 11 and the `vapt` row in `docs/architecture.md` describe
it.

Source order (owner decision, 2026-10-13): explicit pins, BlackArch, pinned
native (pipx) adapters, enabled Chaotic-AUR, CachyOS, Arch. This is an explicit
exception to haseen's repository-wide order (`AGENTS.md`, plans 023 and 024):
it keeps the source policy of the owner's waydots security inventory, and it
has no Omarchy or AUR tier (`docs/architecture.md:93-101`,
`share/haseen/layers/vapt/provision.sh:277-281`).

The layer sets `LAYER_PICKABLE=false` (`share/haseen/layers/vapt/layer.sh:8`,
contract in `share/haseen/lib/layers.sh`): the install picker never offers it
and drops it from a saved choice, because applied without groups it refuses.
`./install.sh --vapt-groups` is the installer route; `--pick` with it is
refused. Shell activation seeds only the owned link
`~/.config/haseen/vapt/shell.sh` and never edits `~/.bashrc` or `~/.zshrc`;
an rc whose own command sources the link is reused, otherwise the exact line
to add is printed (plan 087).

Plan 087 adds ten tool groups from oniomarchy's categories, reviewed aliases
and dependency roles, canonical URL identities and the opt-in private signed
oniomarchy source. Plan 088 adds the installed workflow and the optional
Security panel. Plan 090 records the fixes of the 2026-10-13 audit.
