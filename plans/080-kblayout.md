# Plan 080: keyboard-layout bar widget

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (off by default; Hyprland events only)
- **Depends on**: 079
- **Category**: shell, input
- **Planned at**: 2026-10-07, gap 6 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-keyboard.sh`; nested screenshots EN and AR)

## Change

- New built-in `haseen.kblayout` (bar-widget + panel), **off** (`default/shell.json`, in no bar section).
  `haseen plugin enable haseen.kblayout` puts it in `bar.right`; Setup › Keyboard Layout in the Bar.
- The code (EN, AR) comes from the `Keyboard` singleton (plan 079): one `hyprctl -j devices` read for the
  main keyboard's layouts and active keymap, then `activelayout` events, re-read after `configreloaded`.
- Zero width and invisible with one layout, so it can sit in `bar.right` like `haseen.gestures`.
- Left click: `hyprctl switchxkblayout main next`. `main` is Hyprland's own name for the keyboard the devices
  list marks main (`HyprCtl.cpp` switchXKBLayoutRequest), so it follows the keyboard typed on last rather
  than a name read at startup.
- Right click with more than two layouts opens the panel: one row per layout (code, xkb name, variant),
  the active one from a devices read on open; a click runs `switchxkblayout main N` and closes it.
- Names → codes: the language part of the xkb description through a table taken from evdev.xml's
  `shortDescription` (Arabic and all its variants → AR, English → EN, Persian → FA, …), else the first two
  letters; xkb layout names (`ara`, `us`, `ir`) for the list.

## Evidence

- `tests/test-keyboard.sh`: off by default and in no bar section; the mapping units; in the real engine
  with a stub `hyprctl`: us,ara shows EN then AR after an event, takes room; one layout → width 0 and
  invisible; a click logs `switchxkblayout main next`; a right click opens the list only with three layouts.

## Nested proof

`~/.cache/haseen-wt/scratch-keyboard/shots/bar-en-crop.png` (EN in the bar with us,ara) and
`switch-ar.png` (AR after a switch on the nest socket).

## Review fixes (2026-10-08)

- **One code everywhere.** `Keyboard.code` is the list entry's xkb code (`layouts[index].code`), the description's
  code only while the entry is unknown, so the bar, the list and the OSD agree (Tajik: TJ, not TA). A switch event
  places the entry by its xkb description (`Keyboard.js` `indexOf`, `XKB_NAMES` from xkeyboard-config 2.48's
  evdev.xml, MIT); a variant, a duplicate or another keyboard reads the devices once.
- **A failed or empty devices read keeps the last good one** (the widget no longer vanishes on a reload hiccup).
- **Keyboard names with a comma** ("logitech,-inc.-keyboard"): the longest known name wins in `parseLayoutEvent`.
- **The list** (design review M9): rows show code, xkb description ("Arabic") and the xkb name/variant in
  `Theme.subtle`; the cursor row has the `Theme.selection` fill, the active code is in the accent; the title is the
  accent panel title; Up/Down, j/k, Tab move and Enter picks, as in haseen.session.
- `tests/test-keyboard.sh` 44 checks; 10 of them fail on 2981fb3. No nested screenshot of the list was taken in
  this pass (run out of time); the engine test drives it.

## Not verified

- A pointer click on the widget and the layout panel in the nest (the engine test drives both).
- fcitx5 as the main keyboard (the owner's): switching its group may be overridden by fcitx.

## Rejected

- **Zero-size default-on**: needs owner approval (AGENTS.md); off until he adds it.
- **Reading evdev.xml at runtime** for names: a ~300 KB parse for two letters.
