# Plan 120: A bar drag keeps the pointer — the bar never takes the keyboard

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One surface flag and the Escape shortcut that depended on
  it; the drag state machine is unchanged.
- **Depends on**: 112, 118
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (pull request; the live drag is verified on IO)

## What went wrong

Plan 112's bar took exclusive keyboard focus for as long as a drag lasted, so
Escape could cancel it (`Bar.qml`: `keyboardFocus: strip.dragging ?
WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None`). On io a layer surface
that switches to exclusive focus mid-gesture makes Hyprland drop the pointer
grab: every drag armed and then ended in the same second, so nothing moved.
The owner saw exactly that — "it invokes the drag animation and the border and
disconnects".

With the focus switch disabled the same gesture completed. The live shell
logged, 2026-10-25 13:24:34:

```
haseen-drag: handler true t1nk33r.nettraf draggable true threshold 12
haseen-drag: begin t1nk33r.nettraf 922.83 16.97 dragging false
haseen-drag: move t1nk33r.nettraf 1233.06 {"section":"right","before":"haseen.omarr","at":1233.06}
haseen-drag: land t1nk33r.nettraf dragId t1nk33r.nettraf drop {"section":"right","before":"haseen.omarr","at":1233.06}
haseen-drag: changes t1nk33r.nettraf right haseen.omarr true true
```

Before that change every attempt logged `handler true` and `handler false` in
the same second, with no `move` in between.

## What changed

- `Bar.qml`: `WlrLayershell.keyboardFocus: WlrKeyboardFocus.None`, always,
  with the measurement in the comment. The Escape `Shortcut` that could never
  fire is gone.
- Escape still cancels a drag started from the overflow panel: that window has
  the keyboard and its own Escape handler already calls
  `barWindow.cancelDrag()` (`BarOverflowPanel.qml`). A drag nothing finishes
  ends on the strip's 15 s watchdog.
- `docs/architecture.md` §5's drag paragraph says where Escape works now.
- `tests/test-bar-drag.sh`: asserts the bar never takes the keyboard and that
  no mid-drag focus switch comes back; the old "Escape during a drag cancels
  it" assertion is gone.

## Evidence

- The log excerpt above, from the instrumented live shell on io.
- `tests/test-bar-drag.sh` and `tests/run.sh --affected` in the PR.

## Rejected options

- **`WlrKeyboardFocus.OnDemand` during a drag**: still a focus change
  mid-gesture, and whether Hyprland grants it without dropping the grab is
  unproven; the bar does not need the keyboard to move a widget.
- **A compositor bind for Escape**: it would take Escape from every
  application for the whole session to cancel one drag.
- **Keeping the Shortcut anyway**: it can only fire on a focused window, and
  a focused bar drags nothing.
