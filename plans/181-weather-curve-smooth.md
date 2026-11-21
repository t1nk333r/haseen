# Plan 181: a smooth temperature curve on every renderer

## Status

- **Priority**: P2
- **Effort**: XS
- **Risk**: LOW. The curve's path and how the panel asks Qt to draw it;
  the points and labels stay where they were.
- **Depends on**: 180 (the curve tab)
- **Category**: shell
- **Planned at**: 2026-11-21, from the owner
- **State**: DONE 2026-11-21 (`tests/test-weather.sh` 113/113; the curve
  rendered on the GPU scene graph and on the software renderer at 1.25)

## Problem

The owner, 2026-11-21, after plan 180 reached luna: "the curve is not
smooth".

luna's shell runs on the GPU scene graph (`QT_QUICK_BACKEND=rhi` from a
user drop-in, for a blur plugin). Plan 180's renders used the software
renderer, which antialiases a `Shape`. Rendered on the GPU path the way
luna draws it (`DISPLAY=:0 QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl
QT_QPA_PLATFORM=offscreen`), the line was stair-stepped: the `Shape` in
`share/haseen/shell/plugins/haseen.weather/Panel.qml` (origin/main at
`7ed2928`) left `preferredRendererType` at its default, whose GPU geometry
has no antialiasing. The approved mockup had set `Shape.CurveRenderer`.
The real panel had dropped it.

The path itself could also kink. Plan 180's review clamped each
Catmull-Rom control point to the curve's band separately (`Model.curve`),
so near a peak the incoming and outgoing tangents could stop being
collinear, which shows as a corner.

## Decision

- The `Shape` sets `preferredRendererType: Shape.CurveRenderer`:
  antialiased curves on the GPU scene graph. The software renderer, which
  IO runs, antialiases anyway.
- `Model.curve` draws a monotone cubic (Fritsch and Carlson, 1980) as
  cubic Béziers:
  - each point has one tangent: the mean of its two secants, zero at a
    peak or trough, scaled down where it would overshoot;
  - the control points sit a third of each segment along those tangents,
    rounded to 0.01 px so the tangents stay continuous.

  The line therefore turns smoothly through every point and stays between
  each segment's two points, so it never leaves the band and needs no
  clamp. The points, the labels and the area fill are unchanged.

## Rejected

- **Keeping Catmull-Rom without the clamp**: smooth, but it overshoots
  above the warmest point into the labels' room (plan 180's review,
  finding 9).
- **Antialiasing through `layer.samples`**: a multisampled layer per panel
  costs memory, and layers draw wrong on IO's software renderer at 1.25
  (plan 156).

## Verification

- `tests/test-weather.sh` 113/113. Two new Model units: at every inner
  point of a six-point wave, the incoming control point, the point and
  the outgoing control point are collinear, and the tangent is flat at a
  peak. A source check covers `Shape.CurveRenderer`. The band check from
  plan 180 still passes.
- Rendered with live data for the owner's city, scratch harness, not
  committed:
  - on the GPU scene graph as above: stair-stepped before, smooth and
    antialiased after;
  - on the software renderer at `QT_SCALE_FACTOR=1.25` (IO): smooth.
