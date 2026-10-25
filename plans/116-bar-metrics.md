# Plan 116: The bar takes Omarchy's size

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. A top/bottom bar is 26 px instead of 28 and follows the
  theme's font scale; a `bar.height` in shell.json still wins.
- **Depends on**: 112, 115
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (pull request; the live bar is an owner step)

## What changed

- `Config.barHeight` falls back to `Theme.barMetrics.sizeVertical` for a
  left/right bar and `sizeHorizontal` for a top/bottom one — Omarchy's
  `[bar] size-vertical` 28 and `size-horizontal` 26, scaled by
  `[bar] scale-with-font` (`Theme.barToken`, `Theme.qml:687-703`). An explicit
  `bar.height` in shell.json still overrides it, so `haseen bar height` keeps
  working.
- `Config.barThickness` is that size, in both orientations. The old
  `Math.max(barHeight, fontSize * 3)` made a vertical bar at least 36 px wide;
  Omarchy's is 28.
- `Bar.qml`'s inner hairline is gone: Omarchy's bar is a plain surface, and the
  hairline only existed because haseen drew its own edge.

## Evidence

- `tests/test-bar-drag.sh` asserts the size comes from `Theme.barMetrics` and
  that the hairline text is gone.
- `tests/test-shell-tokens.sh` already pins the `[bar]` values and their font
  scaling.

## Rejected options

- **Keeping 28 as the default**: that is Omarchy's *vertical* bar width, not a
  horizontal bar's height.
- **Scaling from `Theme.fontSize` instead of `Theme.barToken`**: that would
  ignore `[bar] scale-with-font` and any theme that pins a size.
