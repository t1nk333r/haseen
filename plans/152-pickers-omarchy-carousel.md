# Plan 152: the wallpaper and theme pickers are Omarchy's carousel, with no dim

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Two picker panels and two new shared widgets change; the
  CLI calls behind them (`haseen theme set`, `haseen theme bg list|current|
  set|next`) are the same argv as before. The overlay placement and its
  window are the ones the menu and the capture toolbar already use
  (`share/haseen/shell/PanelPopup.qml:14-19,26,47-52`).
- **Depends on**: 020 (themes and backgrounds), 115 (Omarchy's look and
  Theme), 123 (no dim behind the menus)
- **Category**: shell, plugins
- **Planned at**: 2026-11-01, owner: "make the wallpaper selector and theme
  selector like omarchy but without the diming"
- **State**: DONE 2026-11-02 (`tests/test-carousel.sh` 42/42, the affected
  set 74 files 6612/6612; the live pickers are an owner step)

## Problem

`haseen.background` (SUPER + CTRL + SPACE) and `haseen.themepicker`
(SUPER + CTRL + SHIFT + SPACE) were grids of cards in a panel under the bar
(`columns` and `rows` settings, `BackgroundCard.qml`, `ThemeCard.qml`).
Omarchy opens both as its image-picker carousel: the selected picture large
in the middle of the screen, the others as slanted slices beside it, the
theme's name under it, typing to filter themes
(`/usr/share/omarchy/shell/plugins/image-picker/ImagePicker.qml`, 583 lines,
and `ImagePickerModel.js`). It also dims twice: a full-screen scrim
(`ImagePicker.qml:374-378`, `color: root.scrim`) and a shade over every
unselected slice (`ImagePicker.qml:516-519`, `dimColor` at 0.42). The owner
asked for the carousel without the dimming, as plan 123 already did for the
menus.

## What changed

- **`share/haseen/shell/Haseen/Widgets/Carousel.js`** (new, `.pragma
  library`): the carousel's arithmetic, kept out of QML so a test can run it.
  Omarchy's geometry (`ImagePicker.qml:42-48`: 768×475 selected, 108×432
  slices, spacing -30, skew 28, 13 steps), `fit()` that scales it down for a
  small screen (never up), the card width (`ImagePicker.qml:389`), each
  slice's slot (`ImagePicker.qml:458-461`), mirrored for right-to-left, how
  many slices fit on each side (`reach`), the filter (case-insensitive
  substring on the name or the label, as `ImagePickerModel.js:36-44`), selection that wraps
  and skips hidden items, the theme label (`tokyo-night` → `Tokyo Night`)
  and Omarchy's filter keys (Backspace, Ctrl+Backspace, Ctrl+U, typed
  characters).
- **`SkewSlice.qml`** (new): one slanted slice. Omarchy cuts the shape with
  a `MultiEffect` mask (`ImagePicker.qml:496-501`), which draws nothing on
  haseen's software renderer. Here the content is drawn with the inverse
  shear into a layer, and the layer is sheared back: the slice's edge is a
  parallelogram and the picture inside is upright. A `Shape` draws the
  border and is the `MouseArea`'s `containmentMask`, so a click in a cut
  corner reaches the neighbouring slice. There is no shade over an
  unselected slice.
