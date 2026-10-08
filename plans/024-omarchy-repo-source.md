# Plan 024: Omarchy's repository as a package source

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MEDIUM (a third-party repo sharing names with official packages; mitigated below)
- **Depends on**: 023
- **Category**: packaging
- **Planned at**: 2026-10-04, owner request ("can we use omarchy repo?")
- **State**: DONE 2026-10-04 (fixture and dry-run tested; not run on a real CachyOS host, plan 014)

## Why this matters

Some packages haseen uses exist prebuilt only in Omarchy's signed repository.
`ttfx`, the screensaver's text effects, is not in the official repos or in
Chaotic-AUR, so without `[omarchy]` it is built from the AUR. This was checked
on luna, which has Chaotic-AUR, on 2026-10-04.

## Facts (2026-10-04, read on io, which has `[omarchy]`)

- 253 packages in `pkgs.omarchy.org/stable`.
- 12 names clash with `core`/`extra`/`multilib`: asusctl, ghostty (+3 split
  packages), gpu-screen-recorder, intel-lpmd, linux-firmware-cirrus, opencode,
  pinta, rog-control-center, umu-launcher. The repo also carries
  `limine-mkinitcpio-hook` and `limine-snapper-sync`, which CachyOS ships
  itself.
- `omarchy/ttfx` is 0.3.2-1, the version the Omarchy screensaver port was
  checked against (plan 019). AUR `ttfx` is 0.5.0-1.
- Trust (Omarchy `bin/omarchy-update-keyring`): key
  `40DFB630FF42BCFFB047046CF0134EE680CAC571` from keys.openpgp.org, then
  `omarchy-keyring`. omacachy uses `SigLevel = Required DatabaseOptional`.

## What changed

- `lib/packages.sh`:
  - New source tier: official/CachyOS repos, then Chaotic-AUR, then `[omarchy]`, then the AUR. Packages are installed repo-qualified as `omarchy/<pkg>`.
  - New `PKG_DENY` list (`omarchy`, `omarchy-settings`). Both `pkg_install` and `pkg_install_aur` refuse it, because those two packages overwrite `pacman.conf`, the mirrorlist and HOOKS (ADR 0001).
- New layer `share/haseen/layers/omarchy-repo`:
  - pinned key, verified by fingerprint, then lsign;
  - the stanza is appended last, with signed packages required;
  - `pacman -Syu`, then `omarchy/omarchy-keyring`.
  - Its status warns if `[omarchy]` is no longer the last repo, because then its packages can shadow official ones in plain `pacman -S`.
- Default layers: `base chaotic omarchy-repo desktop theme shell`. `desktop` does not require it: without it, ttfx falls back to the AUR with the last-resort warning.
- ADR 0001 is amended. `AGENTS.md`, `docs/architecture.md` §3 and `README.md` are updated.

## Evidence

`tests/test-core.sh`:
- ttfx resolves to `omarchy/ttfx`;
- Chaotic still wins for a package that both repos carry;
- `omarchy` and `omarchy-settings` are refused through both install paths;
- the layer's dry run shows the pinned key, fingerprint check, `SigLevel`, stable server and keyring;
- status is ok when `[omarchy]` is last;
- all of it is dry-run pure.

## Rejected

- **Putting `[omarchy]` before Chaotic-AUR.** Chaotic-AUR rebuilds from AUR PKGBUILDs, which tracks upstream more closely. Omarchy's repo is curated for Omarchy's own versions (ttfx 0.3.2 vs 0.5.0).
- **The rc/edge channels.** haseen pins `stable`.
- **Making `desktop` require the layer.** One leaf package does not justify a hard dependency on a second third-party repo.

## Amendment 2026-10-08: [omarchy]-only packages

Owner decision: herdr and xdg-terminal-exec are taken only from `[omarchy]`.
herdr's AUR build is AGPL-3.0 (Apache-2.0 in `[omarchy]`) and once hung for 44
minutes in a `zig fetch` (plan 014, finding 3). `desktop` still does not require
the layer, so a `--layers` list or a picker choice without it must not fail.

- The manifest gains an `omarchy:` prefix (`share/haseen/lib/packages.sh`).
  `pkg_install_omarchy` sends these entries through the binary part of
  `pkg_install_aur`'s source order (official/CachyOS, Chaotic-AUR,
  `[omarchy]`) when `[omarchy]` is enabled. Without it, they are skipped
  with one warning that names them and the command that adds them:
  `haseen layer apply omarchy-repo desktop`. They are never built from the AUR.
- `haseen layer apply` exports its apply order as `HASEEN_APPLY_LAYERS`. A dry
  run in which `omarchy-repo` comes before `desktop` plans the packages from
  the repo (`omarchy/herdr`), because the real run will have enabled it by then.
  When `omarchy-repo` comes after `desktop` they are skipped, as the real run
  would skip them.
- `desktop/packages.txt`: `omarchy:xdg-terminal-exec`, `omarchy:herdr`. ttfx
  stays an `aur:` entry.

Evidence: `tests/test-desktop.sh`, section "herdr and xdg-terminal-exec need
[omarchy]". On the AMD fixture without the repo, the layer applies, warns
about both packages, and plans no install of either from any source. With
`omarchy-repo desktop` it plans `pacman -S --needed omarchy/xdg-terminal-exec
omarchy/herdr` and gives no warning. With `desktop omarchy-repo` both are
skipped. With `[omarchy]` already in `pacman.conf` both install from it.
Before the change, 146/150 passed; after, 150/150.

Security re-review SEC-7 (2026-10-08): the first version called
`pkg_install_aur` itself when `[omarchy]` was enabled, so an entry that no
enabled repo carried, or whose database lookup failed, fell through to
`paru -S`. Both functions now share `_pkg_install_sourced LAST`, which
resolves each package's source once; `pkg_install_aur` passes `aur`,
`pkg_install_omarchy` passes `skip`, which leaves such packages out with a
warning ("… they are never built from the AUR"). Evidence: the same section,
with `[omarchy]` enabled, a `paru` on `PATH`, and the fixture database first
without herdr/xdg-terminal-exec, then unreadable. Before the fix both cases
planned `paru -S --needed xdg-terminal-exec herdr` (154/158); after, 158/158.
