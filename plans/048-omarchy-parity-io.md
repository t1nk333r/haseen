# Plan 048: Omarchy parity on the first migrated machine

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM (rewrites a user's shell and Hyprland files, behind backups)
- **Depends on**: 016 019 031 036
- **Category**: desktop
- **Planned at**: 2026-10-06, owner request after the first boot of io into haseen
- **State**: DONE 2026-10-06 (real swipes and the boot handover need the owner's eyes)

Numbered 048, not 037: plans 037–047 exist as uncommitted work on luna.

## Problem

io (Omarchy 4 laptop, switched in place, plan 036) booted into haseen. The
owner reported five gaps against what Omarchy gave them:

1. the Plymouth password showed bullets, they want `*`;
2. a wall of text sat between the splash and the desktop;
3. their Omarchy bar, plugins and settings did not come along;
4. Omarchy's three menus were not on Omarchy's keys;
5. no trackpad gestures (they used the omagesture plugin).

## Decision

**1. Asterisks** — `share/haseen/default/plymouth/haseen.script` draws `*`.

**2. Text wall.** Read from io's VT text buffer (`/dev/vcs1`) after boot: it
was uwsm's start-up narration ("Selected compositor ID…", "Created unit
subdir…"), printed onto VT 1 because greetd's sessions run there. Two fixes:
- session start-up output goes to the journal: the greetd command is
  `systemd-cat -t uwsm uwsm start hyprland.desktop`, and the greeter launches
  `["systemd-cat","-t",<session id>, …argv]`;
- the splash hands over the way GDM does: greetd's drop-in conflicts with
  `plymouth-quit.service` and runs `plymouth quit --retain-splash` itself, so
  the last splash frame stays until Hyprland's first frame instead of plymouth
  clearing to the text console first. Rejected: `After=plymouth-quit-wait`
  (what 036 shipped): it is exactly the order that shows the console.
  **Reverted 2026-10-06:** the `Conflicts=plymouth-quit` / `--retain-splash`
  drop-in deadlocked boot on io and was patched out of the installed copy there.
  The drop-in is back to `After=plymouth-quit-wait.service`; the text-wall fix
  rests on the journal redirection above.

**3. `haseen import omarchy`** (`bin/haseen-import-omarchy`,
`share/haseen/lib/omarchy-import.sh`). Reads `~/.config/omarchy` (never writes
it) and translates: the bar layout in order (Omarchy built-ins mapped to
haseen's, third-party plugins kept under their ids with their settings, the
omagesture widget mapped to `haseen.gestures`), idle timeouts, branding text,
hooks whose events haseen fires, custom themes, and the pre-switch Hyprland
files (`o.bind` → `haseen.bind`; Omarchy-only commands skipped and reported).
An existing non-empty `shell.json` is only changed with `--merge`, and every
replaced file gets a timestamped backup. Built-ins with no haseen widget
(Omarchy's menu button, indicators, keyboard-layout, system-update) are
reported, not invented.

**4. Menus** on Omarchy's keys: `SUPER + SPACE` main menu, `SUPER + SHIFT +
SPACE` apps launcher, `SUPER + ESCAPE` system menu (screensaver, lock,
suspend, hibernate, logout, reboot, shutdown — Omarchy's seven, in its order).
Displaced: bar toggle → `SUPER + ALT + SPACE`, close panel → `SUPER + CTRL +
ESCAPE`. Hibernate is listed only when `haseen hibernation status` says ready;
`bin/haseen-system` had its own check that counted zram as swap.

**5. Gestures.** omagesture (MIT, Pedro Henrique) ported as the native
`haseen.gestures` plugin + `haseen gestures apply`, which renders
`~/.local/state/haseen/toggles/hypr/gestures.lua`. Defaults are the owner's
mapping (3 fingers sideways = workspace, 4 fingers = resize, natural scroll,
clickfinger, middle-drag moves). Installed by default on touchpad machines: the
`gestures` hardware quirk matches a touchpad in `/proc/bus/input/devices` by
capabilities (not by name), applies the default once, and sets the
`flags/gestures` flag that shows the widget — the user's `shell.json` is not
edited.

**6. Lock screen ignored Enter** (reported live; the owner escaped to tty2).
Reproduced in a nested Hyprland with `wtype`: typing showed dots, Enter did
nothing. Instrumented, the cause was two bugs in `haseen.lock`, neither of
which the preview-mode tests could reach:
- `locked` was a binding on `WlSessionLock.locked`, which Quickshell 0.3 does
  not notify when assigned from JS. It stayed false for the whole lock, so
  `submit()` returned early. Now `lockRequested || secure || previewShown`.
- PAM's "Password:" prompt was answered from both `pamMessage` and
  `responseRequiredChanged`; the second call aborted as "Unsupported PAM
  prompt", so even the right password could not unlock. Now `pamMessage` only.
After the fix, in the same nested setup: a pam_permit service unlocks on Enter,
and the real `login` service answers a wrong password with "Wrong password".
fcitx5 (`QT_IM_MODULE=fcitx`) was suspected first and ruled out with a probe.
`haseen lock release` is the way out of a stuck lock from a TTY: it lets a
new lock client take over, takes the lock and releases it — used on io.
The polkit dialog had a related focus hole: its field starts disabled until
polkit asks, so the completion-time focus was lost; it now takes focus when
enabled.

**7. Two watchers** (owner request: "lock screen app died" recovery, and
Omarchy's crash → AI diagnosis):
- Lock-client death: the shell records `$XDG_RUNTIME_DIR/haseen-lock-held`
  while it holds the session lock; systemd restarts a crashed shell
  (`Restart=on-failure`), and the new instance retakes the lock
  (`misc.allow_session_lock_restore`, already in haseen's defaults). Proven in
  a nested Hyprland: lock, `kill -9` the shell → Hyprland's "Oopsie daisy …
  lockscreen app died" screen; start the shell → the haseen lock screen is
  back with a password field. `haseen lock release` clears the marker.
- Crashes: `bin/haseen-crash-watch` + `haseen-crash-watch.service`, ported
  from `omarchy-crash-watch`: each core dump of one of the user's programs
  (systemd-coredump's journal entry) becomes one critical notification,
  "Diagnose" runs `haseen agent crash` (plan 033). Silent without a default
  agent, for other users, for itself, and within 60 s of the same program.
  `tests/test-crashwatch.sh` (12).

**8. Follow-ups after the import was live on io.**
- Moon phase in the calendar panel: only the moon part of the owner's retired
  waybar clock (waydots `.config/waybar/scripts/clock-moon.sh`, retired in
  `780cc23`): `haseen.calendar/Moon.js`, same synodic formula, a line under the
  month title (`settings.moon`, default on). Checked against published phases
  (Jan 2024 new, first quarter, full) in `test-widgets-a.sh`.
- The owner compared Omarchy's OmaStats with haseen's own CPU/GPU/RAM widget
  and kept haseen's: the import maps `crmne.omastats` to `haseen.sysusage` in
  the same bar slot.

## Verification

Tests: `test-gestures.sh`, `test-omarchy-import.sh`, `test-keybinds.sh` (the
real `init.lua` under a stub `hl`: the three keys, no duplicate combo, every
bind described), `test-menu.sh` (system menu rows and every action dry-run),
`test-greeter.sh`, `test-desktop.sh`, `test-hardware.sh`. The generated
gestures file passes `Hyprland --verify-config`. Numbers and the live results on
io are in the execution record.

## Execution record

Filled at merge; see the PR.
