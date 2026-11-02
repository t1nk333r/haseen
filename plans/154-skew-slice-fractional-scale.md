# Plan 154: The carousel's slices keep their whole picture at a fractional scale

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One widget changes, `SkewSlice.qml`, and only on the
  software renderer: there its layer is rendered unflipped and its content
  flips itself. On the GPU renderer it renders exactly as before (the same
  `textureMirroring` default, the same matrix).
- **Depends on**: 152 (the carousel and its slanted slice)
- **Category**: shell
- **Planned at**: 2026-11-02, from the owner's screenshot of the wallpaper
  picker on IO (below)
- **State**: DONE 2026-11-02 (`tests/test-carousel.sh` 65/65, the affected
  set 47 files 3912/3912; IO picks it up with its next update)

## Problem

The owner sent a screenshot of haseen.background open on IO, with a line
drawn under the selected card: every slice's picture stopped short of its
slanted frame, and the desktop showed through below it. Measured on the
screenshot, the selected card's frame runs from y 228 to 820 and its picture
ends at 672; the slices' frames run from 255 to 795 and their pictures end
at 660. Each picture is 0.75 of its frame's height, whatever the frame's
size.

IO renders the shell on the software renderer (`shell.qml:2`, and IO's
`haseen-shell.service` sets no `QT_QUICK_BACKEND`) on an eDP-1 panel of
1920x1080 at scale 1.25 (`hyprctl monitors` on IO, 2026-11-02). luna, at
scale 1 and on the GPU renderer, does not show it. Plan 152 tested the
slice on the software renderer at scale 1 only.

## Cause

`SkewSlice` draws its picture into a layer (`layer.enabled`), plan 152's
shader-free slant. Qt 6.12's software renderer gets that layer wrong at any
scale other than 1:

- it always draws a layer's texture flipped upside down, expecting the
  layer to have been rendered flipped
  (`qsgsoftwareinternalimagenode.cpp:463-466` at Qt `v6.12.0`:
  `(m_textureIsLayer ? -1 : 1) * (m_mirrorVertically ? -1 : 1)`);
- it renders the flipped layer through a projection rectangle multiplied by
  the scale (`qsgsoftwarelayer.cpp:204-208`), which the pixmap renderer sets
  as the painter's window (`qsgsoftwarepixmaprenderer.cpp:65`) on a pixmap
  that already carries the scale (`qsgsoftwarelayer.cpp:191-193`).

The second step puts part of the picture outside the texture. The visible
part was 1 at scale 1, 0.75 at 1.25 and nothing at 2: a plain layer, with no
transform at all, lost its bottom quarter at 1.25, and at 2 every layer was
empty while an item without a layer drew normally (probe of four variants,
2026-11-02).

## Fix

On the software renderer (`GraphicsInfo.api === GraphicsInfo.Software`),
`SkewSlice` sets `layer.textureMirroring: ShaderEffectSource.NoMirroring`,
so Qt renders the layer through the unflipped projection, which keeps the
whole picture at every scale. Its renderer still flips the texture when it
draws it, so the content inside the layer flips itself first: the inverse
shear's matrix also maps y to `height - y`. The two flips cancel, and the
picture comes out upright and whole.

On the GPU renderer nothing changes: the layer keeps Qt's default mirroring
and the matrix has no flip.

## What changed

- `share/haseen/shell/Haseen/Widgets/SkewSlice.qml`: `flipped`, the layer's
  `textureMirroring`, and the flip in the content's matrix, with the reason
  in a comment.
- `tests/test-carousel.sh`: the slice is drawn at scales 1, 1.25 and 2, with
  a yellow band along its bottom edge, and read back with ImageMagick at the
  grab's own scale. The check for shaders matches the `ShaderEffect` item
  only: `ShaderEffectSource` is the layer's texture setting, not a shader.
- `docs/architecture.md`: the pickers' line says how the slant survives a
  fractional scale.
- `plans/152-pickers-omarchy-carousel.md`: a pointer to this plan.

## Verification

- `tests/run.sh tests/test-carousel.sh`: 65/65. With `SkewSlice.qml` from
  main and the new test, 55/65: at scale 1.25 the bottom band, both stripes
  and the bottom-left corner fail; at 2 all six checks that need picture
  pixels fail (the two cut corners pass only because nothing is drawn);
  scale 1 passes, as on luna.
- The same probe on the GPU renderer (offscreen, OpenGL through Xwayland's
  GLX on luna, `QT_QUICK_BACKEND=rhi`) at scales 1, 1.25 and 2: the picture,
  both cuts, both stripes and the bottom band are where they should be.
  CI has no GL display, so this one stays a manual check.
- The real card (768x475) and slice (108x432) over a 1920x1080 wallpaper,
  drawn at scale 1.25 on the software renderer: before the fix the card lost
  its bottom quarter, as on IO.
- The affected set (`tests/run.sh --affected`, 47 files, selected by the
  `Haseen/Widgets` and plans globs): 3912/3912.

## Review

- Round 1, DeepSeek Flash on `dfc99ba`: approved, no blocker or should-fix.
  It reran the test (65/65), the mutations (main's slice 55/65, `NoMirroring`
  without the flip 50/65, the flip without `NoMirroring` 50/65), the
  affected set (47 files, 3912/3912), the GPU renderer at 1, 1.25 and 2, and
  `GraphicsInfo.api` before and after the item enters a window. Its three
  nits are taken: the content must not take input (comment and Memory),
  `magick` is required under `HASEEN_REQUIRE_ENGINE=1` as CI sets it, and
  Memory says when the workaround should go.

## Rejected options

- **Run IO's shell on the GPU renderer**, as luna does with a user drop-in:
  it hides the bug on one machine. haseen's default is the software renderer
  (`shell.qml:2`, architecture §6), and anyone at a fractional scale would
  still see it.
- **Give up the layer at a fractional scale and draw an upright card**: it
  loses Omarchy's slant, the look the owner asked for (plan 152).
- **Mirror the layer only on the GPU renderer and ignore the flip on the
  software one**: with `NoMirroring` and no flip, the software renderer draws
  the whole picture upside down (probe, 2026-11-02).
- **`NoMirroring` on both renderers**: the GPU renderer draws that upright
  too, but its default needs no workaround; the change stays on the renderer
  with the bug.
- **Grab at the stage's own size in the test** (`grabToImage(cb, size)`):
  at a fractional scale the grab is a rescaled layer with the same bug, and
  it failed with the fixed slice too. **Read the grab through a Canvas**, as
  plan 152's test did: at a fractional scale its readback did not match the
  grab either. The test reads the PNG with ImageMagick instead, as
  `tests/test-frame.sh` does, and CI installs it (`.github/workflows/ci.yml`,
  `imagemagick`).
- **Report it upstream first**: not needed to fix haseen; noted here with
  the exact lines for whoever files it.

## Memory

- Qt 6.12's software layer is wrong at any scale but 1. A test of anything
  drawn through a layer, a grab or a Canvas must run at a fractional scale
  (`QT_SCALE_FACTOR=1.25`) as well as at 1.
- The workaround leans on Qt always flipping a layer's texture on the
  software renderer. If a Qt release changes that, the slices come out
  upside down; `tests/test-carousel.sh` fails then (its stripes and bottom
  band), and the workaround should go.
- The slice's content is laid out upside down on the software renderer, so
  it must not take input: a MouseArea in it would be mirrored. The slice's
  own MouseArea, outside the layer, takes the clicks.
