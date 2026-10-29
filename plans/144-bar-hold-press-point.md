# Plan 144: holding a bar widget starts its edit again

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One property read in `share/haseen/shell/BarSlot.qml`. A
  press that was throwing now arms plan 126's 700 ms hold, as plan 126 meant.
- **Depends on**: 126 (hold a bar widget to edit it)
- **Category**: shell
- **Planned at**: 2026-10-29, found in luna's shell journal while looking
  into plan 143
- **State**: DONE 2026-10-29 (`tests/test-bar-drag.sh` 129/129; 126/129
  with the old `BarSlot.qml`)

## Problem

luna's journal for `haseen-shell.service` held 74 lines of
`WARN scene: @BarSlot.qml[175:-1]: ReferenceError: centroid is not defined`
from 2026-10-28 00:00 to the morning of 2026-10-29
(`journalctl --user -u haseen-shell | grep -c 'centroid is not defined'`), one
for each press on a bar widget. Line 175 is in the slot's `PointHandler`:

```qml
onActiveChanged: {
    if (active) {
        slot.host.reportPress(slot);
        if (centroid.pressedButtons & Qt.LeftButton)
            hold.restart();
```

`centroid` belongs to the multi-point handlers (`DragHandler`, the slot's
other handler, reads it at lines 202 and 209). `PointHandler` is a single-point
handler and has `point` instead, which the hold timer already reads
(`const p = press.point;`, line 157). So the read threw, `hold.restart()` never
ran, and holding a widget never started plan 126's edit. `reportPress` runs
first, so presses still reached panel placement and nothing else looked
wrong.

Plan 126's test checked the source text, `centroid.pressedButtons &
Qt.LeftButton` (`tests/test-bar-drag.sh:155` before this change), so it held
the bug in place.

## What changed

- `BarSlot.qml:175` reads `press.point.pressedButtons`.
- `tests/test-bar-drag.sh`: the real-engine scenario ends with a left press
  held still on `me.b` for 900 ms, with `haseen` stubbed to record its
  arguments for the two scenario runs (Arabic, English) and removed before the
  CLI checks that need the real command. It asserts that arrange mode is off
  at the hold, that `haseen-calls` reads `bar edit me.b` once a run, and that
  the run's output has no `ReferenceError`. The source check names the fixed
  read.

## Rejected options

- **`hold.restart()` without the button check.** A right press opens arrange
  mode and a middle press is the widget's; plan 126 keeps the hold to the left
  button.

## Tests

- `tests/run.sh tests/test-bar-drag.sh`: 129/129. With the old `BarSlot.qml`
  and the new test: 126/129 (the source check, the recorded edit and the
  `ReferenceError` check fail).
