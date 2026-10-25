# Plan 122: The app launcher opens the menu's size

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. The launcher's card is computed from the menu's numbers; its
  behaviour, IPC and providers do not change.
- **Depends on**: 115, 117
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (owner, "super + D launcher must match the hight
  and width of the super + space launcher").

## Why

SUPER + SPACE opens `haseen.menu`; SUPER + D is bound to `haseen.launcher` in
the owner's `~/.config/hypr/bindings.lua:43`. The two cards were different
sizes: the menu was `space(300)` wide (409 px at the owner's font) and as tall
as its ten root rows, the launcher a flat 520 px wide and as tall as its eight
rows of `max(58, …)`. Opening one after the other moved the card.

## What changed

- **`qs.Haseen.MenuMetrics`** (new singleton) holds the menu's card numbers —
  `space(300)`, the 18 px content margin, the 2 px border, the 34 px header,
  the 6 px content spacing, the 50/58 px rows, the 3 px row spacing, the 36 px
  icon column, the heading and icon sizes — computed with Omarchy's base-12
  scale against haseen's `fontSize`, exactly as `haseen.menu`'s
  `MenuStyle.js` does (`scale = max(1/11, fontSize/11)`).
- **`haseen.launcher`** takes its width, header height, row height, icon
  column and spacing from it, and its card is padded by the difference
  between the menu's `contentMargin` and a panel card's `popup-padding`
  (`Theme.spacing.popupPadding`), so the *outer* card — not just the content —
  matches the menu's and the two interiors sit on the same line.
- **Ten rows at rest** (`maxResults` default 8 → 10): the default root menu's
  list (`share/haseen/default/menu.jsonc:38-47`), so both cards are the same
  height on a stock install.
- **The provider prefixes** ("= Calculator  > Clipboard") moved from their own
  line into the header's right edge, elided and hidden when they do not fit,
  so they cost no height; the same list stays in the IPC `state()` as
  `prefixes`.
- **`settings.width`** defaults to 300 and is scaled like the menu's (a
  `settings.width` above 260 still wins, as before).

## Evidence

- `tests/test-surfaces.sh` -> 111/111 (ten new assertions: the launcher's rows
  and header come from `MenuMetrics`, its card width is `MenuMetrics.space()`,
  the padding difference is applied, `MenuMetrics` carries the menu's 300/18/50
  numbers, and the manifest defaults are 300 and 10).
- `tools/lint.sh` -> OK.
- Live on IO: opened both cards and compared them (screenshots in the pull
  request).

## Rejected options

- **Widening the menu to the launcher's 520 instead**: the owner named the
  menu as the reference ("must match … the super + space launcher").
- **Making `haseen.menu` read `MenuMetrics` too**: it would remove the last
  duplicate, but the menu's geometry is pinned by its own suites and this
  change should not move it. `MenuMetrics` mirrors `MenuStyle.js`; a later
  plan can fold one into the other.
- **A fixed card height** (always ten rows tall even with three matches): the
  menu shrinks with its list, so a fixed launcher would stop matching instead.
