# Plan 023: Package source order with Chaotic-AUR before the AUR

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (dry-run tested; the repo enable path follows the owner's waydots code)
- **Depends on**: 001 003 017
- **Category**: packaging
- **Planned at**: 2026-10-04, owner request ("aur is last resort, chaotic is more preferable")
- **State**: DONE 2026-10-04

## Why this matters

Building AUR packages from source is slow and runs unreviewed PKGBUILDs.
Chaotic-AUR ships the same packages prebuilt and signed. Before this plan,
every `aur:` entry went straight to paru or yay.

## What changed

- `share/haseen/lib/packages.sh` now resolves every package that is not in the official repos in a fixed order:
  1. an enabled official or CachyOS repository (for example `lib32-nvidia-580xx-utils` on CachyOS);
  2. `chaotic-aur/<pkg>`;
  3. the AUR, with a "last resort" warning.

  When no AUR helper exists, it installs paru from Chaotic-AUR. The lookups are read-only and fixture-aware (`pkg_enabled_repos`, `pkg_repo_has`, `pkg_source`).
- All entry points already went through `pkg_install_aur`: manifest `aur:` lines, catalogue `"source": "aur"` apps, `haseen install aur`, and the gaming layer's 32-bit NVIDIA drivers. So the new order applies everywhere without changing those callers.
- New layer `share/haseen/layers/chaotic`, ported from waydots `ensure_chaotic_aur`:
  - pinned key `EF925EA60F33D0CB85C44AD13056513887B78AEB`, checked by fingerprint on a real run;
  - lsign;
  - keyring and mirrorlist from `cdn-mirror.chaotic.cx`;
  - the `[chaotic-aur]` stanza appended once;
  - then `pacman -Syu` (not `-Sy`, which would leave a partial upgrade).
- `desktop` now requires `chaotic`. `install.sh` defaults to `base chaotic desktop theme shell`.
- Docs: `AGENTS.md` (AUR last-resort rule), `docs/architecture.md` §3 (the layer, the source order, the second pacman.conf exception) and `README.md`.

## Evidence

- `tests/test-core.sh`:
  - a repo hit, a Chaotic hit and an AUR-only package each go to the right source;
  - a mixed list builds only the AUR-only package;
  - without Chaotic, the warning suggests enabling it;
  - the chaotic layer's dry run shows the pinned key, the fingerprint check, the CDN packages, the stanza and `-Syu`;
  - a second apply is a no-op;
  - all of this is dry-run pure.
- Real availability, read from luna, which has Chaotic-AUR:
  - in Chaotic: `xpadneo-dkms` 0.10.4-1, `nordvpn-bin` 5.4.0-1, `lib32-nvidia-580xx-utils` 580.178.04-1 and `paru` 2.1.0-2.1;
  - not in Chaotic: `ttfx` and `cursor-bin`. These still build from the AUR, with the warning.

## Rejected

- **Auto-enabling Chaotic-AUR from `pkg_install_aur`.** Adding a third-party repository is a decision, so it stays an explicit layer. It is in the default set and required by `desktop`, which makes it the norm without being a hidden side effect.
- **`pacman -Sy` after adding the repo** (as waydots does). That leaves a partial upgrade if a package is installed next.
