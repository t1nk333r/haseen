# Plan 082: idle suspend and battery timeouts

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (suspend is off by default; the defaults are unchanged)
- **Depends on**: 019, 062, 075
- **Category**: shell, power
- **Planned at**: 2026-10-07, gap 8 of `docs/reference-shell-gaps.md`
- **State**: DONE 2026-10-07 (`tests/test-idle.sh`; nested proof with a stub suspend)

## Change

- `haseen.idle` gains `suspendAfter` (seconds, **0 = never, the default**): a fourth ext-idle-notify monitor
  whose idle edge runs `haseen-system suspend`, the command behind the menu's System › Suspend, by absolute
  path like the battery plugin's critical action (`Service.qml:99`).
- `onBattery` (default `{}`) holds any of `screensaverAfter`, `lockAfter`, `dpmsAfter`, `suspendAfter`; each
  valid number replaces the AC value while UPower's `onBattery` is true. A missing, null or invalid key keeps
  the AC value; 0 turns that monitor off on battery (`IdleLogic.js:16` `effective`). `UPower.onBattery` is a
  D-Bus property binding (`Service.qml:47`), so plugging in or out re-evaluates `timeouts`, and the
  string-keyed monitor model recreates only the monitors whose timeout changed. The screensaver-before-lock
  rule applies to the merged values.
- Gating (`IdleLogic.js:53,78`): the `idle-off` flag (Stay Awake, `haseen toggle idle off`, and the game
  and present contexts of plan 062, which set the same flag) removes every monitor, as before; `actions`
  also returns nothing for an idle suspend monitor once `idleOff` is set, for the moment between the flag
  and the monitor's removal. The suspend monitor is always created with `respectInhibitors: true`, even when
  the setting is false: no suspend under a playing video.
- DPMS bookkeeping (`Service.qml:49-54`) is now documented for plan 084: `_dpmsOff` is true only between the
  dpms monitor turning the displays off and turning them on; `dpms.on` is only sent when it is set.
- `haseen setup idle [status|prompt [--battery]|set [--battery] KEY SECONDS|unset --battery KEY]`
  (`bin/haseen-setup-idle`): KEY is screensaver, lock, dpms or suspend. `status` prints the AC and battery
  columns; `prompt` asks for each value in a floating terminal (Enter keeps; `-` on battery follows AC
  again); writes go through the shell.json lock and atomic write (`shell_config_lock`,
  `shell_config_write`). Menu Setup › Idle and Suspend: Status, Timeouts on AC, Timeouts on Battery (only
  where `haseen battery status` finds a battery).
- `haseen toggle idle --help` and its summary say Stay Awake also holds off suspend.
- Spec naming: the gap text's `{dimAfter, lockAfter, screenOffAfter, suspendAfter}` maps to haseen's
  existing names (`screensaverAfter`, `lockAfter`, `dpmsAfter`); haseen has no dim step.

## Evidence

- `tests/test-idle.sh` (63): the manifest defaults; in Qt's JS engine the timeout selection (AC vs battery,
  partial override merge, battery-only suspend, 0 = off on battery, null/invalid/non-object overrides
  ignored, only timeout keys overridden, idle-off wins on battery, the user's object not mutated) and the
  gating (suspend action, none under idle-off, suspend keys always `:1`, no suspend monitor by default, a plug
  changes only the overridden keys); `haseen setup idle` status, set, `--battery`, unset, prompts through a
  pipe with retries, `--dry-run` purity, refusals, unrelated settings kept, a broken shell.json left alone.
- `tests/test-ambient.sh` (242) still passes: the old idle table is unchanged with suspend 0.

## Nested proof

`~/.cache/haseen-wt/scratch-idle/proof.log`: the worktree shell in a nest on a private system bus with
`tools/fake-upower.py`, `systemctl` stubbed first on the shell's PATH (the stub only appends to
`stub.log`), `suspendAfter` 8 and `onBattery.suspendAfter` 4, input from `tools/vptr`.

1. AC: no call 6 s after input, one call 8.0 s after it.
2. `OnBattery=true` from the fake: monitors become `suspend:4:1` live; the call comes 4.0 s after input.
3. An xdg-toplevel `IdleInhibitor` client: no call in 20 s; a call 7.9 s after the client exits.
4. `respectInhibitors: false` with the inhibitor: no call in 16 s.
5. `haseen toggle idle off`: monitors `[]`, no call in 14 s; after `on`, a call again.
6. `haseen context game`: monitors `[]`, no call in 14 s; after `haseen context normal`, a call again.

`shots/menu-setup-idle.png`: Setup › Idle and Suspend in the nest (no battery row: the host has none).

Found on the way: Hyprland counts idle inhibitors only on **windows**. An `IdleInhibitor` on a layer-shell
`PanelWindow` did not stop the suspend (`shots/inhibited.png`, the call at 8 s regardless); the same
inhibitor on a `FloatingWindow` did. Video players and browsers inhibit from their toplevels, so the
practical case holds; a shell-side inhibitor would have to sit on a window.

## Not verified

- A real suspend and resume (never run; the stub stands in for `systemctl suspend`).
- The real UPower on a laptop being unplugged (the fake emits the same `OnBattery` property change).

## Owner decisions

- **Audio playing**: haseen does not hold off idle for audio alone (nor did it for the lock or screensaver).
  Browsers and mpv inhibit while video plays; music in a player without an inhibitor would not stop a
  suspend. Adding an MPRIS "playing" gate is a separate change.

## Rejected

- **A shell Timer for suspend**: ext-idle-notify already counts in the compositor and knows the inhibitors.
- **systemd-logind `IdleAction`**: system-wide config, root-owned, blind to Stay Awake and the contexts.
- **Honouring `respectInhibitors: false` for suspend**: that setting exists for lock-under-video; a suspend
  under a playing video loses work.
- **New key names (`dimAfter`, `screenOffAfter`)**: a second vocabulary for the same settings.
