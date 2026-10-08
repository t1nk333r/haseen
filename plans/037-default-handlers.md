# Plan 037: Default handlers (four places) and the catalogue's missing half

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (one guarded path can pull the `omarchy` package onto a haseen machine, by owner decision)
- **Depends on**: 003 017 023 024
- **Category**: desktop
- **Planned at**: 2026-10-05, owner request (items 1–5, 8, 24–26 and the ranked gaps 2 and 3)
- **State**: DONE 2026-10-05

## Problem

haseen conflated *installable* with *default*. `share/haseen/default/catalog.json`
was an install menu of 68 entries across 8 categories, and the only handler
wiring in the whole tree was `export TERMINAL=foot`
(`share/haseen/layers/desktop/layer.sh`). A repo-wide grep for `mime` had zero
hits. So a GTK app asked to open a folder, an image or a terminal fell through
to whatever `/usr/share` still carried from Omarchy. The catalogue also had no
handler-able app at all — no file manager, image viewer, video player or PDF
reader — and no way to install `flea`, whose hard dependency on `omarchy`
collides with `PKG_DENY`.

## Decision

**Omarchy's four-place model, one place per precedence level.**

1. **Vendor `mimeapps.list`** at `$PREFIX/share/applications/mimeapps.list`
   (installed by `install.sh`, removed by its uninstall). This is the lowest
   XDG precedence, so the user's `~/.config/mimeapps.list` always wins — yet it
   sits *above* `/usr/share`, which is where a migrated machine still has
   `omarchy-settings`' copy. Coverage: `inode/directory` → `yazi.desktop`, 17
   image types → `imv.desktop`, `application/pdf` → `org.gnome.Papers.desktop`,
   15 video types + `application/ogg` → `mpv.desktop`, 17 text/source types →
   `nvim.desktop`, http/https → `helium.desktop` (the browser the shell layer
   installs, plan 070; the first draft named `firefox.desktop`, which no layer
   installs). `nvim.desktop` is the one id no default layer provides: neovim is
   in the catalogue. The MIME *coverage* is
   Omarchy's proven list, with two deliberate deltas: the image block is widened
   to everything `imv` declares, and Omarchy's `mailto=HEY.desktop` is dropped
   (it is the owner's paid web app, not a desktop default).
2. **Vendor `hyprland-xdg-terminals.list`** at
   `$PREFIX/share/xdg-terminal-exec/`, because `xdg-terminal-exec` is how a
   `Terminal=true` entry (yazi, nvim) actually opens.
3. **A one-shot seed** of `~/.config/xdg-terminals.list` from the chosen
   `$TERMINAL` (`share/haseen/seeds/50-handlers.sh`).
4. **`haseen setup default <files|image|video|pdf|text>`**, each kind owning a
   MIME set and writing the user's `~/.config/mimeapps.list` through one
   `xdg-mime default` call. `browser|terminal|editor|agent` behave exactly as
   before; `terminal` additionally rewrites `~/.config/xdg-terminals.list`, and
   `editor` additionally claims the `text/*` set when its `.desktop` exists.

**Catalogue**: 8 → 13 categories (`files`, `media`, `document`, `utility`,
`mobile` added), 68 → 96 entries. Every `ref` was verified with `pacman -Si`,
and every `.desktop` id was read out of the package, not guessed.

**The flea guard is the narrowest thing that works.** `pacman -Si flea` →
`Depends On: … omarchy …`, and `omarchy` pulls `omarchy-settings=4.0.4`, sddm,
limine and snapper. `PKG_DENY` is **untouched**, so `haseen install package
omarchy` is still refused (ADR 0001); only a catalogue entry declaring
`"pullsOmarchy": true` prints the recorded dependency closure *and* the
`omarchy-settings` files that collide with haseen subsystems —
`/etc/fonts/conf.d/50-omarchy.conf` (plan 047), `/etc/limine-entry-tool.d/omarchy-*.conf`
(plan 002), `/etc/mkinitcpio.conf.d/omarchy_hooks.conf` (plan 033),
`/etc/sddm.conf.d/*` (haseen uses greetd) — and asks for confirmation.

## Rejected

- **Installing the vendor list into `/usr/share/applications`** where Omarchy
  puts it: pacman owns that path through `omarchy-settings` on a migrated
  machine, so it would be silently reverted by the next `pacman -Syu` and would
  become a real file conflict in the PKGBUILD phase.
- **Querying pacman at run time** for the omarchy closure and the collision
  list: it breaks the dry-run contract (pacman is a stubbed binary in tests and
  a privileged call in production) and the warning would be unavailable before
  `[omarchy]` is enabled. Recorded constants carry the exact command and date.
- **Relaxing `PKG_DENY`**: it would also let `haseen install package omarchy`
  through. pacman pulls dependencies without any help; the only thing missing
  was informed consent at the catalogue layer.
- **`"source": "pacman"` with ref `omarchy/flea`**: the ref regex forbids a
  slash and it would hard-code a repo that may not be enabled. `"source": "aur"`
  routes through `pkg_install_aur`, which picks `[omarchy]` when enabled —
  verified hermetically to resolve to `pacman -S --needed omarchy/flea`, never
  paru.
- **Making `inode/directory` open flea**: it drags the whole omarchy chain in,
  so it cannot be the default-install handler. `yazi` is in `extra`, has no such
  dependency, and ships `Terminal=true` — which is exactly what makes
  `xdg-terminal-exec` part of the model rather than an accessory.
- **Sharing the terminal name→`.desktop` map in a new lib file**: a sourced
  fragment under `default/` would blur the "defaults, not code" rule. Both
  copies carry the four-row map and a test asserts they are identical, so drift
  fails the suite.

## Verification

- `tests/test-handlers.sh` (70, new) and `tests/test-catalog.sh` (156) →
  301/301 on the owned tests, 583/583 across the affected set.
- Scratch-`HOME` runs of `haseen seed user`, `haseen setup default image`,
  `… pdf papers --dry-run`, `… files`, `… terminal`, `install.sh --dry-run`
  (planning both vendor files) and `haseen install app flea --dry-run`
  (printing the closure and the collision list before asking).
- `pacman -Si` output recorded for all 32 new refs; `.desktop` ids extracted
  from the packages themselves.

## Open

- `catalog: dev toolchains use mise or docker` could not survive `gh`,
  `lazygit`, `tmux` and `herdr` joining `development`; it was replaced with two
  sharper invariants (a versioned `tool@version` ref must be a mise entry; a
  `container` entry must be run by the docker package).
- `haseen install dev <name>` now also resolves `gh`/`lazygit`/`lazydocker`/
  `tmux`/`herdr`, because it searches the `development` category.
- The menu picks the five new categories up automatically (the catalog-install
  provider builds submenus from `.categories`); no `menu.jsonc` row was added
  for the new `setup default` kinds.

## Execution record

`share/haseen/default/applications/mimeapps.list`,
`share/haseen/default/xdg-terminal-exec/hyprland-xdg-terminals.list`,
`share/haseen/seeds/50-handlers.sh`, `bin/haseen-setup-default`, `install.sh`,
`share/haseen/default/catalog.json`, `share/haseen/lib/catalog.sh`,
`share/haseen/layers/desktop/packages.txt`, `tests/test-handlers.sh`,
`tests/test-catalog.sh`.

## Landing 2026-10-08

- Owner decisions: flea keeps its confirm prompt, and the `PKG_DENY` exception
  is written down in `AGENTS.md` and in the entry's `note` field (D5). The
  handler apps (`yazi`, `imv`, `mpv`, `papers`, `xdg-terminal-exec`) are
  approved as desktop-layer defaults (D6).
- Aether's two vendor entries are not in `VENDOR_FILES`: plan 053 was dropped
  (owner, 2026-10-08; main's plan 067 had already dropped Aether).
- `bin/haseen-setup-default` had two `desktop_installed` definitions after
  main's browser rows (plan 068) met this plan's; the later one read the
  host's `/usr/share`, so `tests/test-handlers.sh` failed on a machine with
  flea installed. One function now reads `XDG_DATA_DIRS` when set and the
  sysroot otherwise, and `tests/lib.sh` `sandbox()` unsets `XDG_DATA_DIRS`.
- Count on landing: main had 78 entries by then (plans 058–085 added some), so
  the catalogue holds 110: these rows, plan 038's six command-line tools, and
  `yt-dlp` in `media`.

