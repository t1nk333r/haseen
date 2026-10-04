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
