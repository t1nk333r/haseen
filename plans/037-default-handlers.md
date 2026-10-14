# Plan 037: Default handlers (four places) and the catalogue's missing half

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (one guarded path can pull the `omarchy` package onto a haseen machine, by owner decision)
- **Depends on**: 003 017 023 024
- **Category**: desktop
- **Planned at**: 2026-10-05, owner request (items 1–5, 8, 24–26 and the ranked gaps 2 and 3)
- **State**: DONE 2026-10-05; amended 2026-10-13 (handlers without xdg-terminal-exec, closure guard for every install)

## Problem

haseen conflated *installable* with *default*. `share/haseen/default/catalog.json`
was an install menu of 68 entries across 8 categories, and the only handler
wiring was `export TERMINAL=foot` (`share/haseen/layers/desktop/layer.sh`). A
GTK app asked to open a folder, an image or a terminal fell through to whatever
`/usr/share` still carried from Omarchy. The catalogue had no file manager,
image viewer, video player or PDF reader, and no way to install `flea`, whose
hard dependency on `omarchy` collides with `PKG_DENY`.

## Decision

**Omarchy's four-place model, one place per precedence level.**

1. **Vendor `mimeapps.list`** at `$PREFIX/share/applications/mimeapps.list`
   (installed by `install.sh`, removed by its uninstall). It is the lowest XDG
   precedence, so the user's `~/.config/mimeapps.list` always wins, and it
   sits *above* `/usr/share`, where a migrated machine still has
   `omarchy-settings`' copy. Coverage: `inode/directory` →
   `haseen-yazi.desktop`, 17 image types → `imv.desktop`, `application/pdf` →
   `org.gnome.Papers.desktop`, 15 video types + `application/ogg` →
   `mpv.desktop`, 17 text/source types → `haseen-nvim.desktop`, http/https →
   `helium.desktop` (the browser the shell layer installs, plan 070). neovim
   is the one program no default layer installs; it is in the catalogue. The
   MIME coverage is Omarchy's list with two deltas: the image block is widened
   to everything `imv` declares, and `mailto=HEY.desktop` is dropped (a paid
   web app, not a desktop default).
2. **haseen's own entries for the two terminal programs**,
   `share/haseen/default/applications/haseen-{yazi,nvim}.desktop`:
   `Terminal=false`, `Exec=haseen-terminal-run yazi %u` (`nvim %F`), and
   `TryExec` so they are hidden while the program is missing. The packaged
   `yazi.desktop` and `nvim.desktop` are `Terminal=true`, which GLib starts
   only through `xdg-terminal-exec` or a terminal on its built-in list, and
   foot is not on it (`strings /usr/lib/libgio-2.0.so.0`, glib2 2.88.3-1:
   xdg-terminal-exec, ghostty, gnome-terminal, mate-terminal, xfce4-terminal,
   tilix, konsole, nxterm, color-xterm, rxvt, dtterm). `xdg-terminal-exec`
   comes only from `[omarchy]` (`pacman -Si` against copies of this machine's
   sync databases, 2026-10-13: `omarchy/xdg-terminal-exec 0.14.3-1`, in no
   other repo), and the desktop layer does not require `omarchy-repo`, so
   without it "open folder" could not launch. `bin/haseen-terminal-run` runs
   the program in `$TERMINAL` (foot when unset or missing) with `-e`, or
   hands it to an `xdg-terminal-exec` `$TERMINAL` as is.
3. **Vendor `hyprland-xdg-terminals.list`** at
   `$PREFIX/share/xdg-terminal-exec/`: when `xdg-terminal-exec` is installed,
   it is how GTK's "Open in Terminal", flea and any other `Terminal=true`
   entry open a terminal.
4. **A one-shot seed** of `~/.config/xdg-terminals.list` from the chosen
   `$TERMINAL` (`share/haseen/seeds/50-handlers.sh`), and
   **`haseen setup default <files|image|video|pdf|text>`**, each kind owning
   a MIME set and writing the user's `~/.config/mimeapps.list` through one
   `xdg-mime default` call. A kind's map lists candidate ids best first and
   takes the first one installed (`yazi`: `haseen-yazi.desktop`, then
   `yazi.desktop`); an entry whose `TryExec` program is missing counts as not
   installed, as it does for GLib. `terminal` also rewrites
   `~/.config/xdg-terminals.list`, and `editor` also claims the `text/*` set
   when its entry is installed.

**Catalogue**: 8 → 13 categories (`files`, `media`, `document`, `utility`,
`mobile`), 110 entries. Every `ref` was verified with `pacman -Si`, and every
`.desktop` id was read out of the package.

**The `[omarchy]` dependency guard.** `PKG_DENY` refuses `omarchy` and
`omarchy-settings` as targets (ADR 0001), but pacman pulls them in as
dependencies: `flea`, `learn-omarchy` and `elsewhen` in `[omarchy]` all
depend on `omarchy` (`pacman -Si`, copied sync databases, 2026-10-13). Before
every pacman install, `pkg_guard_closure` (`share/haseen/lib/packages.sh`)
resolves the closure with `pacman -Sp --print-format %n`, which needs no root
and no network (run as a normal user against the copied databases: it printed
the closure, and exited 1 with `target not found` for an unknown name). When
the closure holds a `PKG_DENY` package it prints the closure, the
`omarchy-settings` files that land on haseen subsystems (`pacman -Ql
omarchy-settings`, 4.0.4-1, read 2026-10-05: fontconfig, Limine entries
(plan 002), mkinitcpio HOOKS (plan 033), sddm, fcitx, mimeapps.list, the
terminal list) and what removal does (`haseen remove` runs `pacman -Rns`,
which takes them out again unless another package needs them), then asks.
`--yes` answers only for packages of a catalogue entry marked
`"pullsOmarchy": true`, and refuses for any other. Under a sysroot,
`var/lib/pacman/sync/NAME.deps` stands in for `pacman -Sp`.

