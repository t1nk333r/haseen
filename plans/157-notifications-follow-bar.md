# Plan 157: notification cards follow the bar

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. With the bar on top, the default, nothing moves: the deck
  stays top-right and every placement is drawn as before (`Layout.fromEdge`
  returns its `y` unchanged, `Layout.js:38-40`).
- **Depends on**: 025 (haseen.pager), 112 (the bar on any edge)
- **Category**: shell
- **Planned at**: 2026-11-04, from the owner
- **State**: DONE 2026-11-04 (`tests/test-pager.sh` 80/80). The live
  check with the bar on the bottom and on the left is an owner step.

## Problem

The owner, 2026-11-04: "make the notification card follow the bar if the
bar in the bottom push the cards to the buttom on the left push them to the
top left and to the right top if the bar on the right and default if bar on
top. when on buttom the cards stack against the bar and open upwards not
downwards like the top placemnt".

Both notification daemons put their cards top-right whatever edge the bar
is on. haseen.pager anchored its window `top`, `bottom` and `right` and its
deck to the window's top-right corner (`Service.qml` before this change,
`anchors { top: true; bottom: true; right: true }` and
`anchors.right: parent.right; anchors.top: parent.top`). The fallback,
haseen.notifications, anchored its popup column `top` and `right`. With the
bar on the bottom the cards still dropped from the top of the screen, far
from the bar; with the bar on the left they sat on the opposite side.

## Decision

The deck's corner follows `bar.position` (`Config.barPosition`,
`Haseen/Config.qml:25`, one of top, bottom, left, right):

| bar | deck | stacks against | opens |
|---|---|---|---|
| top | top-right | the top edge, under the bar | downwards |
| right | top-right | the top edge, beside the bar | downwards |
| left | top-left | the top edge, beside the bar | downwards |
| bottom | bottom-right | the bottom edge, above the bar | upwards |

No window has to measure the bar. The bar reserves its edge
(`Bar.qml:102-103`, normal exclusion, `exclusiveZone: thickness`) and both
daemons' windows use `exclusiveZone: 0`, so the compositor keeps them off
the bar on whichever edge it is.

`Layout.compute` is unchanged: its `y` still means "distance from the edge
the deck stacks against", newest first. Two pure functions are added:

- `Layout.edgeFor(barPosition)` (`Layout.js:29-31`) says which corner:
  `{ bottom, left }`.
- `Layout.fromEdge(y, height, deckHeight, bottom)` (`Layout.js:38-40`)
  turns a placement into the deck's top-down coordinates:
  `deckHeight - y - height` for a bottom deck, `y` otherwise. With height 0
  it turns a point back, which is how the hover area tests the pointer
  against placements.

So the scene clock, the enter animation and every placement keep one
meaning. A new card's seed, 30 px short of its landing place
(`Service.qml:1534`), starts it beyond the bar's edge in both modes: it
slides down from the top, or up from the bottom bar.

At the bottom a card is drawn bottom-anchored (`Toast.qml:351`): its bottom
edge stays put, so a card that grows (buttons, the reply field) grows
upwards, away from the bar. Its scale origin moves to `Item.Bottom`
(`Toast.qml:355`), so the cards behind the front one shrink towards the bar
and peek out above it. The card's own content still lays out top-down; its
words rise with the card as it grows.

## Change

- `haseen.pager/Layout.js`: `edgeFor` and `fromEdge`.
- `haseen.pager/Service.qml`: `edge` and `atBottom` (`:1152-1153`). The
  window anchors to the left beside a left bar (`:2441-2442`). The clipper
  anchors to the bottom above a bottom bar, `edgeSpacing` from it
  (`:2463-2468`), and its height no longer adds the deck's `y`, which is now
  the motion inset at the bottom (`:2470`, `:2476-2477`). The motion inset
  stays on the sides away from the bar and the screen edge. The hover
  area's two hit tests turn the pointer into placement coordinates
  (`:2497`, `:2535`).
- `haseen.pager/Toast.qml`: the card's `y` and `transformOrigin`.
- `haseen.notifications/Service.qml`: the popup window anchors to the bar's
  corner (`:181-184`) with `Theme.gap` on every side, and with a bottom bar
  the column is reversed so the newest popup is the one against the bar
  (`:215`). Its manifest's description says so.
- `haseen.pager/UPSTREAM.md`: the `Layout.js` and `Toast.qml` rows and the
  surface paragraph.

## Rejected options

- **Mirroring the deck with a negative y scale** (on the deck, and again on
  each card so its text reads upright). Two transforms per card make every
  child's coordinates lie, which breaks the hover hit tests
  (`Toast.hoverOn` maps items into the card) and the reply field's input
  position. An explicit turn in one pure function is testable under node.
- **Laying the card's insides out bottom-up**, so the words stay still and
  the buttons appear above them. That puts the headline under the actions,
  the opposite of every other card, and doubles the anchors in a file that
  already carries the reply field and the menu.
- **A setting for the corner.** The owner asked for the cards to follow the
  bar; a separate setting would let them disagree, and nothing asked for
  that.
- **A bottom-left corner for a bottom bar, or a top-right one for a left
  bar.** The owner named the corners: bottom with a bottom bar, top-left
  with a left bar, top-right otherwise.
- **Reading the bar's thickness to offset the window.** The bar's exclusive
  zone already moves the window (`Bar.qml:102-103`); a second offset would
  leave a gap of a bar's width.

## Verification

- `tests/test-pager.sh` 80/80. `security.cjs` checks `edgeFor` for every
  position and an unset one, and `fromEdge` in both modes and that it turns
  a point back. The qs harness creates two cards against a stub scene
  (`y` 10, height 58, deck 200): with a bottom bar the card's bottom edge
  is 10 px above the deck's bottom and it scales from `Item.Bottom`; with a
  top bar its `y` is 10 and it scales from `Item.Top`. Grep checks pin the
  pager's corner to `Config.barPosition`, the bottom anchor, the hover
  turn, and the fallback's anchors and reversed column.

## Residual unknowns

- Not yet seen live with the bar on the bottom or the left; the harness
  draws cards offscreen without a compositor. The owner checks it with
  `haseen bar position bottom` (and `left`) and `notify-send`.
- With the bar on the left and a right-to-left language, the deck keeps
  its explicit x (`Service.qml:2476`), as it did on the right before; the
  cards mirror inside it (plan 109). Not checked with an RTL locale.
