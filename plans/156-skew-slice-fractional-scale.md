# Plan 156: the carousel's slices keep their whole picture at a fractional scale

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One widget changes, `SkewSlice.qml`, and only on the
  software renderer. On the GPU renderer it keeps Qt's default texture
  mirroring and the same matrix as before.
- **Depends on**: 152 (the carousel and its slanted slice)
- **Category**: shell
- **Planned at**: 2026-11-02, from the owner's screenshot of the wallpaper
  picker on IO
- **State**: DONE 2026-11-02, merged as `f294fe5` (PR 115).
  `tests/test-carousel.sh` passed 65/65. IO gets the fix with its next
  update.

## Problem

The owner sent a screenshot of `haseen.background` open on IO, with a line
drawn under the selected card. Every slice's picture stopped short of its
slanted frame, and the desktop showed through below it. The selected
card's frame runs from y 228 to 820 and its picture ends at 672; the
slices' frames run from 255 to 795 and their pictures end at 660. Each
picture covers 0.75 of its frame's height.

IO runs the shell on the software renderer (`shell.qml:2`; IO's
`haseen-shell.service` sets no `QT_QUICK_BACKEND`). Its eDP-1 panel is
1920x1080 at scale 1.25 (`hyprctl monitors` on IO, 2026-11-02). luna runs
at scale 1 on the GPU renderer and does not show the bug. Plan 152 tested
the slice on the software renderer at scale 1 only.

## Cause

`SkewSlice` draws its picture into a layer (`layer.enabled`). That is how
plan 152 cuts the slant without a shader. Qt 6.12's software renderer draws
a layer wrong at any scale other than 1, in two steps:

1. It always draws a layer's texture upside down, because it expects the
   layer to have been rendered upside down already
   (`qsgsoftwareinternalimagenode.cpp:463-466` at Qt `v6.12.0`:
   `(m_textureIsLayer ? -1 : 1) * (m_mirrorVertically ? -1 : 1)`).
2. It renders that flipped layer through a projection rectangle multiplied
   by the scale (`qsgsoftwarelayer.cpp:204-208`). The pixmap renderer sets
   that rectangle as the painter's window
   (`qsgsoftwarepixmaprenderer.cpp:65`) on a pixmap that already includes
   the scale (`qsgsoftwarelayer.cpp:191-193`).

The second step pushes part of the picture outside the texture. A probe of
four variants on 2026-11-02 showed the whole picture at scale 1, 0.75 of it
at 1.25 and nothing at 2, even for a plain layer with no transform. An item
without a layer drew normally at every scale.

## Fix

On the software renderer (`GraphicsInfo.api === GraphicsInfo.Software`),
`SkewSlice` sets `layer.textureMirroring: ShaderEffectSource.NoMirroring`.
Qt then renders the layer through the unflipped projection, which keeps the
whole picture at every scale. Qt still flips the texture when it draws it,
so the content inside the layer flips itself first. The inverse shear's
matrix also maps y to `height - y`. The two flips cancel, and the picture
comes out upright and whole.

On the GPU renderer nothing changes. The layer keeps Qt's default mirroring,
and the matrix has no flip.

## What changed

- `share/haseen/shell/Haseen/Widgets/SkewSlice.qml` gains the `flipped`
  property, the layer's `textureMirroring` and the flip in the content's
  matrix, with a comment that gives the reason.
- `tests/test-carousel.sh` draws the slice at scales 1, 1.25 and 2, with a
  yellow band along its bottom edge, and reads the pixels with ImageMagick.
  Its shader check now matches only the `ShaderEffect` item, because
  `ShaderEffectSource` names the layer's texture setting.
- `docs/architecture.md` and plan 152 point to this fix.

## Verification

- `tests/run.sh tests/test-carousel.sh` passed 65/65. With the old
  `SkewSlice.qml` it passed 55/65. Scale 1 passed, 4 checks failed at 1.25,
  and all 6 checks that need picture pixels failed at 2. Either half of the
  fix alone passes 50/65.
- On the GPU renderer (`QT_QUICK_BACKEND=rhi`, offscreen through
  Xwayland's GLX on luna) the same probe drew correctly at scales 1, 1.25
  and 2. CI has no GL display, so this check stays manual.
- The real card (768x475) and slice (108x432) were drawn over a 1920x1080
  wallpaper at scale 1.25 on the software renderer. Before the fix the card
  lost its bottom quarter, as on IO. The slice's loss shows in the test
  above, whose bottom-band check fails at 1.25.
- `tests/run.sh --affected` selected 47 files and passed 3912/3912.

## Review

DeepSeek Flash approved four rounds with no blocking finding. It
reproduced the test, mutation, GPU-renderer and affected-set results above,
but not the real-size probe. It also confirmed that `flipped` reads
`false` outside a window and turns `true` once Qt places the slice in a
software window. Its notes made `magick` a required tool under
`HASEEN_REQUIRE_ENGINE=1`, which CI sets, and added the last two notes
below. The plan was numbered 154 until PR 114 took that number.

## Rejected options

- **Run IO's shell on the GPU renderer, as luna does with a user drop-in.**
  It hides the bug on one machine. haseen's default is the software renderer
  (`shell.qml:2`, architecture §6), so anyone at a fractional scale would
  still see it.
- **Drop the layer at a fractional scale and draw an upright card.** It
  loses Omarchy's slant, the look the owner asked for in plan 152.
- **Set `NoMirroring` on the software renderer without the flip.** The
  software renderer then draws the whole picture upside down (probe,
  2026-11-02).
- **Set `NoMirroring` on both renderers.** The GPU renderer draws that
  upright too, but it needs no workaround. The change stays on the renderer
  with the bug.
- **Grab at the stage's own size in the test, `grabToImage(cb, size)`.**
  At a fractional scale it goes through a rescaled layer with the same bug,
  and it failed with the fixed slice too.
- **Read the grab through a `Canvas`, as plan 152's test did.** At a
  fractional scale its readback did not match the grab either. The test
  uses ImageMagick, as `tests/test-frame.sh` does, and CI installs it
  (`.github/workflows/ci.yml`, package `imagemagick`).
- **Report the bug upstream first.** The fix does not depend on it. The
  Cause section names the exact lines for whoever files it.

## Notes for later changes

- Qt 6.12's software layer is wrong at any scale other than 1. A test of
  anything drawn through a layer, a grab or a Canvas must run at a
  fractional scale (`QT_SCALE_FACTOR=1.25`) as well as at 1.
- The workaround depends on Qt flipping a layer's texture on the software
  renderer. If a Qt release stops doing that, the slices come out upside
  down. `tests/test-carousel.sh` then fails on its bottom band and on the
  slant's corners, and the workaround should go. The stripes do not catch
  it, because they run the full height and survive a flip.
- On the software renderer the slice's content has flipped coordinates,
  even though its picture draws upright. A `MouseArea` in the content would
  therefore be mirrored. The slice's own `MouseArea`, outside the layer,
  takes the clicks.
