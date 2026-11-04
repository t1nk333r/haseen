# Plan 160: the keybind sheet shows CapsLock's shortcuts

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Without keyd running, `haseen keybinds` prints what it
  printed before. With keyd running it renames the combos of the binds
  CapsLock presses and adds up to a few rows. The sheet's card gets one
  character wider per column.
- **Depends on**: 030 (the keybind sheet), 043 (the snap layer on hyper),
  056 (keyd), 071 (readable keys and the menu's list), 109 (the catalogs)
- **Category**: shell, keybinds
- **Planned at**: 2026-11-04, owner, on IO: "add the capslock binded
  shortcuts to the keybind helper"
- **State**: DONE 2026-11-04 (`tests/test-keybinds.sh` 161/161, the
  affected set of 9 files). IO gets it with its next update.

## Problem

With keyd on (`haseen setup keyd on`), holding CapsLock sends SUPER, SHIFT,
CTRL and ALT together, tapping it sends Escape, and RightAlt + CapsLock is
the real Caps Lock (`share/haseen/default/keyd/default.conf:8-11`). The
keybind sheet (SUPER + F1) failed to show any of it in a usable way.

### The hyper binds were cut before their key

The sheet lists what `hyprctl binds -j` reports (`bin/haseen-keybinds:60`
on `a86129b`) and writes each combo as its modifiers and its key
(`:169`). On IO, `haseen keybinds --json` listed 12 binds on all four
modifiers: the 11 of the snap layer (`share/haseen/default/hypr/binds.lua:315`
onwards) and the owner's own "Paste files here (Transfers)". Their combos
were 30 to 41 characters long, from `SUPER + SHIFT + CTRL + ALT + H` to
`SUPER + SHIFT + CTRL + ALT + BRACKETRIGHT`.

The sheet's key column is too narrow for any of them. On IO's 1536-pixel
screen the card is `Theme.fontSize * 34 * columns` = 12 × 34 × 2 = 816
pixels wide (`Overlay.qml:204` on `a86129b`). Less its margins, a column is
(816 − 24 − 12) / 2 = 390 pixels, and the key column takes 42% of it,
164 pixels (`Overlay.qml:312`). Measured with `qml6` offscreen, in
JetBrainsMono Nerd Font at 12 pixels on the software renderer at scale 1
and 1.25, `SUPER + SHIFT + CTRL + ALT + H` is 215.6 pixels. So every one of
the 12 rows ended `SUPER + SHIFT + CTRL + …`, and the sheet never said which
key went with Snap left.

### keyd's own keys were not there at all

Tap for Escape and RightAlt + CapsLock are keyd's, not Hyprland's, so
`hyprctl binds -j` never reports them and the sheet had no row for them.

## Change

### `haseen keybinds` reads keyd's CapsLock

`keyd_capslock` in `bin/haseen-keybinds` reads the `[main]` lines of
`/etc/keyd/default.conf` whose left side names `capslock`, alone or in a
chord, and the layer headers such as `[hyper:C-M-A-S]`. It runs only while
keyd does: on the live machine `systemctl is-active keyd.service`, and in
a sysroot, which has no running units, an enabled `keyd.service` (a
`wants/` or `requires/` link, as `haseen setup keyd status` reads it).
`haseen setup keyd off` leaves the config in place, so the file alone is
not enough. As keyd does, the last line binding the same keys counts (a
chord's keys in any order), a layer keeps its first header (keyd's own
`control`, `shift`, `alt`, `meta` and `altgr` come before any file), and a
modifier set keyd cannot read (`[hyper:CMAS]`) holds no modifiers. Like
keyd, it skips empty fields between colons, reads a set up to the next
colon and takes a trailing dash (`[hyper::C-M-A-S-]`).

Each line becomes rows under a new section, "CapsLock":

- `overload(layer, key)` (also `overloadt`, `overloadt2` and `lettermod`,
  which take the same first two arguments): "Hold for" the layer's
  modifiers, and "Tap for" the key.
- `layer(layer)`: "Hold for" its modifiers.
- A plain key: "Press for" it.
- Anything else (a macro, a layer with no modifiers, such as `[nav]` or
  `[nav:layout]`): no description, and the keyd line as the action, which
  the sheet shows. A tab in the line becomes a space.

Key names follow the sheet's: `capslock` is CAPSLOCK, `rightalt` RIGHT ALT,
`esc` ESCAPE, and a key with modifier prefixes such as `C-S-esc` is
SHIFT+CTRL+ESCAPE. On luna, run from this branch against the shipped
config (IO's `/etc/keyd/default.conf` is the same file), the section reads:

```
CapsLock
  CAPSLOCK                        Hold for SUPER+SHIFT+CTRL+ALT
  RIGHT ALT + CAPSLOCK            Press for CAPSLOCK
  CAPSLOCK                        Tap for ESCAPE
```

The modifiers in a description are joined without spaces, so
"Hold for SUPER+SHIFT+CTRL+ALT" (29 characters) fits beside its key.

### A bind on CapsLock's modifiers reads CAPSLOCK + key

When CapsLock alone holds three or more modifiers, keyd_capslock also
prints their Hyprland modifier mask (77 for C-M-A-S), and a bind on exactly
that mask gets the combo `CAPSLOCK + key`. Its `mods` stay
`["SUPER", "SHIFT", "CTRL", "ALT"]`, the modifiers Hyprland matches. So on
luna, run from this branch:

```
Snap layer
  CAPSLOCK + J                    Snap bottom
  CAPSLOCK + APOSTROPHE           Snap bottom-left
  ...
  CAPSLOCK + BRACKETRIGHT         Snap top-right
```

Three or more, because a chord of three or four modifiers is only ever
pressed through the key that holds them all. With `capslock =
overload(control, esc)`, CTRL binds keep reading CTRL.

### The menu's list

`haseen keybinds list` (Learn › Keybindings) shows the same rows. A keyd
row has the dispatcher `keyd`, so Enter on it says "keyd remaps this key
itself: press it, the list cannot" instead of the Lua-function message
(`bin/haseen-keybinds-list:113` on `a86129b`), and dispatches nothing.

### The sheet

`Overlay.qml` translates the three descriptions as templates ("Hold for
%1", "Tap for %1", "Press for %1") and marks "CapsLock" for the catalog.
The Arabic catalog has machine translations of the four strings, worded
like its existing "Hold & drag" strings, with the key names in Latin.

The card is now `Theme.fontSize * 35 * columns`. On IO that is 840 pixels,
a 402-pixel column and a 169-pixel key column. Measured as above,
`CAPSLOCK + BRACKETRIGHT`, the longest CapsLock key at 23 characters, is
165.3 pixels and fits; at 34 it did not fit the 164 pixels. The
description column grows from 226 to 233 pixels, so no description that
fitted before is cut now.

The end-user skill (`share/haseen/agents/skills/haseen/hyprland.md`) says
the sheet names these binds CAPSLOCK + key, and no longer says the
defaults ship no hyper binds: the snap layer is on hyper.

## Rejected

- **HYPER + key.** That is keyd's name for the layer, but the key you press
  is CapsLock, and CapsLock is the owner's word for it.
- **CAPS + key.** The sheet already writes CAPS for the Lock modifier, bit
  2 of the mask (`bin/haseen-keybinds:284`). Two meanings for one word on
  one sheet.
- **Rename for one or two modifiers too.** With `capslock = layer(meta)`
  every SUPER bind would read CAPSLOCK, though SUPER is still the key most
  people press.
- **Change `mods` to `["CAPSLOCK"]`.** `mods` are Hyprland's modifiers;
  only the combo is for reading.
- **Size the key column to the longest key.** On IO the longest are
  `SUPER + XF86MonBrightnessDown` (29 characters) and
  `SUPER + SHIFT + CTRL + SPACE` (28). The column would grow to its cap,
  and descriptions of 28 to 31 characters that fit today ("Move workspace
  to right monitor", "Capture toolbar or screenshot") would be cut.
- **A 44% key column.** It fits 23 characters but cuts "Move workspace to
  right monitor" (31 characters) by a pixel.
- **Symbols for punctuation keys (`CAPSLOCK + ]`).** Shorter, but it
  changes every key name plan 071 took from Omarchy, which nobody asked
  for.
- **Read every `/etc/keyd/*.conf`.** haseen writes and checks only
  `default.conf`. Other files apply to the keyboards their `[ids]` name,
  which the sheet cannot tell apart.
- **Dispatcher `""` for keyd rows.** The list would call them Lua functions.

## Limits

Only `/etc/keyd/default.conf` is read, though keyd loads every
`/etc/keyd/*.conf`, and only its `[main]`. An `include`, the `[ids]` a
file applies to, and what other layers do with CapsLock are not followed.
A keyd action the sheet cannot name is listed by its keyd line. The sheet
names a bind CAPSLOCK only while keyd runs.

## Tests

`tests/test-keybinds.sh`, "CapsLock through keyd": a sysroot with the
shipped config and an enabled `keyd.service`. It checks:

- `CAPSLOCK + H`, `CAPSLOCK + BRACKETRIGHT`, unchanged `mods`, and a
  three-modifier bind left as it is;
- the three CapsLock rows in order, their dispatcher, action, key and mods;
- the terminal sheet and the menu's list, Enter on a keyd row, and its dry
  run;
- keyd disabled (no rows, the four modifiers back);
- a one-modifier hold (no renaming);
- a three-modifier `meh` layer (renamed);
- an action it cannot name (the keyd line);
- a layer with no modifiers (no "Hold for" row);
- the same keys bound twice, in the same and in another order, and a
  layer given two headers;
- a modifier set keyd cannot read, one after an empty field, with a
  trailing dash or before a second colon, and a built-in layer redeclared;
- a `keyd.service` linked under `requires/`;
- the live machine asking systemd and listing nothing while keyd is not
  running. With keyd running there, the test would have to read the
  host's `/etc/keyd`, so that branch is untested.

## Review

DeepSeek Flash reviewed the first head and approved it with seven nits.
Four were fixed in the second head: a layer with an empty modifier set
gave "Hold for " with nothing after it; a `requires/` link did not count as
enabled; a tab in a keyd value cut its action; and duplicate lines did not
follow keyd (the last binding wins, a layer's first modifier set wins).
Two comments said binds.lua writes the modifiers in the sheet's order; it
does not (`SUPER + SHIFT + ALT + CTRL`), so they now name the sheet. The
Limits above now say that other keyd files are not read. The seventh nit,
the untested live branch, stays as it is.

DeepSeek Flash approved the second head too, with three low findings, all
fixed in the third: a layer's first header counted only when it named
modifiers (so `[nav]` then `[nav:C]` read "Hold for CTRL", where keyd keeps
`[nav]`), and keyd's built-in modifier layers could be redeclared; a chord
written in another order (`capslock+rightalt`, then `rightalt+capslock`)
gave two rows where keyd keeps the last; and a modifier set keyd rejects,
such as `[hyper:CMAS]`, still named the hyper binds CAPSLOCK. It also
pointed out the one line here over 80 columns.

The third review approved the third head and found that its new check of
modifier sets was stricter than keyd: keyd 2.6.0 also accepts a trailing
dash and stops at a second colon (`parse_modset` and `new_layer`, checked
by the reviewer against keyd's own parser), so `[hyper:C-M-A-]` lost its
CAPSLOCK names. The fourth head accepts both.

The fourth review approved the fourth head and found one more form: keyd
skips an empty field between colons, so `[hyper::C-M-A-S]` holds all four
modifiers where the sheet read none. The fifth head skips it too.
