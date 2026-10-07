# Plan 061: shell recovery and safe mode

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: LOW (the shell unit changes how it restarts; everything else runs only after a failure or on request)
- **Depends on**: 005 011 048
- **Category**: shell, plugins, reliability
- **Planned at**: 2026-10-07, round 9 task. The idea comes from aphotic-hypr's description only. That project is GPL, so none of its code or text was read.
- **State**: DONE 2026-10-07. Proof: `tests/test-recovery.sh` (fixture journals, the offer and its fixes, the last good `shell.json`, safe mode in the real Quickshell engine) and nested-session screenshots. The OnFailure path on the owner's real systemd user manager is an owner check.

## Problem

A plugin that breaks the shell leaves an empty screen. `haseen-shell.service`
restarted it every 2 s for as long as the start limit allowed
(`share/haseen/systemd/user/haseen-shell.service` before this plan), then
stopped. Nothing said which plugin did it or how to get the desktop back.
Getting it back meant a TTY, `journalctl` and editing `shell.json` by hand.
Third-party plugins are the likeliest cause: Omarchy and DMS plugins run
through compat hosts, QML cannot sandbox them (architecture §5.2
`permissions`), and they change when their authors push.

## Decision

- **Only a crash loop opens the offer.** `haseen-shell.service` sets
  `RestartMode=direct`, `StartLimitIntervalSec=60`, `StartLimitBurst=4` and
  `OnFailure=haseen-shell-recover.service`. With the default
  `RestartMode=normal`, every crash passes through "failed" and would open the
  offer (systemd 254+, `man systemd.service`, `RestartMode=`). With `direct`,
  one crash just restarts the shell. Four failures within 60 s leave the unit
  failed, and only then does `OnFailure=` start the recovery unit.
- **The recovery unit** (`share/haseen/systemd/user/haseen-shell-recover.service`)
  runs `haseen shell recover present`. `install.sh` installs it with the other
  user units (its loop over `share/haseen/systemd/user/*`). It is never
  enabled. It is `Type=simple`, so the unit stays active while the offer is
  open, and a new failure in that time does not open a second offer.
- **The suspect** (`find_suspect` in `bin/haseen-shell-recover`) comes from
  the last 300 lines of this boot's journal for the unit
  (`journalctl --user -u haseen-shell.service -b -o cat`). Each plugin that
  `plugin_index` finds is matched by:
  - its directory, because QML errors carry file URLs, for example
    `file:///…/plugins/me.broken/Widget.qml[10:-1]: TypeError` from the
    nested run below;
  - its id as a whole word, because haseen's own warnings name ids. A
    neighbouring id with a suffix (`me.broken-extra.v2`) does not match.

  A plugin that is not built in beats a built-in, and after that a later
  mention beats an earlier one. Built-ins ship tested with haseen, and the
  last lines before the exit are the likeliest cause. The record goes to
  `~/.local/state/haseen/recovery/last-failure.json`: time, suspect (id,
  directory, origin, the line) and the last 12 lines.
- **The offer is a floating terminal** (`floating_terminal_exec`, app-id
  `haseen.floating`), not a second Quickshell config. The choices, one key
  each:
  - `d` disables the suspect (`haseen plugin disable`, which edits only
    `shell.json`, never the plugin directory);
  - `s` turns safe mode on;
  - `r` restores the last good `shell.json`;
  - `c` starts the shell as it is;
  - `q` leaves the shell stopped.

  Every fix runs `reset-failed` and `start`, but only when the unit is
  failed. A unit that was stopped on purpose (`haseen shell use dms`) is left
  alone.
- **Safe mode** is the file `~/.local/state/haseen/safe-mode`, holding JSON
  `{reason, since}`. `Haseen/Plugins.qml` watches it with a `FileView` (an
  inotify watch, no polling) and exposes `safeMode`, `safeModeInfo` and
  `held(id)`. `held` is true for every origin except `builtin`: user,
  user:omarchy, user:dms, omarchy and dms. For a held plugin:
  - `entryUrl()` returns `""`;
  - `Config.isEnabled()` returns false;
  - bar sections, services, roles, launcher providers and compat lookups
    therefore drop it at once, with no restart.

  A user copy of a built-in id gives way to the built-in, so safe mode never
  leaves a hole where a built-in would run. `shell plugins` over IPC reports
  `held` per plugin and a `safeMode` object. The shell logs each change.
- **The parent directory must exist** for the watch to see the file appear. A
  qs 0.3.1 check showed this: a `FileView` saw a missing file created, deleted
  and re-created when the directory existed, and saw nothing when the
  directory came later. So `bin/haseen-shell-run` runs
  `mkdir -p "$HASEEN_USER_STATE"` before `exec qs`.
