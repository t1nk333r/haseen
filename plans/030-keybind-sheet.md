# Plan 030: Keybind registry and cheat sheet

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (read-only; one overlay plugin)
- **Depends on**: 003 005 010
- **Category**: shell
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05

## Problem

haseen ships its bindings as Lua (`default/hypr/binds.lua`) and lets the user add
their own, with no way to see what is bound. The keys were documented only in the
file that declares them, which drifts the moment anyone rebinds anything.

## Decision

Port the model and the sheet from DankMaterialShell
(`core/internal/keybinds`, `Modals/KeybindsModal*.qml`, MIT), not the Go daemon:

- The binds come from the running compositor (`hyprctl binds -j`), not from
  parsing a config file. A bind from any Lua file, submap or plugin is listed as
  soon as Hyprland has it, which is what upstream's config parser cannot do.
- Only the category comes from the Lua sources: the `-- Section ---` comment the
  bind's description was written under, read from the default files and then the
  user's, so a user section wins. A bind no file declares is `Other`; a submap
  bind is `Submap: <name>`.
- `haseen keybinds` prints the grouped sheet in a terminal; `--json` is the
  record (`key`, `mods`, `combo`, `description`, `action`, `category`, `submap`,
  `repeat`, `locked`) the shell renders. The modifier mask is decoded to names.
- `haseen.keybinds` is an overlay plugin: a fullscreen layer surface with
  exclusive keyboard focus, type-to-search over combo, description, action and
  category, Escape or a click outside closes. `SUPER + SLASH` opens it through
  `haseen shell ipc keybinds toggle`.
- The IPC verbs are `open`/`close`/`toggle`: Quickshell's IPC listing reserves
  `show`/`hide`, and a call to those never reaches the handler.

## Verification

- `tests/test-keybinds.sh` (17): modifier decoding, combo text, categories from
  both default and user Lua, a runtime-only bind, a submap bind, the dispatcher
  fallback for a bind with no description, the terminal grouping and a
  compositor that does not answer.
- Live on the reference laptop: the overlay opened over the running session and
  listed 234 live bindings in their sections (screenshot). A bind added at
  runtime with `hyprctl eval 'hl.bind(...)'` appeared on the next open (235) and
  was the only row left when the search read `smoke`, with no shell restart. The
  bind was removed again with `hl.unbind`.

## Execution record

`bin/haseen-keybinds`, `share/haseen/shell/plugins/haseen.keybinds/`, the
`SUPER + SLASH` bind in `share/haseen/default/hypr/binds.lua`, the service entry
in `share/haseen/default/shell.json`, and `tests/test-keybinds.sh`.
