# Plan 143: universal copy and paste under every layout and in panels

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Two changes in the SUPER + C/V/X block of
  `share/haseen/default/hypr/binds.lua`: the chords name keys by code, and a
  shell panel that holds the keyboard is sent the plain CTRL chord. A window
  that is not under a panel gets what it got before.
- **Depends on**: 052 (universal paste), 103 (the terminal chord)
- **Category**: desktop, keybinds
- **Planned at**: 2026-10-29, owner report on luna: "super + c and super + V
  have some issues"
- **State**: DONE 2026-10-29 (`tests/test-keybinds.sh` 127/127; both bugs
  reproduced and the fix driven in a nested Hyprland 0.56.2, see "Tests").
  Review: DeepSeek V4.1 Flash, see "Review".

## Problem

The owner did not say which issue they met. Two were found and reproduced on
Hyprland 0.56.2, the version luna runs (`hyprctl version`).

### 1. Under a second layout the chord is not sent

luna types `us,ara` with `grp:alts_toggle` (`hyprctl getoption
input:kb_layout`, `input:kb_options`). `send_key_state` turns a key name into
a code in `resolveKeycode` (`src/config/lua/bindings/LuaBindingsDispatchers.cpp`
at v0.56.2, lines 353-400). It builds an xkb state for the keyboard's
*current* layout group (`xkb_state_update_mask(..., KB->m_modifiersState.group)`)
and looks for a key whose symbol is the name. In the Arabic group no key
yields `c`, `v` or `x`, so the call fails with "key not found" and nothing
reaches the app. A found code is cached per keyboard and name
(`m_keyToCodeCache`), so the failure shows only for a keyboard that had not
sent that chord in English first. luna's main keyboard is fcitx5's virtual
keyboard (`hyprctl devices`), which is new each time fcitx5 starts.

Measured in a nested Hyprland with `kb_layout = "us,ara"`, a foot window
reading raw bytes:

| Layout | Sent | Result |
|--------|------|--------|
| English | CTRL + `V` | `^V` received |
| Arabic | CTRL + `X`, CTRL + `C` | `send_key_state: key not found`, nothing received |
| Arabic | CTRL + `code:53` | `^X` received |

`resolveKeycode` takes `code:NN` before any name lookup (same file, lines
357-358), and an xkb key code is the same key under every layout. The app
reads it in layout group 0, because `Actions::pass` sends group 0 with the
mods of every synthetic key (`src/config/shared/actions/ConfigActions.cpp`,
line 1554), so CTRL + code:54 is CTRL + C even while Arabic is active. A
physical CTRL + C under Arabic is not: in that group key 54 is
`Arabic_hamzaonwaw` (`xkbcli compile-keymap --layout us,ara`). The fix
relies on the same group reset this plan lists under "What this does not
do".

### 2. A panel over a terminal is sent the terminal's chord

`focused_is_terminal()` read `hl.get_active_window()`, which is
`Desktop::focusState()->window()` (`src/config/lua/bindings/LuaBindingsQuery.cpp`,
lines 125-134). A layer surface with the keyboard is not a window: with a
panel open over a terminal, the active window is still the terminal. In the
nested Hyprland, with a Quickshell layer `haseen-panel` holding the keyboard
exclusively over a foot window tagged `terminal`, `hl.get_active_window()`
returned the foot window and its `terminal*` tag. So SUPER + V sent
CTRL + SHIFT + V to the launcher, the clipboard panel or any other haseen
panel. A Qt `TextField` in that layer ignored CTRL + SHIFT + V and pasted on
CTRL + V; Qt's paste and copy keys on Linux are CTRL + V / SHIFT + Insert and
CTRL + C / CTRL + Insert (`QKeySequence::Paste`, `QKeySequence::Copy`).

## What changed

- `KEY_C`, `KEY_V`, `KEY_X` are `code:54`, `code:55`, `code:53` (evdev + 8),
  used by all three chords.
- `keyboard_on_panel()` walks `hl.get_layers()`. A mapped layer holds the
  keyboard when it asks for it exclusively (`interactivity` 1) on the top or
  overlay level (`layer` 2 or 3), or when it is a haseen panel
  (`haseen-panel`, `haseen-overlay`) that asks on demand (2). An exclusive
  layer keeps every window from the keyboard while it is mapped.
  `PanelPopup.qml` primes the keyboard exclusively and then holds it on
  demand, and its `HyprlandFocusGrab` keeps the keyboard in the panel and
  closes it on a click elsewhere (`share/haseen/shell/PanelPopup.qml:51-77`;
  `BarOverflowPanel.qml:120,155-163` the same, with no keyboard while it is
  held), so a mapped panel with keyboard interactivity has the keyboard. The
  nested probe's exclusive panel read `interactivity=1 layer=2 mapped=true`.
  `focused_is_terminal()` is false while one is up.
