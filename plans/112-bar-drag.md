# Plan 112: Drag bar widgets, and the bar itself, without arrange mode

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MEDIUM. Every press on the bar now passes a drag handler, and the
  bar's widgets live in a pool that moves between section cells instead of in
  the sections. A press that stays under the threshold, the wheel, the right
  and middle buttons and double clicks reach widgets as before; this is
  measured in the real engine against native, BarButton, TapHandler, Omarchy-
  and DMS-hosted widgets (below). The compositor's pointer grab, the overlay
  window and Escape need a live session (Owner steps).
- **Depends on**: 015 (the bar, transparency), 050 (the overflow panel, slots
  moved by reparenting), 051 (arrange mode and drops), 095 (the nook), 100
  (affected tests), 109 (I18n; the bar is never mirrored)
- **Category**: shell
- **Planned at**: 2026-10-22, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; drags on a live Hyprland session
  are owner steps)

## Decision (owner, 2026-10-22)

In the coordinating thread the owner asked: "I want the elements of the bar to
freely be graped and moved like the omarchy shell bar not a toggle". Asked
whether to also move the whole bar, the owner chose **"Widgets and the whole
bar"**: drag any widget anywhere (within and between sections, into and out of
the overflow drawer) with no arrange mode; and hold on empty bar space (about
0.2 s) or drag it past the threshold to move the bar to another screen edge,
like Omarchy. Double-click and right-click on empty space must keep working.

Not chosen: **"Widgets only"**, which would have kept `haseen bar position`
and arrange mode's edge buttons as the only ways to move the bar.

Plan 051 had rejected dragging the bar: "Dragging the bar itself was rejected:
it competes with double-click and right-click on the same little empty space"
(`plans/051-io-round-5.md:29-30`), and limited widget drags to arrange mode
because "outside it every press belongs to the widget"
(`plans/051-io-round-5.md:31-32`; `docs/architecture.md:366-369` at 6cdaf97).
Both now coexist: the bar move starts only on a 200 ms hold or a drag past
the threshold, a double click is two short presses and a right click another
button, and a widget drag starts only once a press has travelled past the
threshold, so a press that does not travel stays the widget's.

## Problem

At 6cdaf97 a widget moves only in arrange mode: a right click on empty bar
space (`share/haseen/shell/Bar.qml:312-326`), Style › Bar › Arrange widgets
(`share/haseen/default/menu.jsonc:126`) or `haseen bar arrange`. Arrange mode
covers every widget with a `MouseArea` that keeps the mouse
(`share/haseen/shell/BarSection.qml:208-223`, `preventStealing: true`), so the
widget never sees a press while it is on. The bar moves only through `haseen
bar position`, Style › Bar › Position or arrange mode's four edge buttons. A
cross-section drop rebuilt the widget: each section had its own `Repeater`
(`BarSection.qml:104-140`), so the id left one and was built anew in the
other.

## Omarchy 4.5's bar (read, not pasted)

A read-only sparse clone of `v4.5.0-rc1` (03ff1eff3812933f7088484533784d2f63eaf19a),
`shell/plugins/bar/Bar.qml`, deleted afterwards:

- Every widget slot has a `MouseArea` over the widget (`modulePointer`,
  `:2617`, `acceptedButtons: Qt.LeftButton` `:2627`,
  `propagateComposedEvents: true` `:2631`). It takes the press itself; a drag
  starts past `dragThreshold: Style.space(4)` (`:2624`; `Commons/Style.qml:221`
  rounds `px × scale`, 4 px at scale 1); a click is handed to the widget by the
  bar (`onClicked` `:2701-2709` → `pressModuleClickTarget` `:1311`, the
  widget's `triggerPress`). The widget never sees the press.
- The drop: `moduleDropAtScene` (`:990`), room opened where it would land
  (`moveDragRoom` `:1114`), the ghost gliding into it before the write
  (`settleBarDrag` `:1211`); the ghost in an overlay window with an empty mask
  (`DragGhostPanel` `:1757`, `mask: Region {}` `:1782`).
- The bar move: `CenterGestureArea` (`:2055`) on empty space, left button
  (`:2064`), `pressAndHoldInterval: 200` (`:2066`) or the threshold;
  `beginBarMove`…`finishBarMove` (`:589-616`); the edge from
  `nearestScreenEdge` (`:577`), which splits the screen along its diagonals in
  normalised space; a preview per edge in an input-less overlay
  (`BarMoveGhostPanel` `:1805`).

haseen keeps its widgets' own pointer handling (and that of Omarchy and DMS
widgets it hosts, which expect their own presses), so it takes the gestures,
the drop rule's shape, the edge rule and the overlay windows, and not the
press model.

## What was built

### The bar's contents move out of its window

`Bar.qml` is now the layer-shell window only: the overflow panel and the drag
overlay (both lazy), Escape during a drag, the hairline, and the members
`shell.qml`, `BarOverflowPanel.qml` and the nook already used, forwarded.
Everything inside it is `BarStrip.qml`: the sections, the pool, the chevron,
the fit, every gesture. A layer-shell window cannot be built without a
compositor ("No PanelWindow backend loaded", measured offscreen), so this
split is what lets the test build the bar's real contents in an ordinary
window.

