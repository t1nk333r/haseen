# Plan 152: the wallpaper and theme pickers use Omarchy's carousel, without the dim

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. Two picker panels change, and they run the same CLI
  commands as before. The overlay window is the one the menu already uses
  (`share/haseen/shell/PanelPopup.qml:14-19`).
- **Depends on**: 020 (themes and backgrounds), 115 (Omarchy's look and
  Theme), 123 (no dim behind the menus)
- **Category**: shell, plugins
- **Planned at**: 2026-11-01, owner: "make the wallpaper selector and theme
  selector like omarchy but without the diming"
- **State**: DONE 2026-11-02, merged as `547119a` (PR 112).
  `tests/test-carousel.sh` passed 44/44.
- **Follow-up**: plan 156. At scale 1.25 on the software renderer every
  slice lost the bottom quarter of its picture. This plan tested scale 1
  only.

## Problem

`haseen.background` (SUPER + CTRL + SPACE) and `haseen.themepicker`
(SUPER + CTRL + SHIFT + SPACE) showed a grid of cards under the bar.
Omarchy opens both as its image-picker carousel
(`/usr/share/omarchy/shell/plugins/image-picker/ImagePicker.qml` and
`ImagePickerModel.js`). The selected picture is large in the middle of the
screen, the others are slanted slices beside it, and typing filters the
themes. Omarchy's picker also dims the whole screen (`ImagePicker.qml:377`)
and shades every unselected slice at 0.42 alpha (`ImagePicker.qml:518`). The
owner asked for the carousel without either dim, as plan 123 did for the
menus.

## What changed

### The shared widgets

Three new files in `share/haseen/shell/Haseen/Widgets/` draw the carousel
for both pickers. Nothing in them darkens the screen or a slice.

- **`Carousel.js`** holds the arithmetic, so a test can run it without a
  window. It has Omarchy's geometry (`ImagePicker.qml:42-48`): the selected
  item at 768x475, slices of 108x432 that overlap by 30 px, a 28 px slant
  and 13 slice steps. `fit()` shrinks it for a small screen and never
  enlarges it. It also has the card width (`ImagePicker.qml:389`), each
  slice's position (`ImagePicker.qml:458-462`), Omarchy's filter
  (`ImagePickerModel.js:36`), the filter keys (Backspace, Ctrl+Backspace and
  Ctrl+U), and the labels that turn `tokyo-night` into "Tokyo Night".
- **`SkewSlice.qml`** draws one slanted slice. Omarchy cuts the slant with a
  `MultiEffect` mask (`ImagePicker.qml:496`), and that draws nothing on the
  software renderer haseen uses. `SkewSlice` instead draws its content
  into a layer with the inverse shear, then shears the layer back. The
  outline becomes a parallelogram, and the picture inside stays upright. A
  `Shape` draws the border. The same `Shape` is the `MouseArea`'s
  `containmentMask`, so a click in a cut corner goes to the neighbouring
  slice.
