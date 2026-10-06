# Plan 051: io, fifth round — tray hover, arrange and drag, bar edge, double-click, hidden widgets, calculator

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM (every pointer path on the bar)
- **Depends on**: 050
- **Category**: shell
- **Planned at**: 2026-10-06, owner requests while using io
- **State**: DONE 2026-10-06 (touchpad double-tap and physical drags on io are owner checks)

## Problem and decision

- **Tray**: opens on hover, closes 400 ms after the pointer leaves (marked
  single-shot timer), a chevron click pins it. Logic in `haseen.tray/Drawer.js`,
  unit-tested; an open item menu holds it open.
- **Hidden widgets took room and hover**: `t1nk33r.updates` hides with
  `visible: false` but keeps its implicitWidth, and the compat hosts passed it
  on. Slots now size only visible widgets; OmarchyHost/DmsHost report 0 for an
  invisible widget (as Omarchy's layout does).
- **Double-click**: worked only on empty space, of which io's bar has little.
  A passive PointHandler over the whole bar toggles transparency on two quick
  presses anywhere except the chevron and arrange mode (Omarchy toggles on
  modules too, `Bar.qml:1707`). A TapHandler was rejected: it stole widget clicks.
- **Moving the bar**: `haseen bar position` and Style › Bar › Position always
  worked; the owner never found them. Arrange mode (right-click empty bar
  space, Style › Bar › Arrange widgets, `haseen bar arrange`) now shows the four
  edges as buttons. Dragging the bar itself was rejected: it competes with
  double-click and right-click on the same little empty space.
- **Drag to reorder**, in arrange mode only (outside it every press belongs to
  the widget): within and between sections, onto the chevron (overflow) and out
  of the panel (pinned). Saved by `haseen bar move` through the shell.json
  helper. The tray never moves and nothing lands before it.
- **Calculator**: `haseen.calculator`, a launcher provider on `=`. A
  recursive-descent parser (no eval), Enter copies with wl-copy.

## Verification

`test-bar-overflow.sh` (move/dropTarget/panelTarget, `bar move`, `bar arrange`),
`test-frame.sh` (Drawer.js), `test-calculator.sh` (26 units incl. refusing
`constructor.constructor`). Nested Hyprland: tray states, hidden-widget hover
scan, double-click toggles, edge buttons, drags with the saved shell.json
checked after each, `=12*(3+4) + 10%` → 92.4 copied.
