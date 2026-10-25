# Plan 121: Panel rows use Omarchy's controls

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM. Every panel's body is touched; behaviour must not move.
- **Depends on**: 115, 117
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: PENDING. 19 panels still paint their own row fills.

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

- `grep -c 'Theme.surfaceAlt\|Theme.selection' plugins/*/Panel.qml` — the
  table above.
- `grep -rln 'PanelButton\|PanelSwitch' share/haseen/shell/plugins/` — empty
  before this plan.
