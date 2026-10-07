# Plan 083: theme generator keys, Wallhaven scroll, bigger previews, centred

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (haseen.themegen stays off by default)
- **Depends on**: 067, 072
- **Category**: shell, theme
- **Planned at**: 2026-10-07, owner's report on haseen.themegen in the real session
- **State**: DONE 2026-10-08 (`tests/test-themegen-keys.sh`; nested screenshots)

## Change

- **Scroll kept when a page loads.** Cause, verified: `WallhavenGrid.qml:116` (before this plan) gave the
  GridView a new JS array per page, and the view rebuilt and went back to contentY 0. A copy of the old grid in
  the test harness, scrolled to cell 20 (contentY 252), read contentY 0 once page 2 landed; the current cell
  survived because it was the grid's own property (`~/.cache/haseen-wt/scratch-themegen/head-cause.log`).
  The model is now a `ListModel` that later pages are appended to (`WallhavenGrid.qml:131,161`); repeats are
  dropped with `Wallhaven.js:96` `fresh(seen, more)`, which replaces `append`. A new search empties it and
  calls `positionViewAtBeginning` (`WallhavenGrid.qml:53,173`).
- **Paging trigger.** With appends the count changes row by row, and `atYEnd` read on a count change was still
  that of the empty view: page 2 loaded before page 1 was seen. The end is now worked out from the count and the
  scroll position (`WallhavenGrid.qml:92` `atEnd`, used at :249,:251). A new search asked for while a page loads
  runs once that page ends and drops it (`restart`, :41); before, the search was refused.
- **Sizes.** Thumbnails 18 em wide (were 10 em: 110 px at the default 11 px font, now 198 px), 4 to a row by
  default (`columns` 4, was 5), smaller only where the panel would pass 60% of the screen width or about 85% of
  its height (`Panel.qml:56`). The palette mock spans two thumbnails at 2:1 (`mockWidth`, :59; was 26 × 13 em).
  At 1536 × 864 the card is 193 px (height cap). `ImageCard.qml:47-48` now decodes both sides at the card's size
  × `pixelRatio`, so a crop of a wide picture is never scaled up from a width-only decode.
- **Centred.** `manifest.json` `placement` (string, default `center`, as haseen.menu declares it);
  `PanelPopup.qml:27` → `PanelPlacement.js:56` anchors nothing for `center`.
- **Keys** (`Panel.qml:83-230`, header comment :19-30). Three stages, `stage` = search | images | palette:
  - search: the field has the focus; every letter, h/j/k/l included, is text. Enter (on Wallhaven a search
    first) or Down → images (`submit`, :145; `Keys.onReturnPressed` :555, because TextInput passes an accepted
    Return on to its parent, where the images stage took it as a pick).
  - images: h/j/k/l and the arrows move; in the Wallhaven grid left/right by one, up/down by a row
    (`Wallhaven.js:111` `gridStep`: the first row stays on up, a shorter last row lands on the last cell); in the
    strip up/down step like left/right. Moving downloads nothing. Enter picks (Wallhaven: downloads) and moves
    to the palette (`choose`, :153).
  - palette: h/j/k/l and the arrows step through the schemes (live preview as before), Enter applies (`confirm`).
  - Everywhere outside the field: `/` back to the field, Backspace back one stage (palette → images → field),
    Tab flips dark/light; Ctrl+S saves; Escape closes (the host).
  - Apply waits for the picture on show: `ready` (:88) also needs no running or queued preview and no download,
    so Enter during a Wallhaven download says "still downloading" and applies nothing. Save/Apply buttons use it.
  - The active area is framed in the accent (`StageFrame.qml`, :575,:630; the field keeps its focus border) and
    the header names the stage's keys before the latest note (:89,:497).
- debugIpc `state` gains `stage`, `ready`, `query`, `strip` and `wallhaven.count`/`scrollY`.

## Evidence

- `tests/test-themegen-keys.sh` (50): manifest (placement center, columns 4, validates); `gridStep` and
  `fresh` in Qt's JS engine; the panel in the real engine (qs, offscreen) with real key events from QtTest's
  `TestEvent` and a stub CLI: hjkl typed into the field stays text; strip and grid movement; Enter → palette →
  Enter calls `theme generate … --scheme content --mode light --name b` (stub argv); page 2 keeps scrollY and
  cell 20; a new search starts at 0; Enter during a held-back download applies nothing, then applies the
  downloaded file. Passed 3 runs in a row.
- `tests/test-wallhaven.sh`, `tests/test-themegen.sh`, `tests/test-widgets-c.sh`, `tests/test-panel-placement.sh`: 366/366.

## Nested proof

`~/.cache/haseen-wt/scratch-themegen/shots/`: worktree shell in a nest, `haseen wallhaven` stubbed with local
images (no network), matugen stubbed, keys from the nest-only virtual keyboard: `1-centred-search.png`,
`2-images-stage.png`, `3-palette-stage.png`, `5-wallhaven-row6-before-page2.png` and
`6-wallhaven-page2-kept.png` (same rows, cell 20, "page 2 of 3"), `8-wallhaven-palette.png`.

## Rejected

- Restoring contentY by hand after a reassignment: keeps the cause and flickers.
- Downloading on every arrow (the old behaviour): a download per key press; Enter now downloads.
- Shift+Tab as "back": Tab already flips the mode; Backspace is the one back key.
- Switching to Wallhaven's larger thumbnails: a CLI change (plan 072); see below.

## Not verified

- Wallhaven's `thumbs.small` (what the CLI caches, `lib/wallhaven.sh:174`) is about 300 px wide [INFERENCE];
  at a pixelRatio above about 1.5 the 198 px card asks for more pixels than it has. Owner decision: keep, or
  cache `thumbs.large`.
- Not run in the owner's live session.