## Owner decisions

- flea may pull `omarchy` and `omarchy-settings` in after the closure is
  printed and the question asked; it is the only `pullsOmarchy` entry, and
  the exception is written in `AGENTS.md` and the entry's `note` (owner,
  2026-10-05; confirmed 2026-10-08 and 2026-10-13).
- `yazi`, `imv`, `mpv`, `papers` and `xdg-terminal-exec` are desktop-layer
  defaults (owner, 2026-10-08; confirmed 2026-10-13). `xdg-terminal-exec`
  comes only from `[omarchy]` (owner, 2026-10-08, plan 024).
- Aether's two vendor entries are not shipped: plan 053 was dropped (owner,
  2026-10-08; plan 067 had already dropped Aether).

## Rejected

- **Installing the vendor list into `/usr/share/applications`** where Omarchy
  puts it: pacman owns that path through `omarchy-settings` on a migrated
  machine, so the next `pacman -Syu` would revert it and a PKGBUILD would hit
  a file conflict.
- **Shipping the yazi association only when `xdg-terminal-exec` is
  installed**: the vendor list is one static file `install.sh` copies; it
  would have to be rewritten whenever `omarchy-repo` is applied later or the
  package is removed, and the text block needs the same treatment.
- **Overriding `yazi.desktop` with a same-id entry under `$PREFIX/share`**: it
  would replace the package's own entry in every launcher and drift from it.
- **An inline `sh -c '"$TERMINAL" -e yazi'` Exec line**: GLib and xdg-open
  parse Exec quoting differently; a command is one argv for both.
- **A recorded closure constant for flea** (the first version): it went stale
  with each omarchy release and covered only catalogue entries marked
  `pullsOmarchy`, so `haseen install package learn-omarchy --yes` pulled
  omarchy in silently. It was chosen because querying pacman was thought to
  be privileged; `pacman -Sp` is not.
- **Relaxing `PKG_DENY`**: it would let `haseen install package omarchy`
  through.
- **`"source": "pacman"` with ref `omarchy/flea`**: the ref regex forbids a
  slash and it would hard-code a repo that may not be enabled. `"source":
  "aur"` goes through `pkg_install_aur`, which picks `[omarchy]` when enabled
  (`pacman -S --needed omarchy/flea`, never paru).
- **Making `inode/directory` open flea**: it drags the omarchy chain in, so it
  cannot be the default handler. `yazi` is in `extra` with no such
  dependency.
- **Sharing the terminal name→`.desktop` map in a new lib file**: a sourced
  fragment under `default/` would blur "defaults, not code". Both copies
  carry the four-row map and `tests/test-handlers.sh` asserts they are equal.

## Verification

- `tests/test-handlers.sh`: the vendor blocks equal the `setup default` MIME
  sets; no vendor default is a packaged `Terminal=true` entry; each haseen
  entry is `Terminal=false`, runs `haseen-terminal-run`, carries `TryExec`
  and declares the MIME types it is given; the launcher's terminal choice;
  `TryExec` in `desktop_installed`; the seed with `$TERMINAL` unset writes
  nothing to stderr. On the code before 2026-10-13, 13 of these fail before
  the file aborts on the missing launcher.
- `tests/test-catalog.sh`: flea's closure, collisions, removal text and
  `pacman -S --needed omarchy/flea`; `learn-omarchy`, `elsewhen` and a mixed
  `flea learn-omarchy` refused under `--yes` (dry run included) and asked
  without it; a clean closure asks nothing. 20 of these checks fail on the
  code before 2026-10-13.
- `desktop-file-validate` passes on both haseen entries.

## Open

- An AUR build's dependencies are not resolved before the build: there is no
  offline, unprivileged resolver for the AUR. paru lists them and asks,
  except under `--yes`.
- `haseen install dev <name>` also resolves the `development` CLI tools
  (`gh`, `lazygit`, `lazydocker`, `tmux`, `herdr`), because it searches that
  category.

## Execution record

`share/haseen/default/applications/{mimeapps.list,haseen-yazi.desktop,haseen-nvim.desktop}`,
`share/haseen/default/xdg-terminal-exec/hyprland-xdg-terminals.list`,
`share/haseen/seeds/50-handlers.sh`, `bin/haseen-setup-default`,
`bin/haseen-terminal-run`, `install.sh`, `share/haseen/default/catalog.json`,
`share/haseen/lib/{catalog,packages}.sh`,
`share/haseen/layers/desktop/packages.txt`, `tests/test-handlers.sh`,
`tests/test-catalog.sh`. `desktop_installed` reads `XDG_DATA_DIRS` when set
and the sysroot otherwise, and `tests/lib.sh` `sandbox()` unsets
`XDG_DATA_DIRS`, so a handler installed on the host never counts in a test.
