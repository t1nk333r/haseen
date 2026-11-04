# Plan 158: the theme picker shows Omarchy's pictures

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. The theme picker scans one more directory and ranks what
  it finds in a small JavaScript file. `haseen theme fetch` stops making a
  thumbnail that only the picker read. The shared carousel decodes its
  pictures at its window's pixel ratio instead of the screen's.
- **Depends on**: 020 (themes, backgrounds and the fetch), 152 (the
  carousel), 156 (the slice at a fractional scale)
- **Category**: shell, plugins, themes
- **Planned at**: 2026-11-04, owner: "wallpaper and theme selector still
  broken the it has like 25% of the bottom missing the images does not fill
  the trapezoid also the images are not taken from omarchy for the theme
  take them"
- **State**: DONE 2026-11-04. `tests/test-carousel.sh` passed 72/72 and
  `tests/test-themes2.sh` 226/226. IO gets this and plan 156 with its next
  update.

## Problem

The owner reported three things on IO. Two of them are one bug that IO had
not received yet. The third is new.

### The bottom quarter and the unfilled slant

IO still ran `547119a`, plan 152's merge. Its installed
`/usr/local/share/haseen/shell/Haseen/Widgets/SkewSlice.qml` is dated
2026-11-02 09:08 and has no `flipped` property (`grep -c flipped` printed
0 on IO, 2026-11-04). Plan 156's fix, merged as `f294fe5`, never reached
IO. A picture that ends three quarters of the way down its slanted frame
is also what "the images does not fill the trapezoid" describes.

Plan 156 tested its fix offscreen with `QT_SCALE_FACTOR`, never in a live
Wayland window. This plan checked it live on luna, on a headless Hyprland
output at scale 1.25 (`hyprctl output create headless`, then
`hl.monitor({ ..., scale = 1.25 })` through `hyprctl eval`), with a test
shell on the software renderer and `grim -o`:

- `547119a`'s slice drew its picture a quarter of its height too high.
  The picture's top quarter was cut off, its bottom edge sat at row 446 of
  the card's 594 device rows, and the frame below it was empty.
- `main`'s slice filled its frame. The real `SkewCarousel`, with 14 of
  Omarchy's backgrounds and a 6 px band along each picture's bottom edge,
  filled every slice down to the band.

So the first two reports need IO to update, not new code.

### The theme pictures

The theme picker took a theme's picture from two places only: the user
theme's own `preview.png`, then the cache of `haseen theme fetch`. In the
cache it preferred `preview-thumb.png`, a 512x288 thumbnail. On IO the
cache held 14 of the 24 stock themes. The selected card is 768x475
logical pixels, 960x594 at IO's scale, so those 14 were drawn at 1.9 times
their size. The other 10 stock themes showed only their palette. Of IO's
10 user themes one has its own preview, eight have a `backgrounds/` image
and no preview, and one has neither. The picker showed nine palettes
there.

