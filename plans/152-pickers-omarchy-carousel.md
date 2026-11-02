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
- **State**: DONE 2026-11-02 (`tests/test-carousel.sh` 44/44, the affected
  set 74 files; the live pickers are an owner step)

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
  substring on the name or the label, as `ImagePickerModel.js:36-44`),
  selection that wraps and skips hidden items, the theme label
  (`tokyo-night` → `Tokyo Night`) and Omarchy's filter keys (Backspace,
  Ctrl+Backspace, Ctrl+U, typed characters).
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
  a side in 1120 px, so about a 1150 px card with its padding; on a screen
  under about 1160 px it shows only the slices that fit the card: one a
  side down to about 1000 px, then the selected item alone) inside a panel
  card. There Escape closes the picker at once, as it does a menu
  placed in a panel: `PanelPopup`'s window shortcut takes it before the
  carousel (`PanelPopup.qml:79-90`), and only an overlay panel handles
  Escape itself.
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
`reach + 2` slices exist on each side while the picker is open. Before the
carousel has a width none is visible and only the two preloaded slices a
side load. The reviewer measured the theme picker
with 23 themes against 3: +13 MB at scale 1, +40 MB at scale 2, released on
close. `cache: false`, and the panel unloads on close, so nothing stays
after it.

## Verification

- `tests/test-carousel.sh` 44/44 (new). Static checks: both panels use
  `SkewCarousel`, default to `overlay`, have no `columns`/`rows`, no scrim,
  `dimColor`, `MultiEffect`, `ShaderEffect` or `layer.effect`, no hex
  literals, keep the MIT notice and decode at the selected size. `Carousel.js`
  under `qml`: labels, filter, step and keep, fit, reach, slots (also
  mirrored), card, design and compact widths, the compact card's reach
  (two slices a side, one on a 1080 px screen, never past the card at any
  whole width from 0 to 2000) and the filter keys, value for value. A `fitReach`
  that ignores the card's width fails it. A draw test
  renders `SkewSlice` on the software scene graph and reads the pixels: the
  centre is filled, the top-left and bottom-right corners are cut, the other
  two are kept, a vertical stripe stays vertical (upright), and the mouse
  area takes only the slanted shape. Removing the inverse shear fails it
  ("the picture is upright"); the reviewer also removed the outer shear,
  which fails three corner and stripe checks.
- `tests/test-widgets-c.sh` and `tests/test-themes2.sh` pass.
- `tests/run.sh --affected`: 74 files (the shared widgets, manifests and
  i18n catalogs widen it), 6614/6614, run from a short bind mount. One
  run at 8ba2e73 missed two of `tests/test-shell-tokens.sh`'s checks that
  wait for a Hyprland config reload; they pass alone (73/73, twice), this
  change does not touch Theme or Config, and the reviewer's run of that
  head passed 6614/6614 and the file seven times, six of them under load.
  From this checkout's own path `tests/test-menu-back.sh` cannot open its
  IPC socket (past the 108-byte limit, plan 101's known case). The
  reviewer's runs selected the same 74 and passed 6608/6608 at 30f2396
  and 6614/6614 at c2c68e3, 8ba2e73 and aec70ce.
  `tools/lint.sh` lint OK; `tools/check-docs.sh` OK.
- Rendered offscreen in a real Quickshell over a background, both pickers:
  open on the current item, moved, the theme filter `ro` showing 2 of 32
  with "Retro 82" selected, and right-to-left with the next themes on the
  left. The desktop shows through unchanged around the carousel. In the
  `center` placement the carousel is 1120×609 (the card about 1150×640
  with its padding); with no screen the carousel takes its design size,
  1822×609, and the engine prints no binding loop.

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
- Round 2, DeepSeek Flash at fa780fa: APPROVE; the four fixes reproduce
  (no binding loop with no screen, a 1120 px compact carousel, 42/42 and
  6612/6612). Four nits, taken in the next commit: the compact carousel's
  reach is capped at two slices a side (the third overlapped the card's
  padding by 58 px), the manifests compare Escape with a menu placed in a
  panel rather than the menu (an overlay by default), and the plan's
  preload and card-size sentences are corrected.
- Round 3, DeepSeek Flash at c2c68e3: APPROVE; the cap reproduces (0 pixels
  outside a 1120 px card, 19,373 at fa780fa), also mirrored. Three nits,
  taken: the cap ignored the width, so on a screen under 1160 px the two
  slices still spilled up to 70 px past a narrower card; `Carousel.fitReach`
  now counts only the slices that fit, tested by value over every width
  from 0 to 2000 instead of by a grep of the source; and the card size reads
  about 1150×640, which covers a theme with or without a border.
- Round 4, DeepSeek Flash at 8ba2e73: APPROVE; `fitReach` reproduces (0
  pixels outside the card at 1536 and 1080 px, also mirrored; 11,712 at
  c2c68e3 on 1080), and so does the mutant's failure. Three wording nits,
  taken: below about 1000 px the compact carousel shows the selected item
  alone, the index leads with the passing run, and the reach test steps
  through every whole width instead of every fourth.
- Round 5, DeepSeek Flash at aec70ce: APPROVE; 44/44, 6614/6614, and the
  narrow-screen boundaries recomputed exactly (one slice a side from 1004
  to 1159 px, two from 1160). Two cosmetic nits, taken: this paragraph's
  wrapping and "seven times, six of them under load".

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
  Its window shortcut serves every panel, and a menu placed in a panel
  behaves the same way; the overlay, the default, already gives Escape the
  filter first.
- **Shearing the image itself.** The picture leans; Omarchy's stays upright.
- **Keeping the shade on unselected slices at a lower alpha.** The owner
  asked for no dimming; the selected slice's accent border and size mark it.
- **Changing `haseen.imagepicker` too.** The generic directory picker was
  not asked for; it keeps its grid.
- **The panel's title, hint line and current-theme dot.** Omarchy's
  carousel has none of them; the label and the selection say the same.