### A pool of widgets that moves, never rebuilds

`BarStrip` keeps one `BarSlot` (the old per-section slot: plugin loader, hover
highlight, press report, arrange mode's area) per shown widget, in an
`Instantiator` over the shown ids **sorted**, so moving a widget between
sections leaves the pool as it is. `BarSection` keeps only a cell per id, sized
to that id's slot, and registers it; the slot's parent is `hostFor(id)`: the
open overflow panel's cell, else its section's cell, else a zero-size clipped
parking item. An id that leaves the shown set leaves the pool a moment later
(`Qt.callLater`): `shell.qml`'s `moveWidget` sets `bar.left`, `bar.center` and
`bar.right` one at a time, so a cross-section move takes the widget out of
every section in between. Measured before that deferral: `DIED me.b` /
`BORN me.b` in the engine log and a different instance after a move; after it,
the same instance, built once (test below). `ScriptModel` itself emits moves:
reordering `["a","b","c","d"]` to `["d","a","b","c"]` destroyed and built
nothing (scratch probe, `qs` offscreen).

### Widget drag

- **Gesture.** A `DragHandler` on each slot, left button, `target: null`,
  threshold `BarDrag.threshold(Qt.styleHints.startDragDistance)` = 1.5 × Qt's
  drag distance (15 px at Qt's 10). Below it nothing happens: the widget has
  the press. Past it the handler takes the exclusive grab, the widget's
  `MouseArea` gets `canceled` (no click). The handler sits on the slot, the
  widget's parent, which sees the press after the widget accepts it and only
  watches. Placed in an item above the widget (as the press-reporting
  `PointHandler` is) it swallowed presses whenever it was the only enabled
  handler there: a scratch QML probe logged `point arr-press arr-click | |
  point arr-press arr-click`, the middle click (DragHandler alone) reaching
  nothing; on the slot it logged `widget1 widget2 wheel | wcancel dragtrue
  dragfalse | widget1 | arrange arr-press arr-click arr-press dragtrue
  dragfalse`.
- **Widgets with drags of their own** keep them (measured with the fixtures
  below). Qt delivers a move to the exclusive grabber before passive
  grabbers, and an item holding
  `keepMouseGrab` (a `MouseArea` with `drag.target` once its drag starts at
  Qt's smaller distance, one with `preventStealing`, a Controls `Slider`)
  refuses the takeover; a native widget can also set `readonly property bool
  barDraggable: false`. No built-in bar widget has its own drag (grep of every
  bar-widget entry for `drag.target|preventStealing|DragHandler|Slider`); the
  tray never moves (`fixedIds`).
- **Live room.** The lifted widget's cell folds away (its ghost follows the
  pointer) and the section the drop would land in gets a room of the widget's
  length in front of the target (`BarDrag.rows`), outlined in `Theme.accent`;
  the section's other cells glide aside (a 120 ms `move` transition set only
  while a drag lasts).
- **Ghost.** `BarDragOverlay.qml`: a `PanelWindow` on `WlrLayer.Overlay`,
  `ExclusionMode.Ignore`, `mask: Region {}`, keyboard `None`, built by a
  `LazyLoader` only while a drag lasts. It draws the widget's picture
  (`grabToImage`, outlined until it arrives) under the pointer, held where it
  was pressed, at `BarDrag.windowOrigin` + the pointer.
- **Drop targets.** `BarStrip.dropAt`, against the bar as the drag found it
  (`frozen`: each section's spans read at drag start), so the room moving does
  not move the target: in the bar, `Overflow.dropTarget` (unchanged); the
  chevron, which shows during every drag (the right section makes way for it
  as the drag starts, before the bar is measured), or the nook: the panel's
  end; over the open panel's card, `Overflow.panelTarget` (unchanged), marked
  by the panel's accent line. The nook never goes into the panel it opens.
  Out of the panel into the bar the move is pinned (as before).
- **Landing.** After the release has been handled (`Qt.callLater`), `Bar`
  emits `moveRequested`, which `shell.qml` already sends through `haseen bar
  move … --no-apply` (unchanged). A drop where the widget already was writes
  nothing (`Overflow.changes`).
- **Cancel.** Letting go anywhere that is no target, Escape, a grab the
  compositor takes away (`DragHandler.canceled`), the bar hiding, or the
  dragged widget going away: nothing saved. For Escape the bar takes the
  keyboard (`WlrKeyboardFocus.Exclusive`) while a drag lasts and only then; a
  drag that hears nothing for 15 s ends (a marked single-shot timeout,
  restarted by each pointer move), so a release the compositor never delivers
  cannot keep the keyboard. Escape in the open overflow panel cancels a drag
  before it closes the panel.
- **Fit.** The overflow fit waits while a widget is dragged and runs once it
  lands, so nothing moves into or out of the panel under the pointer.

### Bar move

A `MouseArea` under the sections, left button, `pressAndHoldInterval: 200`,
that lets go of any press over a widget, the chevron or the nook
(`onEmpty`). A 200 ms hold, or a drag past the threshold, lifts the bar; the
edge nearest the pointer on the bar's screen (`BarDrag.edgeAt`, Omarchy's
diagonal rule) is drawn as a bar in the overlay; letting go there emits
`positionRequested`, which `shell.qml` already sends through `haseen bar
position --no-apply`. A short press moves nothing; the double-click
`PointHandler` (transparency) and the right-click `MouseArea` (arrange) are
unchanged and forget a press that began a drag. **Multi-monitor:**
`bar.position` stays one value for every screen; the pointer's place on the
screen of the bar being dragged picks the edge, and every bar moves. A widget
dragged from one screen's bar onto another's is no drop (the compositor keeps
the pointer with the source surface); the layout is shared anyway.

### Arabic

The bar is never mirrored (plan 109, `docs/architecture.md` §5.8), and nothing
here reads the layout direction: the scenario test runs in Arabic and in
English and requires identical results. No new interface string (`tools/i18n.py
extract` changed nothing; `check` passes).

### Arrange mode: kept, no longer needed to reorder

It still opens the panel (even empty), outlines widgets, and a click moves a
widget between the bar and the panel; the panel shows the four edge buttons.
Its own drag code is gone: the slot's `DragHandler` drags in both modes (its
area no longer keeps the mouse). `haseen bar arrange`, the right click on
empty space and the chevron, the nook's right click, Style › Bar › Arrange
widgets and the IPC answer as before; the help of `haseen bar arrange`, `move`
and `position` now names the drags.

