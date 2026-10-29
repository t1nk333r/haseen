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
  reproduced and the fix driven in a nested Hyprland 0.56.2, see "Tests")

## Problem

The owner did not say which issue they met. Two were found and reproduced on
Hyprland 0.56.2, the version luna runs (`hyprctl version`).

### 1. Under a second layout the chord is not sent

luna types `us,ara` with `grp:alts_toggle` (`hyprctl getoption
input:kb_layout`, `input:kb_options`). `send_key_state` turns a key name into
a code in `resolveKeycode` (`src/config/lua/bindings/LuaBindingsDispatchers.cpp`
at v0.56.2, lines 353-398). It builds an xkb state for the keyboard's
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
353-357), and an xkb key code is the same key under every layout. The app
reads that key with the mods sent, which is what the physical CTRL + C does
under Arabic.

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
  overlay level (`layer` 2 or 3), or when it is a haseen or compat panel
  (`haseen-panel`, `haseen-overlay`, `omarchy-keyboard-panel`) that asks on
  demand (2). `PanelPopup.qml` primes the keyboard exclusively and then holds
  it on demand, and its `HyprlandFocusGrab` closes the panel on any click
  elsewhere (`share/haseen/shell/PanelPopup.qml:51-77`), so a mapped panel has
  the keyboard. The nested probe's exclusive panel read `interactivity=1
  layer=2 mapped=true`. `focused_is_terminal()` is false while one is up.
- A desktop widget (`haseen-desktop-widget`, on demand,
  `share/haseen/shell/Compat/DmsDesktopWindow.qml:86-88`) stays mapped all
  the time and does not count, or every terminal would be sent CTRL + C.

## What this does not do

- `Actions::pass` (`src/config/shared/actions/ConfigActions.cpp`, lines
  1530-1599) ends every synthetic key with `sendKeyboardMods(0, 0, 0, 0)`:
  the app is told no modifier is held, no lock is on and the layout group is
  0. The next real modifier change (releasing SUPER) sends the true state.
  If SUPER is released inside the 50 ms before the "up" half, nothing does,
  and the app keeps group 0 (English letters under Arabic) and no NumLock
  until a modifier moves. That is Hyprland's, and no Lua call sends the real
  state; it is recorded here, not worked around.
- Omarchy's `default/hypr/bindings/clipboard.lua` has both bugs; nothing is
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

## Tests

- `tests/test-keybinds.sh`: the chords expect `code:54/55/53`, and a new case
  presses SUPER + C/V over foot with layers in the stub: a `haseen-panel`, a
  `haseen-overlay` and an `omarchy-keyboard-panel` on demand, and an exclusive
  overlay get CTRL; a desktop widget on demand, an unmapped panel and an
  exclusive background layer leave foot CTRL + SHIFT. 127/127. With the old
  `binds.lua` both chord assertions fail (125/127).
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
