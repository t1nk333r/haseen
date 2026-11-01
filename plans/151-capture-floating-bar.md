# Plan 151: the capture toolbar is a floating bar

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. The plugin is off by default and changes only its own
  files. The overlay placement and its window are the ones the menu already
  uses (`share/haseen/shell/PanelPopup.qml:14-19`).
- **Depends on**: 150 (haseen.capture), 115 (Omarchy's controls and Theme)
- **Category**: shell, plugins
- **Planned at**: 2026-11-01, owner, on seeing plan 150's toolbar: "i like
  the original look of it the floating bar but themeable"
- **State**: DONE 2026-11-01 (`tests/test-capture-toolbar.sh` 56/56; the live
  toolbar is an owner step)

## Problem

Plan 150 drew haseen.capture as a panel card under the bar, with a labelled
button per choice and one row per setting. The owner preferred the look of
the DMS toolbar they had used, a floating bar near the bottom of the screen,
drawn in the theme. That plugin has no license (plan 052), so its look can be
followed but none of its code taken; this is written from its screenshots.

## What changed

- **`share/haseen/shell/plugins/haseen.capture/Panel.qml`** is a floating
  bar. Its `placement` setting defaults to `overlay`, so the panel gets the
  whole screen, as the menu does (`PanelPopup.qml:14-19`). The panel lays
  out, near the bottom and clear of a bottom bar:
  - **the bar**: round icon buttons for the modes, then what the mode
    captures (for sound, its two sources), then the capture button in the
    accent's circle, the options gear and close, with dividers between the
    groups;
  - **the options card**, opened by the gear or the controller's Y, above
    the bar with a nub pointing at the gear. It holds the mode's options: a
    screenshot's delay and the "Open in the editor" switch, a video's sound
    switches and delay, a sound's format;
  - **the hint** under the bar: the name of the control under the cursor
    (haseen draws no tooltips), the keys, the controller count and any
    warning.

  A click anywhere else closes the toolbar. Escape and B close the card
  first, then the toolbar. The `center` and `bar` placements show the same
  bar inside a panel card.
- **Theme**: every colour is a Theme token: `popups` for the bar, card and
  hint, `accent` for the capture button, `urgent` for the recording dot, and
  the control states through `PanelButton` and `PanelSwitch`. The text is in
  the theme's font. A new `shape` setting picks `pill` (the default: fully
  rounded, as the original) or `theme` (the theme's corners). Right-to-left
  languages mirror the bar and keep the card over the gear.
- **`Model.js`**:
  - The cursor's rows are now one bar row, with the card's rows above it
    while the card is open.
  - `label()` names each icon button.
  - Screenshots gain an `edit` state, with a matching `edit` setting, that
    opens the editor every time; Ctrl+Space still does it for one capture.
  - The glyphs are Nerd Font Material Design codepoints, checked against the
    installed `SymbolsNerdFont-Regular.ttf`'s glyph names. Two examples:
    `md-monitor_multiple` for all screens and `md-waveform` for sound, so the
    sound mode no longer shares the microphone's glyph.
- **`PillWindow.qml`**: the recording pill takes the same shape: a red dot,
  the elapsed time in the theme's monospace, a waveform or video glyph, and a
  square stop button.
- **i18n**: "Options", "Format", "Open in the editor" and "Close" in English
  and Arabic. The panel's old "Edit", "Recording sound" and "Recording the
  screen" left both catalogs.

## Verification

- `tests/test-capture-toolbar.sh` 56/56. The Model cases are 47, up from 41:
  - the bar row and each mode's card rows;
  - moving between the card and the bar;
  - labels;
  - the editor switch;
  - Y.

  The engine probe opens the card with Y, moves up from Capture into it,
  picks 5 s, switches to a video of a window, and checks that B closes the
  card and puts the cursor back on Capture before the capture is queued.
- `tests/run.sh --affected`: 60 files, 5298/5298 passed. The i18n catalogs
  widen the selection.
- `tools/lint.sh` lint OK (qmllint, i18n, coverage). `tools/check-docs.sh`
  OK.
- Rendered offscreen over the owner's wallpaper and theme in each mode, with
  the card open and closed, while recording, mirrored for right to left, and
  with `shape: theme`.

## Rejected options

- **Copy the original's QML.** It has no license; only its look is followed.
- **A frosted-glass background like the original's.** Blur is not allowed
  (architecture §6). The bar uses the theme's `popups` colours and alpha
  instead.
- **Tooltips on the icon buttons.** haseen's panels show hints in their own
  text, not in tooltips (`PanelButton.qml:1-4`). The hint pill names the
  control under the cursor, which also serves the keyboard and the
  controller.
- **The original's clipboard, save, pointer, notification and directory
  switches.** How a capture is saved and shown is `haseen capture`'s to
  decide (Omasnap, plan 107); a second set of switches here could disagree
  with it.
- **Keep the labelled panel as the default and add the bar as an option.**
  The owner asked for the bar. The other placements stay as settings.
