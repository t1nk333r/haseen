# Plan 133: SUPER + O pops the window out again

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. One key gets a bind; nothing else in the layout changes, and
  the key was free.
- **Depends on**: 043 (the owner's waydots layout is the default), 093 (the
  omarchy answers haseen ships), 105 (the keys Omarchy 4.5 added)
- **Category**: keybinds, Omarchy compatibility
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26

## Problem

Owner, 2026-10-26: "super + o was a floating following key not working
anymore". Omarchy binds `SUPER + O` to its pop-out
(`default/hypr/bindings/tiling.lua:11` at v4.5.0-rc1):

```lua
o.bind("SUPER + O", "Pop window out (float & pin)", "omarchy-hyprland-window-pop")
```

— float at 1300×900, centre it, pin it and raise it, so the window stays on
top and follows across workspaces; the key again unpins and tiles it back.
That is the "floating following" the owner means.

Plan 043 made the owner's waydots layout the default, and plan 105 added the
keys Omarchy 4.5 brought. This one was not in either: haseen ships the
command (`share/haseen/omarchy/bin/omarchy-hyprland-window-pop`, one of plan
093's answers) but no key ran it. `hyprctl binds` on luna lists nothing on
`O`, and the owner's key did nothing.

## What changed

- **`share/haseen/default/hypr/binds.lua`** — `SUPER + O` runs
  `omarchy-hyprland-window-pop`, under the Windows section beside the plain
  toggle. `SUPER + T` stays toggle floating, as in Omarchy.
- **`tests/test-keybinds.sh`** — pins both actions, and the "every bound
  command exists" check now accepts a command haseen ships in
  `share/haseen/omarchy/bin` (the desktop layer puts that directory on
  `PATH`), so an Omarchy answer can be bound the way Omarchy binds it.
- The keybind sheet and the Arabic catalog carry the new description
  (`tools/i18n.py extract`, `ar/shell.json`).

Not bound: Omarchy's other tiling keys that haseen ships a command for —
`SUPER + CTRL + F` (tiled full screen), `SUPER + Home` / `SUPER + ALT + Home`
(window width), `CTRL + ALT + DELETE` (close all) and `SUPER + M` (minimize
to a dock haseen does not have). They stay free until the owner asks; the
owner's layout owns `SUPER + J`, `SUPER + L` and `SUPER + GRAVE`.

## Evidence

- `tests/test-keybinds.sh` → 125/125, including
  `SUPER + O` → `omarchy-hyprland-window-pop` and `SUPER + T` →
  `dsp.window.float({action=toggle})`.
- `hyprctl -j binds` on luna: no bind on `O` before the change.
- `omarchy-hyprland-window-pop` is on `PATH`
  (`/usr/local/share/haseen/omarchy/bin/omarchy-hyprland-window-pop`).

## Owner steps

```sh
./install.sh --yes     # luna needs your sudo
```

then `hyprctl reload` (the shell reloads the theme's binds; a new session
always has them), and SUPER + O floats, centres and pins the focused window;
press it again to tile it back.
