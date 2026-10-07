# Plan 068: the menu, ported from Omarchy's; readable secondary text

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM (the menu is rebuilt; the data side, routes and IPC stay)
- **Depends on**: 016 049
- **Category**: shell
- **Planned at**: 2026-10-07, owner report on io ("the menu indicator is wonky", "menu refresh is janky", "the subscript of apps is not aligning to the colour scheme"), then owner decision: "make the menu exactly like Omarchy"
- **State**: DONE 2026-10-07 (`tests/test-menu-view.sh`, `tests/test-panel-placement.sh`; nested-session frame captures before/after and next to Omarchy 4's own shell in a second nest, in `~/.cache/haseen-wt/MenuPolish/shots/`)

## Problem, with evidence (nested Hyprland, theme `haseen`)

1. **Janky refresh.** The menu was a PanelPopup with placement "center": a
   layer surface sized to its content, which the compositor centres. Every row
   count change (each search keystroke, each `when` answer) resized the window,
   and Hyprland re-centred it: the card jumped up and down, and one frame per
   resize showed the old buffer stretched (frame `b-search-04`: a cut row at
   the bottom). The guard batch takes about 0.8 s on io (`bash -c "$(guardScript)"`
   timed), and the panel is destroyed on close, so every open re-ran it and
   `when` rows popped in late (`b-guard-*`: the card first drawn at a different
   size and place). The rows model was a JS array replaced on every answer,
   which rebuilt every delegate, and `settle()` kept the cursor by index, so a
   row appearing above moved the cursor to another row.
2. **Wonky indicator.** Rows took the selection on `onEntered`, so rows passing
   under a still pointer (keyboard scrolling, a narrowing search, rows landing
   late) took the cursor whenever the pointer jittered; Omarchy filters this
   with `PointerMoveGate`. The cursor row parked flush with the list edge
   (`ListView.Contain`), hiding what follows (`b-scroll-*`).
3. **Subtitle colours.** Descriptions and launcher subtitles were `Theme.muted`:
   #525252 on the panel #222222 is 1.9:1 and on the selection #864313 1.05:1 in
   `haseen` (`b-launcher-down-crop`: "Markdown Writer" invisible). Across the 23
   stock themes muted on selection is below 1.5:1 in 13.
4. **Translucent launcher in the owner's screenshot.** The `layers` animation
   (`default/hypr/looknfeel.lua:83`, fade, speed 2) caught mid-way: frames
   `b-launcher-open-*` go from translucent to opaque in about 150 ms and the
   launcher at rest is opaque. Not a colour problem; the launcher keeps its fade.

## Change

- `haseen.menu` is a port of Omarchy 4's `shell/plugins/menu/Menu.qml` on
  haseen's data (menu.jsonc and its overlay, providers, `when`/`checked`/
  `disabled`, routes, the About view, IPC `menu toggle`, the `menu` role and
  the debugIpc hooks): a 300 px card (520 for Capture › Screenrecord and Style ›
  Font) centred over a dimmed screen, no fade, "Go…"/title header that shows
  the query, Omarchy's row size, icon column, fonts and colours mapped onto
  Theme (`MenuStyle.js`), the foreground-tint cursor with accent text and no
  moving highlight, the frozen top edge and height after the first step, the
  folded list with a peeking row and scroll scrims, the search ranking with a
  divider before deeper rows, descriptions only while searching, the keys
  (Up/Down, PageUp/PageDown, Enter/Right, Left/Backspace back, Ctrl+U,
  Ctrl+Backspace, Escape clears then closes) and the pointer gate
  (`PointerGate.qml`).
- Beyond Omarchy, for the reported jank: rows update in place by itemId
  (`MenuModel.syncRows`), the cursor follows its row (`selectionAfter`,
  `selectedId`), late answers freeze only the card's top edge so rows grow
  downward, and guard answers, provider rows and the menu files are kept for
  the shell's lifetime (`MenuModel.memory`), so a reopened menu draws its final
  rows at once.
- PanelPopup placement "overlay" (`PanelPlacement.js`): every edge anchored,
  overlay layer, exclusive zones ignored, no PanelSurface chrome, namespace
  `haseen-overlay` with a `no_anim` layer rule (`default/hypr/windowrules.lua`),
  as Omarchy's `omarchy-menu` rule. The menu's `placement` defaults to it.
- Corner radius: Omarchy rounds the menu like the windows (`Style.cornerRadius`
  is `hyprctl getoption decoration:rounding`). A new shell.json token
  `windowRadius` carries the theme's window rounding (the theme's
  `hyprland.lua`, else `default/hypr/looknfeel.lua`; `_theme_window_radius` in
  theme-lib.sh), read as `Theme.windowRadius` (fallback 4); `haseen` gives 4.
- `Theme.subtle(bg)` (`Haseen/Ink.js`): secondary text is the foreground at
  Omarchy's description alpha 0.52, raised in 0.01 steps until it reads at 3:1
  on its row. Used by the menu descriptions and the launcher subtitles; in
  `haseen` the menu keeps exactly 0.52.

## Rejected

- A ListView highlight with a move animation: Omarchy has none, and an
  animated highlight lags behind a list that changes under it.
- Showing the menu only once the guard batch answered: 0.8 s on io.
- `when` showing rows until a false answer (Omarchy's rule): a "Stop
  recording" row would flash up; haseen keeps hiding until true.
- Hiding the jank by delaying layout changes: the card would still move.
- Matching Omarchy's 0.52 everywhere: four stock themes (catppuccin-latte,
  everforest, rose-pine, tokyo-night) fall below 3:1 on the selected row.
- Omarchy's Delete-to-uninstall on app rows: haseen's menu has no app removal.

## Verification

- `tests/test-menu-view.sh`: a real ListModel and ListView under the Qt engine;
  a guard answer inserting a row above the cursor keeps the cursor and every
  delegate; an unchanged answer writes nothing; descriptions and subtitles read
  at 3:1 on normal and selected rows for all 23 rendered stock themes.
- `tests/test-panel-placement.sh`: the overlay placement.
- Nested session: frame sequences before (`b-*`) and after (`a-*`), Omarchy's
  shell in a second nest at the same colours (`o-*`), side by side (`cmp-*`).