- **The last good `shell.json`.** `bin/haseen-crash-watch` already runs for
  the whole session. It now also asks `haseen shell recover snapshot` every
  5 minutes. A background loop does this; its sleep is killed with it. The
  snapshot is the user `shell.json`, byte for byte, saved as
  `recovery/last-good.json`, and only when all of these hold:
  - the unit has been active for `HASEEN_SHELL_HEALTHY_MINUTES` (default 10);
  - the file has not changed for as long, because a fresh edit has proven
    nothing yet;
  - safe mode is off, because a shell that runs only built-ins proves nothing
    about the rest.

  `restore-last` keeps the file it replaces as `recovery/shell.json.replaced`,
  raw, because a `shell.json` that is not JSON may be what broke the shell.
- **Menu**: `update.recovery` ("Shell Recovery", aliases `recover`,
  `recovery`, `safe-mode`) holds:
  - Safe Mode, a toggle with a ✓ from a file test, so no fork;
  - Last Good Config, shown only when a snapshot exists;
  - Recovery Choices, the offer in a floating terminal.
- **Owner rule (optional features off by default).** Safe mode is off until
  someone turns it on. The recovery unit adds nothing to the screen until the
  shell has already failed. Main should confirm that this counts as part of
  the desktop and not as an optional feature.

## Rejected

- **A minimal Quickshell config for the offer.** Whatever stopped the shell
  (a plugin, Qt, quickshell itself after an update) can stop that config too.
  A terminal also needs Wayland, but nothing from the stack that failed.
- **`OnFailure=` with the default restart mode.** It opens the offer on every
  single crash, even when the restart fixes it.
- **A systemd timer for snapshots.** The task says to reuse
  `haseen-crash-watch`. A timer would also need a unit and a check for the
  shell's start time anyway.
- **Snapshots of the merged config.** The defaults change with haseen
  updates. Only the user's own file is theirs to restore.
- **Dropping held plugins from the registry.** Hosts would then warn "unknown
  plugin id", and `shell plugins` could not show what is held.

## Verification

- `QT_QPA_PLATFORM=offscreen tests/run.sh tests/test-recovery.sh`:
  - suspect detection from the fixture journals in
    `tests/fixtures/recovery/`:
    - a user plugin's file URL beats later built-in mentions;
    - with only built-ins mentioned, the latest one is the suspect;
    - an Omarchy plugin is found by its directory (`omarchy.ticker`, origin
      omarchy);
    - a log that names no plugin gives no suspect and shows its last lines;
  - dry-run purity of `present`, `safe-mode on|off` and `snapshot`;
  - the offer's keys:
    - `d` disables the suspect and restarts the failed unit (a stubbed
      `systemctl`);
    - `s` writes the reason and the time;
    - `r` restores and keeps the broken file;
    - `c` restarts;
    - an unknown key asks again;
    - a unit that is not failed is not started;
  - snapshot rules: uptime, a fresh edit, safe mode, `--force`. The watcher
    asks on its interval and stops asking when it exits;
  - the real Quickshell engine:
    - safe mode on unloads a running user service without a restart;
    - user and Omarchy plugins are held and have no entry;
    - a user copy of `haseen.clock` gives way to the built-in;
    - `describe()` lists the held ids;
    - safe mode off brings it all back.
- Nested Hyprland (`nest-launch.sh`, scratch XDG dirs, private D-Bus,
  `systemctl` and `journalctl` stubbed so the owner's user manager is never
  asked):
  - a fixture plugin `me.broken` (a TypeError on load, then `Qt.exit(1)`)
    made `haseen shell run` exit 1;
  - `haseen shell recover present` on that log opened the floating terminal:
    "Suspect: me.broken (user)", the TypeError line, and `d s c q`;
  - pressing `s` wrote the flag with the reason "the shell kept failing;
    suspect me.broken";
  - a shell started then ran with `me.broken` still listed. Workspaces, clock
    and battery were shown.
  - With `me.broken` disabled, `safe-mode off` showed the third-party
    `me.hello` widget, and `safe-mode on` removed it. The qs PID stayed the
    same throughout. `shell plugins` reported
    `{"safeMode":{"on":true,"reason":"nested proof",…},"held":["me.broken","me.hello"]}`.

## Live apply

1. `./install.sh --tree-only`, so the new command, both units and the QML are
   installed.
2. `systemctl --user daemon-reload`, so `OnFailure=` and `RestartMode=` take
   effect.
3. `haseen shell restart`, so the shell watches the safe-mode file.
4. `systemctl --user restart haseen-crash-watch.service`, so snapshots start.

Owner checks:
- a real crash loop on io opens the offer (for example a plugin that calls
  `Qt.exit(1)` on load, listed in the bar);
- the menu entry Update › Shell Recovery.