- An on-demand layer without that grab does not count: it can stay mapped
  while a window takes the keyboard, and counting it would send CTRL + C, an
  interrupt, into a terminal. That covers the desktop widgets
  (`haseen-desktop-widget`, `share/haseen/shell/Compat/DmsDesktopWindow.qml:86-88`,
  always mapped) and the compat `omarchy-keyboard-panel`
  (`share/haseen/shell/Compat/Omarchy/Ui/KeyboardPanel.qml:103,116`), which
  goes on demand after its prime and has no focus grab.

## What this does not do

- `Actions::pass` (`src/config/shared/actions/ConfigActions.cpp`, lines
  1530-1599) ends every synthetic key with `sendKeyboardMods(0, 0, 0, 0)`:
  the app is told no modifier is held, no lock is on and the layout group is
  0. The next real modifier change (releasing SUPER) sends the true state.
  If SUPER is released inside the 50 ms before the "up" half, nothing does,
  and the app keeps group 0 (English letters under Arabic) and no NumLock
  until a modifier moves. That is Hyprland's, and no Lua call sends the real
  state; it is recorded here, not worked around.
- An Omarchy plugin's panel (`omarchy-keyboard-panel`) or any other
  on-demand panel with its own namespace, open over a terminal, is still sent
  the terminal's CTRL + SHIFT chord, which its Qt fields ignore. Paste there
  needs CTRL + V by hand until such a panel takes a focus grab like
  haseen's; giving the compat KeyboardPanel one would change how every
  Omarchy plugin panel closes, which is its own change.
- Omarchy's `default/hypr/bindings/clipboard.lua` has the same two bugs as
  far as its code shows (key names, the active window's tag); nothing is
  sent upstream from here.

## Rejected options

- **Insert chords for panels too** (CTRL + Insert / SHIFT + Insert). Qt
  accepts them, but SHIFT + Insert pastes the primary selection in the
  terminals (plan 103), so the terminal case still needs its own chord.
- **Teaching the panels CTRL + SHIFT + C / V.** Every text field in every
  panel and compat plugin would need it, and third-party plugins would still
  miss it.
- **Sending down and up together, without the 50 ms timer.** It would close
  the stale-modifier window above. Omarchy split them on purpose
  (`default/hypr/bindings/clipboard.lua`, discussion 14099) and no app here
  was measured to need or not need the gap, so it stays.
- **Any layer with keyboard interactivity counts.** The always-mapped desktop
  widgets ask on demand, which would send CTRL + C into every terminal.
- **Counting the compat `omarchy-keyboard-panel` too** (round 1 of the
  review). It has no focus grab, so a window can take the keyboard while it
  stays mapped (Hyprland drops an on-demand layer from its exclusive list,
  `LayerSurface.cpp:386-387` at v0.56.2), and SUPER + C would interrupt the
  terminal.

## Tests

- `tests/test-keybinds.sh`: the chords expect `code:54/55/53`, and a new case
  presses SUPER + C/V over foot with layers in the stub: a `haseen-panel` and
  a `haseen-overlay` on demand and an exclusive overlay get CTRL; an
  `omarchy-keyboard-panel` and an unknown panel on demand, a desktop widget,
  an unmapped panel, an exclusive background layer and no layer list at all
  leave foot CTRL + SHIFT. 127/127. With the old `binds.lua` both chord
  assertions fail (125/127); with round 1's, which counted the compat panel,
  the panel assertion fails (126/127).
- Nested Hyprland 0.56.2 (Wayland backend on luna, hidden special
  workspace), `kb_layout = "us,ara"`, the clipboard block copied from this
  `binds.lua` and its functions called directly:
  - a Quickshell `haseen-panel` with a `TextField` over a foot window tagged
    `terminal`: SUPER + V pasted, English and Arabic;
  - the tagged foot alone, Arabic: SUPER + V pasted the clipboard
    (CTRL + SHIFT + V), SUPER + X sent `^X`;
  - an untagged foot, Arabic: SUPER + X, V, C sent `^X`, `^V`, `^C`.
- The live session on luna, before the change, a foot window on a silent
  special workspace addressed by window selector: CTRL + `V` and CTRL + `C`
  by name arrived as `^V` and `^C` in English, so the send path itself works
  there.

## Review

- **Round 1** (DeepSeek V4.1 Flash, 8f71b84): REQUEST_CHANGES. Should-fix:
  `omarchy-keyboard-panel` has no focus grab, so counting it could send
  CTRL + C into a terminal that took the keyboard while the panel stayed
  mapped; it no longer counts, and the gap it leaves is under "What this does
  not do". Nits, all taken: the comment and plan said the app reads the code
  as the physical chord under Arabic, but it reads it in group 0 because of
  `Actions::pass`; two line ranges in `LuaBindingsDispatchers.cpp`; the test
  gained an unknown on-demand panel and a nil layer list. The reviewer
  confirmed 127/127, the 125/127 mutation, the affected selection (19 files,
  3603/3603) and keycodes 53/54/55 for X/C/V.