IO and luna both have Omarchy installed at `/usr/share/omarchy`
(`OMARCHY_PATH` in IO's session, version `4.0.0.alpha`). Each of its 22
stock themes has a 1800x1012 `preview.png` and a `backgrounds/` directory.
Omarchy's own switcher picks a theme's picture in `find_preview`
(`/usr/share/omarchy/bin/omarchy-theme-switcher`): `preview.png`, `.jpg`,
`.jpeg`, `.webp`, `.gif` or `.bmp`, in that order and in any case, else
the theme's first background in sorted order. It looks in the user's
theme first and falls back to Omarchy's theme of the same name. Its
carousel shows that picture at up to 1536x864: `omarchy-menu-images` makes
its thumbnails with `vipsthumbnail --size 1536x864`.

### Found on the way: decodes at twice the size

The carousel decoded every picture at the selected card's size times
`screen.devicePixelRatio`. On the headless output at scale 1.25 the
`ShellScreen` reported 2 and the Quickshell window reported 1.25. The
screen's ratio is the output's scale rounded up to a whole number. Every
picture on IO therefore decoded at 1536x950, 2.56 times the pixels the
window draws.

## What changed

- **`share/haseen/shell/plugins/haseen.themepicker/Previews.js`** is new.
  It ranks the scanned files the way `find_preview` does, adapted under
  Omarchy's MIT notice. It looks in three places: the user's theme
  (`~/.config/haseen/themes`), the fetched cache
  (`~/.cache/haseen/themes`) and the installed Omarchy
  (`$OMARCHY_PATH/themes`, else `/usr/share/omarchy/themes`). The order is:
  1. the user theme's preview, then its first background;
  2. the cache's preview, then the installed Omarchy's preview;
  3. the cache's first background, then the installed Omarchy's.

  The cache and the installed Omarchy hold the same stock themes, so a
  stock preview from either comes before a stock background from either.
  The cache comes first because it is fetched from the commit that haseen's
  stock colours come from (`THEME_OMARCHY_COMMIT`), while an installed
  Omarchy can be another release. A background's order is JavaScript's
  string order, which for ASCII names equals `sort` under `LC_ALL=C`.
- **`haseen.themepicker/Panel.qml`** scans the three places with one
  `find`, down to `backgrounds/`, and hands the output to `Previews.js`.
  It reads the installed Omarchy's path as
  `Compat/Omarchy/Commons/I18n.qml:27` does. haseen reads these images
  where they are installed and never ships or copies them, as with the
  fetched artwork (`NOTICE.md`).
- **The picker reads `preview.png`, not the 512 px thumbnail.** Every
  slice decodes at the selected card's size, so a thumbnail saves little
  (Verification) and looks blurry. `haseen theme fetch` no longer makes
  `preview-thumb.png` and no longer needs `glycin-thumbnailer`.
- **`SkewCarousel.qml`'s `pixelRatio`** is `QsWindow.window.devicePixelRatio`
  when the window reports one, else the screen's as before. Both pickers
  decode through it.
- `ThemePreview.qml`'s and the manifest's text, `NOTICE.md`'s row for the
  carousel, `docs/architecture.md`, `handoff.md` and plan 152's status
  point to this plan.
- `tests/test-carousel.sh` runs the panel's own `find`, read from
  `Panel.qml`, over a fixture of user, cache and installed themes. It
  checks the ranking under Qt's engine and that the picker no longer reads
  the thumbnail. `tests/test-themes2.sh` checks that fetch makes no
  thumbnail.

## Verification

- `tests/run.sh tests/test-carousel.sh` passed 72/72, 7 checks more than
  before. With the cache and the installed Omarchy swapped in
  `Previews.js` it failed "each theme's picture, in Omarchy's order".
  `tests/test-themes2.sh` passed 226/226.
- `tests/run.sh --affected` selected 76 of 172 test files and passed
  7072/7072. The shared widget makes the set wide.
- The scan of IO's real files (`find` over IO's three places, 2026-11-04,
  read only) ranked through `Previews.js` gives 31 of IO's 34 themes a
  picture, up from 15, 14 of them blurry. The 22 Omarchy stock themes get
  Omarchy's `preview.png`: 14 from the cache and 8 from
  `/usr/share/omarchy`. The user theme with a preview keeps it, and the
  eight with only a background show it. haseen's own `haseen` and
  `starship` themes, which Omarchy does not have, and the user theme with
  no image keep their palette.
- The real theme picker panel from this branch ran live on luna's headless
  output at scale 1.25 on the software renderer. 30 of luna's 32 themes
  showed a picture and every stock theme showed Omarchy's `preview.png`.
  The carousel's `pixelRatio` read 1.25. The test shell's RSS with the
  picker open was 142 MB, and 169 MB with the screen's ratio of 2.
- Memory of the thumbnail, offscreen at `QT_SCALE_FACTOR=1.25`, 22 of
  Omarchy's previews decoded at 960x594 each, two runs each:

  | | RSS while shown | left after the images go |
  |---|---|---|
  | full 1800x1012 `preview.png` | +80.5 to +81.5 MB | +14 to +21 MB |
  | 512x288 thumbnail | +71.4 to +71.7 MB | +17 to +47 MB |

  The decode at the card's size dominates. Plan 020 made the thumbnail for
  the old grid, where a tile decoded the whole preview.
