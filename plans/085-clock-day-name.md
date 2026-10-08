# Plan 085: Clock day-name toggle

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (one optional boolean setting; live UI and user-config write)
- **Depends on**: 021, 027, 076
- **Planned at**: 2026-10-08, owner request
- **State**: DONE 2026-10-08 (`tests/test-clock-dayname.sh`: 32 assertions and 28 Qt JS cases; `tests/test-widgets-a.sh`: 64 assertions); nested screenshots captured and inspected

## Change

- `haseen.clock` adds the optional boolean `showDayName`. With the setting absent, the clock keeps following its `format` or `verticalFormat` exactly as before. When true, the clock adds `dddd` only if the source format has no day-name token (on its own line in a vertical bar); when false, it removes only Qt-tokenized day names and one associated separator while preserving numeric-day tokens and the stored source format.
- The calendar panel reads the current effective clock setting and adds a compact `Day name` row with the shared `Pill` at the bottom. It is pointer- and keyboard-reachable; toggling updates `Config` immediately and persists only `showDayName` through the existing `haseen plugin settings` CLI.
- `qs.Haseen.ClockDayName` exposes a quote-aware JavaScript formatter to both built-in widgets, including user plugin overrides, without importing one plugin directory from another. It follows Qt's decomposition of longer `d` runs and preserves quoted literals and unrelated punctuation.

## Evidence

- `share/haseen/shell/plugins/haseen.clock/manifest.json:6,24-27`: description and optional boolean setting (no default).
- `share/haseen/shell/plugins/haseen.clock/Widget.qml:17-25`: effective horizontal/vertical format and live clock text.
- `share/haseen/shell/Haseen/ClockDayName.js`: quote-aware Qt `d`-run tokenization, numeric-day preservation, scoped separator cleanup and vertical prefix.
- `share/haseen/shell/Haseen/ClockDayName.qml` and `share/haseen/shell/Haseen/qmldir`: shared formatter and long-lived settings singletons.
- `share/haseen/shell/plugins/haseen.calendar/Panel.qml`: initial state from the effective clock setting and bottom toggle row with Tab/Space/Enter support.
- `share/haseen/shell/Haseen/ClockSettings.qml`: shell-lifetime write queue; the newest requested value stays effective across config reloads until its write succeeds, while a failed final write releases the override if no newer request remains.
- `share/haseen/shell/plugins/haseen.clock/Widget.qml`: apply the pending setting override when deriving the live format.
- `tests/test-clock-dayname.sh`: 28 Qt JS cases and real-engine calendar/clock tests for delayed panel teardown, intermediate queued-write reloads, an earlier failed write with a newer request queued, and final nonzero/cannot-start failures followed by external settings reloads and panel recreation.
- `tests/test-widgets-a.sh` (64 assertions): existing clock/calendar widget contract.

## Nested proof

Ran nested proof under `flock ~/.cache/haseen-wt/nest.lock` with `tools/nest-launch.sh`. Used the NEST signature to disable `WAYLAND-1` and confirmed only the headless `IO` output remained before capturing frames.

Captured and visually inspected:

- `bar-day-on.png`: the bar shows `Thursday 12:18`.
- `panel-day-on.png`: the calendar panel shows the `Day name` toggle On and the day name in the bar.
- `panel-day-off.png`: the toggle is Off and the bar shows only `12:18`.
- `bar-day-off.png`: the bar shows only `12:18`.

Stopped the nested processes and removed the runtime/config scratch; only these requested images remain under `~/.cache/haseen-wt/scratch-clock-dayname/shots/`.

## Rejected

- Changing the saved `format` / `verticalFormat` on every click: that would overwrite the user's chosen Qt format and make turning the day name back on lossy. Keep the source format and derive the displayed format.
- Giving `showDayName` a true or false default: either default would change existing bars. An absent value instead preserves the current format-driven display.
- Owning the process queue in the calendar panel: closing the popup destroys it and can cancel an accepted write. Keep the service in the shell's Haseen singleton instead.
- Writing `shell.json` directly from the panel or adding another persistence endpoint: reuse `Config.setRuntime` for the immediate update and the existing lock-safe `haseen plugin settings` CLI for persistence.
- Keeping the optimistic override after a failed final write: with no write pending, that stale value would override later saved settings. Release it only when the queue is empty; preserve it if a newer request remains.
