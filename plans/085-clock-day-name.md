# Plan 085: Clock day-name toggle

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (one optional boolean setting; live UI and user-config write)
- **Depends on**: 021, 027, 076
- **Planned at**: 2026-10-08, owner request
- **State**: DONE 2026-10-08 (`tests/test-clock-dayname.sh` (9 checks, 15 Qt JS cases) and `tests/test-widgets-a.sh` (64 checks)); nested UI screenshots not verified (see below)

## Change

- `haseen.clock` adds the optional boolean `showDayName`. With the setting absent, the clock keeps following its `format` or `verticalFormat` exactly as before. When true, the clock adds `dddd` only if the source format has no day-name token (on its own line in a vertical bar); when false, it removes `ddd`/`dddd` and the separator after them without changing the stored source format.
- The calendar panel reads the current effective clock setting and adds a compact `Day name` row with the shared `Pill` at the bottom. It is pointer- and keyboard-reachable; toggling updates `Config` immediately and persists only `showDayName` through `haseen plugin settings`.
- `qs.Haseen.ClockDayName` exposes a pure JavaScript formatter to both built-in widgets, including user plugin overrides, without importing one plugin directory from another.

## Evidence

- `share/haseen/shell/plugins/haseen.clock/manifest.json:6,24-27`: description and optional boolean setting (no default).
- `share/haseen/shell/plugins/haseen.clock/Widget.qml:17-25`: effective horizontal/vertical format and live clock text.
- `share/haseen/shell/Haseen/ClockDayName.js:3-73`: quoted-token detection, `ddd`/`dddd` handling, separators, and vertical prefix.
- `share/haseen/shell/Haseen/ClockDayName.qml:1-18` and `share/haseen/shell/Haseen/qmldir:12`: shared singleton facade for the pure helper.
- `share/haseen/shell/plugins/haseen.calendar/Panel.qml:30-40,249-279`: initial state from the clock and bottom toggle row with Tab/Space/Enter support.
- `share/haseen/shell/plugins/haseen.calendar/ClockSettings.qml:14-60`: immediate runtime update and serialized, lock-safe CLI persistence.
- `tests/test-clock-dayname.sh` (9 assertions): 15 Qt JS format cases plus the real-engine calendar toggle, live clock-format change, persisted false/true values, source-format preservation and keyboard toggle.
- `tests/test-widgets-a.sh` (64 assertions): existing clock/calendar widget contract.

## Nested proof

Not run. The executor environment had no `HYPRLAND_INSTANCE_SIGNATURE`, `XDG_RUNTIME_DIR` or `WAYLAND_DISPLAY`; `tools/nest-launch.sh` requires the owner's compositor signature to start the nested session on workspace 5. No live-shell IPC or compositor commands were attempted. The panel and clock screenshots requested for nested proof were not captured or inspected.

## Rejected

- Changing the saved `format` / `verticalFormat` on every click: that would overwrite the user's chosen Qt format and make turning the day name back on lossy. Keep the source format and derive the displayed format.
- Giving `showDayName` a true or false default: either default would change existing bars. An absent value instead preserves the current format-driven display.
- Writing `shell.json` directly from the panel or adding another persistence endpoint: reuse `Config.setRuntime` for the immediate update and the existing lock-safe `haseen plugin settings` CLI for persistence.