- Screenshots of the live tests showed luna's own notifications and were
  deleted after viewing.

## Review

DeepSeek Flash reviewed the first head, before the rebase. Codex's requests to the proxy's DeepSeek
route now fail with a 422 on the `developer` message role, so the reviewer
ran in `omp` with that role turned off. It reproduced the counts above,
65/65 at the base, lint and the docs check. It ran `Previews.js` over the
installed Omarchy's 22 themes and got the same 22 previews as
`find_preview`. It also ran an adversarial fixture and seven mutations of
its own. Its findings:

- **Blocker: the plan number.** PR 118 merged its own plan 157 while this
  was open, so this plan became 158 when the branch was rebased onto it.
- **Two fixture lines could not fail.** A root guard without its `/` and an
  image pattern without its `$` each still passed 72/72. Each edge case is
  now the only candidate for its theme (`uXz/preview.png`,
  `partial/backgrounds/a.jpg.part`), and both mutations fail.
- **`docs/architecture.md` and `Panel.qml` misstated the order.** They now
  say that any stock preview comes before any stock background.
- **Omarchy's `sort` follows the locale** (Notes for later changes).
- **The pixel ratio is checked only in the source text.** No offscreen test
  can show a window's ratio, and the live run above is the evidence.
- **An animated GIF would animate in a slice.** It would not: QML's `Image`
  shows a GIF's first frame, and only `AnimatedImage` plays it.

The second round reviewed the rebased head and the fixes. It accepted each
response above, and both mutations now failed for it too. It found one
more blocker: this section cited the first head's commit, which the rebase
had replaced, so `tools/check-docs.sh` failed in a fresh clone. The
section now names no branch commit. It also asked for "for ASCII names"
in the sort note above. Its affected run counted 7083/7083 over the same
76 files: plan 157 added 11 checks to `tests/test-pager.sh`, which is in
the selection.

## Rejected options

- **Keep the thumbnail ahead of `preview.png`.** It is drawn at 1.9 times
  its size on IO and saves about 10 MB while the picker is open.
- **Make a bigger thumbnail, as Omarchy does (1536x864 JPEG).** The decode
  at the card's size still dominates. It would need a thumbnailer for the
  installed Omarchy's previews as well.
- **Run `haseen theme fetch --all` when the picker opens.** That is about
  65 MB of downloads on a key press, and the installed Omarchy already has
  the previews on disk.
- **Copy the installed previews into haseen's cache.** It duplicates
  files that can be read where they are.
- **Rank strictly place by place, as Omarchy does with its two places.**
  The cache's background would then beat the installed Omarchy's preview of
  the same stock theme. A preview shows the theme. A background is only one
  of its wallpapers.
- **Read `~/.config/omarchy/themes`.** `haseen theme list` does not list
  Omarchy's user themes (`theme_names` in
  `share/haseen/layers/theme/theme-lib.sh`), so no slice would use them.
- **Keep the screen's pixel ratio.** It is 2 on IO's 1.25 screen.

## Notes for later changes

- A theme's first background is the first in JavaScript's string order,
  which for ASCII names is C order (`LC_ALL=C sort`).
  Omarchy's switcher sorts in the session's locale, so for names that differ
  in case, such as `Z.jpg` and `a.jpg`, it can pick the other one.

- `haseen.imagepicker` (`Panel.qml:259`) and `haseen.themegen`
  (`Panel.qml:56`) still decode at the screen's ratio, so on IO they decode
  2.56 times the pixels they draw.
- Caches fetched before this plan keep a `preview-thumb.png` beside each
  `preview.png`. Nothing reads them, and deleting them is safe.
- To check rendering at a fractional scale in a real Wayland window
  without touching a monitor: `hyprctl output create headless NAME`,
  `hyprctl eval 'hl.monitor({ output = "NAME", mode = "1920x1080@60",
  position = "-3000x0", scale = 1.25 })'`, a test shell with
  `//@ pragma DefaultEnv QT_QUICK_BACKEND = software` and its own
  `XDG_RUNTIME_DIR`, `grim -o NAME`, then `hyprctl output remove NAME`. The
  running shell draws its bar and notifications on that output as well.
