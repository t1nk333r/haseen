# Plan 118: The bar's drag ghost reads the drag again

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One property's name in the drag's overlay window; the drag
  state itself is unchanged.
- **Depends on**: 112
- **Category**: shell
- **Planned at**: 2026-10-25
- **State**: DONE 2026-10-25 (pull request; the live drag on IO is an owner step)

## What went wrong

`Bar.qml` creates the drag's window as

```qml
BarDragOverlay {
    screen: bar.screen
    strip: strip
}
```

`BarDragOverlay` declared `required property var strip`. Inside the object's
own scope that name resolves to the property being defined, not to `Bar.qml`'s
`BarStrip` id, so the binding was `strip = strip` and the overlay held
`undefined`. Every read of the drag's state then threw, in the live shell on
io on 2026-10-25 at 12:24:53 and 12:24:56:

```
WARN scene: @BarDragOverlay.qml[18:-1]: TypeError: Cannot read property 'dragId' of undefined
WARN scene: @BarDragOverlay.qml[38:9]: TypeError: Cannot read property 'dragScreenAt' of undefined
WARN scene: @BarDragOverlay.qml[69:-1]: TypeError: Cannot read property 'barMoving' of undefined
```

The drag itself still armed (the window is created from `strip.dragging`), so
the widget's slot dimmed, but neither the ghost nor the edge preview appeared:
a drag looked like nothing had been picked up.

## What changed

- `BarDragOverlay.qml` declares `required property var stripItem` and reads
  `stripItem.*`; `Bar.qml` passes `stripItem: strip`.
- `tests/test-bar-drag.sh` asserts the call site hands the strip over and that
  the overlay does not declare a property named after the id. Plan 112's test
  builds `BarStrip` directly (Bar.qml is a layer-shell window and is read from
  the source), which is how a broken binding at the call site went unseen.

## Evidence

- `tests/test-bar-drag.sh` 119/119, including the two new assertions.
- `grep -n 'stripItem' share/haseen/shell/Bar.qml
  share/haseen/shell/BarDragOverlay.qml` shows the single binding and its reads.

## Rejected options

- **Rename `Bar.qml`'s id**: the id is used throughout the file and by the
  overflow panel's callbacks; renaming the one property is the smaller change.
- **`strip: bar.strip` by another name**: the id is the same object; the
  problem was the property's name, not where it came from.
