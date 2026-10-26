# Plan 125: The app launcher opens where the menu does

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. One manifest default; the panel, its rows and its keys do
  not move.
- **Depends on**: 122
- **Category**: shell
- **Planned at**: 2026-10-26
- **State**: DONE 2026-10-26 (owner, "the super + D menu still in the sky move
  down to match super + space").

## Why

Plan 122 made the launcher's card the menu's size. Its *place* still differed:
`haseen.menu` opens in overlay mode and centres its card,
`centeredTop = max(gapsOut, (areaHeight - cardHeight) / 2)`
(`plugins/haseen.menu/Panel.qml:171-175`), while the launcher declared no
`placement`, so `PanelPlacement.place()` anchored it to the bar's edge with
`gapsOut` of margin (`PanelPlacement.js:60-63`). On a tall screen those are
hundreds of pixels apart: SUPER + D opened "in the sky" and SUPER + SPACE in
the middle.

## What changed

- `haseen.launcher`'s manifest declares `placement`, default **`center`**.
  `PanelPlacement.place()` returns no anchors for it
  (`PanelPlacement.js:52-53`), so the compositor centres the card on the
  screen — the same middle the menu's formula computes.
- `"bar"` stays available as the old behaviour (a panel under the bar) for
  anyone who preferred it; no other value is documented.

## Evidence

- `tests/test-surfaces.sh` asserts the launcher's default is `center` and the
  menu's is still `overlay` (`tests/test-surfaces.sh:130-135`).
- `PanelPlacement.js` already had the `center` branch and its headless suite
  (`tests/test-panel-placement.sh`) covers it; this plan only points the
  launcher at it.

## Rejected options

- **Forcing the launcher into overlay mode**: overlay means the host draws no
  `PanelSurface`; the launcher would have to draw its own card and scrim, for
  a position it can get from the compositor.
- **A fixed top margin**: it must follow the card's height and the screen's,
  exactly as the menu's formula does.
- **Moving the menu down to the launcher**: the owner named the menu as the
  reference ("move down to match super + space").