- **`SkewCarousel.qml`** (new): the carousel. It takes the names and a
  `slice` component, draws the slices through `Loader`s (only those on
  screen and `PRELOAD` (2) beyond on each side are created), the label in
  `Theme.font.display` DemiBold with Omarchy's outline (`ImagePicker.qml:
  548-563`) and the filter line under it (`ImagePicker.qml:566-578`). Keys
  are Omarchy's: Left/Right (mirrored in right-to-left), Tab/Shift+Tab,
  Enter, Escape clearing the filter before it closes; any other key goes to
  the panel. Colours are `Theme.imagePicker.{text,selectedBorder,
  unselectedBorder}` (`Theme.qml:427-431`, Omarchy's `[image-picker]`
  keys) and `Theme.background` for the label's outline. There is no scrim.
- **`haseen.background/Panel.qml`**: the carousel over the theme's
  backgrounds. It opens on the one on screen (`bg current`), Enter or a
  click on the selected slice runs `haseen theme bg set`, `n` runs
  `haseen theme bg next` and follows it, Escape or a click away closes.
  `BackgroundCard.qml` is gone. The picker still paints no wallpaper;
  swaybg under `haseen-background.service` keeps drawing it.
- **`haseen.themepicker/Panel.qml`**: the carousel over `haseen theme list`
  with labels and the filter. `ThemeCard.qml` became `ThemePreview.qml`:
  the preview image, else the theme's palette from its `colors.toml` ("Aa"
  over a row of swatches in the selected item, a column of swatches in a
  slice). Omarchy falls back to a theme's first background; on luna only
  three themes have fetched backgrounds (`ls ~/.cache/haseen/themes` lists
  everforest, nord, retro-82), so the palette stays the fallback.
- **Manifests**: `columns` and `rows` are gone; a `placement` setting
  defaults to `overlay` (the whole screen, no dim). `center` and `bar` show a
  compact carousel (`SkewCarousel.compact`: the selected item and two slices
  a side, a 1120 px card) inside a panel card. There Escape closes the
  picker at once, as it does the menu: `PanelPopup`'s window shortcut takes
  it before the carousel (`PanelPopup.qml:79-90`), and only an overlay
  panel handles Escape itself.
- **i18n**: the old titles and hint line ("Background", "Background · %1",
  "Themes", "Enter applies · n next · Esc closes") left both catalogs; the
  carousel's "No matches" was already translated.
- **`tests/test-widgets-c.sh`**: its comment-skipping grep now passes `-H`.
  With `BackgroundCard.qml` gone the background plugin has one QML file,
  grep drops the file name, and the filter that keys on `file:line:` stopped
  skipping the header comment.

### Memory

Every slice decodes its picture at the selected item's size times the
screen's scale (768×475 at scale 1, 1.46 MB), so selecting a slice never
decodes it again. A 16:9 picture cropped to a 108×432 slice needs a 768×432
decode anyway, so this costs about 10% more per slice, not 7 times. At most
`reach + 2` slices exist on each side while the picker is open, and none
before the carousel has a width. The reviewer measured the theme picker
with 23 themes against 3: +13 MB at scale 1, +40 MB at scale 2, released on
close. `cache: false`, and the panel unloads on close, so nothing stays
after it.

## Verification

- `tests/test-carousel.sh` 42/42 (new). Static checks: both panels use
  `SkewCarousel`, default to `overlay`, have no `columns`/`rows`, no scrim,
  `dimColor`, `MultiEffect`, `ShaderEffect` or `layer.effect`, no hex
  literals, keep the MIT notice and decode at the selected size. `Carousel.js`
  under `qml`: labels, filter, step and keep, fit, reach, slots (also
  mirrored), card, design and compact widths and the filter keys, value
  for value. A draw test
  renders `SkewSlice` on the software scene graph and reads the pixels: the
  centre is filled, the top-left and bottom-right corners are cut, the other
  two are kept, a vertical stripe stays vertical (upright), and the mouse
  area takes only the slanted shape. Removing the inverse shear fails it
  ("the picture is upright"); the reviewer also removed the outer shear,
  which fails three corner and stripe checks.
- `tests/test-widgets-c.sh` and `tests/test-themes2.sh` pass.
- `tests/run.sh --affected`: 74 files (the shared widgets, manifests and
  i18n catalogs widen it), 6612/6612, run from a short bind mount: from
  this checkout's own path `tests/test-menu-back.sh` cannot open its IPC
  socket (past the 108-byte limit, plan 101's known case). The reviewer's
  run at 30f2396 selected the same 74 and passed 6608/6608.
  `tools/lint.sh` lint OK; `tools/check-docs.sh` OK.
- Rendered offscreen in a real Quickshell over a background, both pickers:
  open on the current item, moved, the theme filter `ro` showing 2 of 32
  with "Retro 82" selected, and right-to-left with the next themes on the
  left. The desktop shows through unchanged around the carousel. In the
  `center` placement the card is 1120×609 with three slices a side in
  reach; with no screen the carousel takes its design size, 1822×609, and
  the engine prints no binding loop.

## Review

- Round 1, DeepSeek Flash at 30f2396 (GLM 5.3 Flash's provider was out of
  credits): APPROVE with four nits, all taken in the next commit.
  1. With no `screen` the carousel fitted its own size, which follows its
     implicit size, which follows the fit: three binding loops. It now takes
     its design size, and `reach` is 0 before the carousel has a width
     (it was 13, so slices could start loading before layout).
  2. `center` and `bar` opened a screen-wide card, and Escape there closes
     at once instead of clearing the filter. The carousel is compact in a
     panel card, and both manifests say what Escape does there.
  3. `ThemePreview.hasPreview` had no reader; it is gone.
  4. The verification numbers predated the docs; they are re-cited below.

## Rejected options

- **Omarchy's `MultiEffect` mask.** Draws nothing on the software renderer
  the shell uses (architecture §6); a test window showed empty slices.
- **`clip: true` under a shear.** The software renderer clips to the
  bounding rectangle, so the corners were not cut.
- **`Shape` with `fillItem`.** Filled white on the software renderer.
- **`Canvas` drawing the picture into the parallelogram.** Decodes the
  picture at full size, about 33 MB per 4K background, outside the
  `Image` pipeline's `sourceSize`.
- **Taking Escape from `PanelPopup` in the `center` and `bar` placements.**
  Its window shortcut serves every panel, and the menu behaves the same
  way; the overlay, the default, already gives Escape the filter first.
- **Shearing the image itself.** The picture leans; Omarchy's stays upright.
- **Keeping the shade on unselected slices at a lower alpha.** The owner
  asked for no dimming; the selected slice's accent border and size mark it.
- **Changing `haseen.imagepicker` too.** The generic directory picker was
  not asked for; it keeps its grid.
- **The panel's title, hint line and current-theme dot.** Omarchy's
  carousel has none of them; the label and the selection say the same.