## Rejected

- **Omarchy's press model** (the bar takes every press and replays the click
  through `triggerPress`): every haseen widget, and the Omarchy 4.0.6 and DMS
  widgets it hosts, handles its own presses, hover, wheel and double clicks;
  replaying clicks would change all of them.
- **Omarchy's 4 px threshold**: there the bar owns the press. Here a click
  that slips 5 px would become a drag and cancel the widget's click, and a
  widget's own drag (starting at Qt's 10 px) would lose to the bar's.
- **The drag handler above the widget**: measured to swallow presses (above).
- **Removing arrange mode**: the nook's right click, the menu row, scripts
  calling `haseen bar arrange`, click-to-move (easier than a drag on a
  touchpad) and the edge buttons would go with it.
- **Moving the bar live during the drag**: every window would be laid out
  again on each pointer move; the overlay previews the edge instead.
- **Opening the drawer when a drag rests on the chevron**: not done; a drop on
  the chevron lands at the panel's end, and with the panel open first (the bar
  is inside its focus grab) a drag places a widget anywhere in it.
- **A chevron over the bar's end that the right section ignores**: it would
  cover the last widget; the section makes way as the drag starts.

## Tests and gates

- `tests/test-bar-drag.sh` (new, `# haseen:covers` the bar's QML/JS, the three
  `haseen bar` commands, `BarButton`, `OmarchyHost`, `DmsHost`): 117/117.
  34 JS units (threshold, edges, window origin, room rows, `Overflow.changes`);
  `Bar.qml`'s window wiring from the source (keyboard only while dragging,
  Escape, the lazy overlay, its empty mask and layer, the panel's Escape, the
  marked timeout); `BarStrip` in the real Quickshell engine, offscreen, twice
  (Arabic, then English, identical), with 12 fixture widgets, the real tray and QtTest's
  `TestEvent`: left, right, middle clicks and the wheel on a native,
  BarButton, TapHandler, Omarchy-hosted and DMS-hosted widget; a press moving
  6 px stays a click; double clicks; drag within a section (room, folded cell,
  cancelled press, ghost, the move), across sections (same instance, built
  once, nothing destroyed), onto the chevron, out of and into a stand-in
  overflow panel (the real `BarOverflowCell`s), cancel by letting go off the
  bar and by Escape's path; `drag.target`, `preventStealing`, a `Slider` and
  `barDraggable: false` keep their drags; hold and threshold bar moves (top to
  bottom, a left bar to the right), a short press and Escape's path move
  nothing; right click arranges, arrange mode's click and drag; then every
  drop replayed through `haseen bar move` gives the shell's rule's bar.
- `tests/test-bar-basics.sh`: its two source checks read `BarStrip.qml` now.
- Affected selection, lint, docs and secrets: numbers in the pull request.

## Owner steps

Shell only; no `hyprctl reload`. After the deploy (which restarts
`haseen-shell`):

1. Press and drag a widget along the bar: the others make room, a ghost
   follows; let go. Drag one into another section, onto the chevron, and,
   with the drawer open, into and out of it. Press Escape during a drag, and
   let go of one off the bar: nothing changes.
2. Click, scroll, right-click and middle-click several widgets (workspaces,
   audio, media, clock, network, the tray): as before. A click that slips a
   little stays a click.
3. Hold empty bar space for a moment and drag toward another edge; let go.
   Double-click empty space (transparency) and right-click it (arrange mode).
4. After a drag, check the keyboard is back where it was (the bar holds it
   only during a drag).

Not verifiable here: the compositor's pointer grab across the bar and the
drawer windows, the overlay window and its picture, the keyboard during a
drag, two screens.
