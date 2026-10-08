# Plan 086: Themegen Quick Look and calendar day-name alignment

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (local preview in the existing panel window; no new window or network request)
- **Depends on**: 083, 085
- **Planned at**: 2026-10-08, owner request
- **State**: DONE 2026-10-08 (`test-themegen-keys.sh` 74/74; `test-clock-dayname.sh` 32/32; `test-themegen.sh` 132/132; `test-widgets-a.sh` 64/64; nested screenshots inspected)

## Change

- `haseen.themegen` adds Quick Look to the existing image stage. Space opens it; Space or Escape closes only the preview; Enter picks; h/j/k/l and the arrows browse. Search-field input is unchanged, so Space still types in the field. The selected local image uses its original file; Wallhaven uses the selected cached `thumbs.small` path, not a full-image download. The preview uses `Image.PreserveAspectFit`, `pixelRatio`, and theme tokens without compositor blur.
- Quick Look is an `Item` in the themegen panel's image-stage body. While open it replaces the grid, hides the search/source/palette controls, and grows the existing centered panel to 85% of screen width by 68% of screen height. Keys stay on the panel's existing focus item.
- The calendar's day-name row spans the seven date columns, not the optional week-number column. Its label fills the remaining row width and is vertically centered beside the existing `Pill`.

## Evidence

- `share/haseen/shell/plugins/haseen.themegen/Panel.qml:99-105,113-147,406,709-781`: preview state/path, hints and key handling, bounded panel size, and the in-panel image-stage content.
- `share/haseen/shell/plugins/haseen.themegen/QuickLook.qml:1-63`: theme-token card, local image rendering, pixel-ratio decode, and fit mode.
- `share/haseen/shell/plugins/haseen.themegen/WallhavenGrid.qml:45-46`: preview path is the current cached thumbnail; the full image is not fetched until Enter.
- `share/haseen/shell/plugins/haseen.calendar/Panel.qml:248-285`: date-column alignment, flexible label, vertical centering, and the existing settings toggle.
- `tests/test-themegen-keys.sh:210-253,327-339`: search text including Space; local preview path, movement, close and pick; Wallhaven cached path, movement, Escape and no `wallhaven get`.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-themegen-keys.sh`: 74/74 passed.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-clock-dayname.sh`: 32/32 passed.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-themegen.sh`: 132/132 passed.
- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-widgets-a.sh`: 64/64 passed.

## Nested proof

Using `tools/nest-launch.sh` under the required `flock`, a local-only CLI stub, and the nest's virtual keyboard, captured and visually inspected:

- `~/.cache/haseen-wt/scratch-quicklook-dayrow/shots/local-quicklook.png`: local wallpaper shown in the expanded in-panel preview.
- `~/.cache/haseen-wt/scratch-quicklook-dayrow/shots/wallhaven-quicklook.png`: cached thumbnail shown; the stub log contains `wallhaven search` and no `wallhaven get`.
- `~/.cache/haseen-wt/scratch-quicklook-dayrow/shots/calendar-dayname.png`: calendar day-name row and On pill aligned to the date columns.

The screenshots and scratch directory are temporary proof artifacts and are removed after inspection; the nested compositor is stopped and its runtime endpoints removed.

## Rejected

- A separate `PanelWindow` for Quick Look. `share/haseen/shell/PanelPopup.qml:71-75` closes the popup when its `HyprlandFocusGrab` is cleared, and `share/haseen/shell/shell.qml:255-275` destroys the lazily loaded panel component on close. A second exclusive-focus window would therefore dismiss the panel it must preview over. Keep the preview inside the existing panel window and focus grab.
- Running `haseen wallhaven get` to preview a result. That downloads the full wallpaper and makes browsing require network and disk work; the cached search thumbnail is already available locally.
