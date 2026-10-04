# ADR 0001: haseen replaces Omarchy as the base

- **Status**: accepted 2026-10-04 (owner)

## Context

Omarchy 4 ships as Arch packages from its own repository (`pkgs.omarchy.org`). It requires `OMARCHY_PATH` in 15+ shell QML files and expects Limine, plymouth and its own kernel. Its install step overwrites `pacman.conf`, `mirrorlist` and the mkinitcpio HOOKS. omacachy exists only to undo those overwrites on CachyOS (`install-omarchy-quattro.sh`, about 2,000 lines). waydots is an overlay that cannot stand alone (its README says so).

## Decision

haseen is the base. It installs on CachyOS without Omarchy's system packages. These Omarchy pieces are lifted under MIT: the `colors.toml` theme format and template renderer, the CLI router convention, and the hook runner. Omarchy plugins and themes stay usable through compat (plan 011, plan 004).

**Amended 2026-10-04 (owner, plan 024):** the `[omarchy]` repository may be used as a *package source* for leaf packages such as `ttfx`.
- The `omarchy-repo` layer appends it last in `pacman.conf`, so official packages win name clashes.
- `lib/packages.sh` asks it after Chaotic-AUR and before the AUR.
- `omarchy` and `omarchy-settings` are refused by name in `PKG_DENY`. Those two are the packages that overwrite `pacman.conf`, the mirrorlist and HOOKS.

## Consequences

- No more reconciliation code against Omarchy's package overwrites.
- haseen owns everything Omarchy used to provide: bar, lock, launcher, notifications (plan 010).
- On an Omarchy host the installer warns and asks before continuing. Migrating such a host means a fresh CachyOS install followed by haseen; that is the supported path.
