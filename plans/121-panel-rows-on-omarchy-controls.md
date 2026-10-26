# Plan 121: Panel rows use Omarchy's controls

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM. Every panel's body is touched; behaviour must not move.
- **Depends on**: 115, 117
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: PARTIAL 2026-10-26. The row chrome is converted on 11 panels
  (below); toggles, fields, the network action ring, the todoist confirm card
  and the lock's wallpaper remain.

## Why

Plan 117 gave the panels Omarchy's card (`PanelSurface`), section caption
(`PanelSectionHeader`), divider (`PanelSeparator`) and the row controls
(`PanelButton`, `PanelSwitch`, `PanelActionButton`, `PanelSlider`). The
controls are already pixel-identical ports, but almost no panel uses them:
`PanelButton` and `PanelSwitch` had no user in `share/haseen/shell/plugins/`
before this plan, and 19 panels still paint rows with `Theme.surfaceAlt` and
`Theme.selection` (a scan of `plugins/*/Panel.qml`, 2026-10-25):

| Panel | Hand-rolled fills |
| --- | --- |
| haseen.themegen | 4 |
| haseen.weather | 4 |
| haseen.browser-picker, haseen.clipboard, haseen.emoji, haseen.typist, haseen.vpn | 3 |
| haseen.agents, haseen.imagepicker, haseen.settings | 2 |
| haseen.ai, haseen.display, haseen.kblayout, haseen.media, haseen.network, haseen.sysusage, haseen.todoist | 1 |

`Theme.selection` is also the text-selection colour, so each hit is checked
before it is replaced: only row and button fills move to a control.

## Done 2026-10-26: rows paint through `CursorSurface`

`CursorSurface` (the Omarchy row chrome added by plan 115) now paints every
row that hand-rolled a hover/selection rectangle, so hover, keyboard cursor
and the current item use the theme's state fills and borders instead of
`Theme.surfaceAlt` (the hover-cursor fill) and `Theme.selection` (the
*text-selection* colour, which was never the selected row's fill):

| Panel | Row |
| --- | --- |
| haseen.audio | device row |
| haseen.clipboard | item row (text and image rows alike) |
| haseen.kblayout | layout row, keeping its `surface` rest fill |
| haseen.emoji | the grid tile (current item and hover) |
| haseen.agents | running-agent row and account row |
| haseen.bluetooth | device row |
| haseen.battery | the low-battery/setup row |
| haseen.display | the night-light row |
| haseen.browser-picker | the rule picker's row |
| haseen.typist | the entry row |
| haseen.vpn | the toggle row and the server row |

`CursorSurface` gained a `background` property for the one panel whose rows
sat on `Theme.surface` at rest (kblayout); everywhere else the rest colour is
transparent, exactly as before.

`CursorSurface` rather than `PanelButton` for these: the rows carry an icon
column and one or two text columns, and `PanelButton` centres a lone label
(submenu-style) — Omarchy's own list rows use `CursorSurface` too. No string,
command or IPC reply changed.

Still hand-rolled after this: the search/filter fields (browser-picker,
clipboard, emoji, imagepicker, settings, themegen, typist, vpn), text
selection colours (ai, launcher), the media cover placeholder, the sysusage
meter track, the weather graphs, network's action-icon hover ring and
todoist's delete-confirm card.

## What

Per panel, in this order (the panels the owner opens most first):

1. **Rows that act** (`network`'s access points, `bluetooth`'s devices,
   `browser-picker`, `imagepicker`, `emoji`, `clipboard`, `kblayout`) become
   `PanelButton` with `leftAlign`, `hasCursor` for the keyboard cursor and
   `selected` for the current item. `Theme.hoverFillFor` / `selectedFillFor`
   then paint hover, focus and selection exactly as Omarchy's panels do
   (`Ui/PanelButton.qml:66-78`).
2. **Toggles** (`settings`, `display`, `vpn`, `syncthing`, `wooting`) become
   `PanelSwitch`, keeping their labels and their state text.
3. **List rows with a subtitle** (`agents`, `todoist`, `typist`, `sysusage`,
   `themegen`) keep their own two-line delegate but paint it with
   `Theme.selectedFillFor(Theme.foreground, Theme.accent)` and
   `Theme.hoverFillFor`, and take `Theme.spacing.rowPaddingX` as side padding.
4. **Sliders** (`media`, `weather`'s rain graph stays a graph) move to
   `PanelSlider` / `TrackBar` as the bar already does.

Each panel keeps its tests; a converted panel must not change a single string,
command or IPC reply.

## Also

- **Blurred wallpaper on the lock** (deferred from 117): read the current
  background path in `haseen.lock` and draw it under a `MultiEffect` blur with
  `contrast: -0.08`, as `plugins/lock/LockView.qml:100-120` does. Needs the
  background service's path, so it is its own change.

## Evidence

- 2026-10-26, after the row pass: `grep -c 'Theme.surfaceAlt\|Theme.selection'
  plugins/*/Panel.qml` leaves only the fields, text selections, the media
  cover, the sysusage track, the weather graphs, network's action ring and
  todoist's card.
- `tests/run.sh test-audio-panel test-surfaces` 121/121;
  `test-battery test-surfaces test-adopted-tools` 406/406; qmllint clean on
  every converted file.

- `grep -c 'Theme.surfaceAlt\|Theme.selection' plugins/*/Panel.qml` — the
  table above.
- `grep -rln 'PanelButton\|PanelSwitch' share/haseen/shell/plugins/` — empty
  before this plan.