- **`SkewCarousel.qml`** lays out the slices. It takes a list of names and
  a `slice` component, and it loads a slice only while it is on screen or
  within `PRELOAD` (2) slices of it. The label and filter lines follow
  Omarchy (`ImagePicker.qml:547-580`). The label is `Theme.font.display` in
  DemiBold, outlined in `Theme.background` at 0.7 alpha. The keys follow
  Omarchy too:
  Left and Right, Tab and Shift+Tab, Enter, and Escape, which clears the
  filter before it closes the picker. The colours come from
  `Theme.imagePicker` (`Theme.qml:427`, Omarchy's `[image-picker]` keys).

### The pickers

- **`haseen.background`** shows the current theme's backgrounds. It opens
  on the one on screen (`haseen theme bg current`). Enter, or a click on the
  selected slice, runs `haseen theme bg set`. The `n` key runs
  `haseen theme bg next`. `BackgroundCard.qml` is gone. swaybg, under
  `haseen-background.service`, still draws the wallpaper.
- **`haseen.themepicker`** shows `haseen theme list` with labels and the
  filter. `ThemeCard.qml` became `ThemePreview.qml`, which shows the
  theme's preview image or, without one, the palette from its
  `colors.toml`. Omarchy falls back to a theme's first background instead,
  but on luna only three themes had fetched backgrounds
  (`ls ~/.cache/haseen/themes`), so the palette stays the fallback.

### Settings, strings and tests

- **Manifests.** The `columns` and `rows` settings are gone. A new
  `placement` setting defaults to `overlay`, the whole screen. `center` and
  `bar` put a compact carousel, 1120 px wide, in a panel card of about
  1150x640 with its padding. It shows up to two slices on each side, one
  below a screen width of about 1160 px, and none below about 1000 px. In a
  panel card, Escape closes the picker at once, because `PanelPopup`'s
  window shortcut takes it first (`PanelPopup.qml:79-90`).
- **Translations.** The grid's strings "Background", "Background · %1",
  "Themes" and "Enter applies · n next · Esc closes" left both catalogs.
- **`tests/test-widgets-c.sh`.** Its comment-skipping grep now passes `-H`.
  With one QML file left in the background plugin, grep printed no file
  name, and the filter that expects `file:line:` stopped working.

### Memory use

Every slice decodes its picture at the selected item's size times the
screen's scale (768x475 at scale 1, 1.46 MB), so selecting a slice needs no
second decode. A 16:9 picture cropped to a 108x432 slice needs a 768x432
decode anyway, so this costs about 10% more per slice. At most `reach + 2`
slices exist on each side, and before the carousel has a width only the two
preloaded slices on each side load. The reviewer measured the theme picker
with 23 themes against one with 3. The picker with 23 used 13 MB more at
scale 1 and 40 MB more at scale 2. The images use `cache: false` and the
panel unloads on close, so the memory is released when the picker closes.

## Verification

- `tests/test-carousel.sh` (new) passed 44/44.
  - Static checks: both panels use the carousel, open as overlays and have
    no dim or shader. The widgets have no hex colour, and
    `tests/test-themes2.sh` and `tests/test-widgets-c.sh` check the panels
    for one.
  - `Carousel.js` runs under Qt's `qml` engine and each result is compared
    by value. At no whole width from 0 to 2000 px does a compact slice cross
    the card's edge.
  - A draw test renders `SkewSlice` on the software renderer and reads its
    pixels. Two corners are cut, a vertical stripe stays vertical, and the
    mouse area takes clicks only inside the slant. Removing either shear
    fails it.
- `tests/test-widgets-c.sh` and `tests/test-themes2.sh` pass.
- `tests/run.sh --affected` selected 74 files and passed 6614/6614. One
  earlier run missed two checks in `tests/test-shell-tokens.sh` that wait
  for a Hyprland config reload. That file passes alone (73/73, twice), and
  this change touches neither Theme nor Config.
- Both pickers rendered offscreen in a real Quickshell over a background.
  The theme filter `ro` showed 2 of 32 themes with "Retro 82" selected, and
  in right-to-left the next themes sat on the left. In the `center`
  placement the carousel measured 1120x609. Without a screen it took its
  design size, 1822x609, and Qt printed no binding loop.

## Review

DeepSeek Flash approved five rounds (GLM 5.3 Flash's provider was out of
credits). Its notes led to the fixes the text above describes, and to
removing the unused `ThemePreview.hasPreview`. Without a screen the
carousel's size depended on itself, and Qt reported three binding loops.
The `center` and `bar` placements opened a card as wide as the screen. On a
narrow screen the compact card cut its outer slices. The reviewer counted
11,712 pixels outside the card at 1080 px before `fitReach`, and 0 after.

## Rejected options

- **Omarchy's `MultiEffect` mask.** It draws nothing on the software
  renderer the shell uses (architecture §6). A test window showed empty
  slices.
- **`clip: true` under a shear.** The software renderer clips to the
  bounding rectangle, so the corners stayed.
- **`Shape` with `fillItem`.** It filled the slice white on the software
  renderer.
- **A `Canvas` that draws the picture into the parallelogram.** It decodes
  the picture at full size, about 33 MB for each 4K background, because a
  Canvas ignores the `sourceSize` that limits an `Image`.
- **Taking Escape from `PanelPopup` in the `center` and `bar` placements.**
  Its window shortcut serves every panel, and a menu placed in a panel
  closes on Escape the same way. The default overlay placement already
  lets Escape clear the filter first.
- **Shearing the picture itself.** The picture would lean. Omarchy's stays
  upright.
- **A lighter shade on the unselected slices.** The owner asked for no dim.
- **The same carousel in `haseen.imagepicker`.** The owner did not ask for
  it. That generic directory picker keeps its grid.
- **The panel's title, hint line and current-theme dot.** Omarchy's
  carousel has none of them. The label and the selection carry the same
  information.
