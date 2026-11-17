# Plan 172: a Caps Lock warning on the lock screen

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One line under the password field, shown only while Caps
  Lock is on. One `hyprctl -j devices` read when the lock opens and on a
  Caps key press, no timer.
- **Depends on**: 010 (lock), 109 (interface language), 173 (CapsLock is Caps Lock)
- **Category**: shell
- **Planned at**: 2026-11-14, from the owner (sent lucid's repository, "what
  could be good to take", then "go")
- **State**: PLANNED 2026-11-14. Plan 173 dropped `compose:caps`, so the
  Caps key turns Caps Lock on in a default install and the warning matters.

## Problem

A password typed with Caps Lock on fails as "Wrong password" with no hint.
Lucid's lock shows a Caps Lock chip, read from the main keyboard in
Hyprland's device list (MIT, Sn3akyy1/lucid at d1bcf8a,
`Lockscreen.qml:620-633`, `lucidlock/LockAuthCard.qml:241-248`).
haseen's lock has no such line (`haseen.lock/LockView.qml:122-207`).

- Until plan 173 haseen's Hyprland input set `kb_options = "compose:caps"`,
  so Caps was Compose and this warning had nothing to show. Plan 173 dropped
  it: CapsLock is Caps Lock on a default install. With keyd, a tap is still
  Escape and a hold the hyper layer (`share/haseen/default/keyd/default.conf:8-9`,
  plan 160), and RightAlt + CapsLock is Caps Lock.
- haseen already parses the state: `Keyboard.lockState(text)` returns
  `{caps, num}` from `hyprctl -j devices` (`share/haseen/shell/Haseen/Keyboard.qml:63-67`,
  `Keyboard.js:213-220`). Its one caller is the OSD, fed by a release bind on
  `code:66` (`share/haseen/default/hypr/binds.lua:205-208`) that has no
  `locked = true`, so it cannot fire while the session is locked.

## Decision

- `haseen.lock/Service.qml` keeps `capsLock`, read with one `hyprctl -j
  devices` `Process` and `Keyboard.lockState`: when the lock opens, and when
  `LockView`'s field sees `Qt.Key_CapsLock` (the lock surface has the
  keyboard, `LockView.qml:158-159`). No timer; architecture §6 is untouched.
- `LockView.qml` shows "Caps Lock is on" under the field while it is true,
  in the preview banner's place and type (`:200-207`, `Theme.warning`,
  `Theme.font.body`), with `capsLock` passed in both places the view is made
  (`Service.qml:456-465`, `PreviewWindow.qml:29-39`).
- The preview IPC's `state()` gains `capsLock` (`Service.qml:420-444`).
- One new string, in `share/haseen/i18n/ar/shell.json`.

The reason for a new on-screen element (CLAUDE.md, "No visual clutter"): it
shows only while Caps Lock is on, on the lock screen, where a wrong-case
password is otherwise a mystery.

## Rejected

- **Polling the LED** (`/sys/class/leds/*::capslock/brightness`): sysfs does
  not notify that file (`haseen.osd/Service.qml:196-201`), so it needs a
  sampler, and the lock is exactly when nothing else is happening.
- **Adding `locked = true` to the OSD's lock-key bind**: it would run
  `haseen shell ipc` on every Caps press for everyone, OSD setting on or
  off, to serve the lock.
- **Showing it inside the field as the placeholder** (`LockView.qml:170-181`):
  the placeholder disappears as soon as one character is typed, which is
  when the warning matters.

## Evidence (to collect)

- `tests/test-lock.sh` (covers `haseen.lock/**`, `:6`), in its real-engine
  harness (`:41-51`): with a stub `hyprctl` reporting `capsLock: true` the
  line is visible and `state()` says so; with `false` it is hidden; a
  `Qt.Key_CapsLock` press re-reads.
