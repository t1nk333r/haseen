# Plan 123: No dim behind the menus

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. One full-screen rectangle goes; the click-catcher, Escape and
  the card stay.
- **Depends on**: 117, 122
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (owner, "no background black highlight on both").

## Why

`haseen.menu` drew a full-screen scrim — the background at 0.5 alpha — whenever
it opened as an overlay (`Panel.qml:1068-1072`, `MenuStyle.SCRIM = 0.5`). The
app launcher on SUPER + D never dims, so moving from one to the other washed
the desktop dark and back. The owner asked for no background highlight on
either.

Omarchy's menu dims, so this is a deliberate departure from it: the two haseen
launchers now look alike over the desktop.

## What changed

- `haseen.menu/Panel.qml`: the scrim `Rectangle` and its `scrim` property are
  gone. The full-screen `MouseArea` that closes the menu on a click outside
  stays.
- `haseen.menu/MenuStyle.js`: `SCRIM` and its mention in the header comment
  are gone. The list's edge fades (the "scroll scrims" inside the card) are
  gradients that mask cut-off rows, not a dim, and stay.

## Evidence

- `tests/test-surfaces.sh` -> 114/114, with three new assertions: the menu
  paints no `root.scrim`, `MenuStyle.js` keeps no `SCRIM`, and the launcher
  paints no scrim either.
- `grep -rn 'scrim' plugins/haseen.menu/` -> only the in-card scroll fades.

## Rejected options

- **A `scrim` setting, off by default**: nothing else in the shell dims the
  screen behind a popup, and the owner asked for none; a setting would be one
  more thing to explain.
- **Dimming the app launcher instead, to match the menu**: that is the
  opposite of what was asked.
