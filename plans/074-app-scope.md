# Plan 074: apps start outside the shell's cgroup

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (one singleton; app launches change cgroup, not argv)
- **Depends on**: 005 016
- **Category**: shell, apps
- **Planned at**: 2026-10-07, owner report (io): "Every time the shell restarts, Helium and Chromium crash."
- **State**: DONE 2026-10-07 (`tests/test-apps.sh`; nested before/after below)

## Cause

The launcher called `DesktopEntry.execute()` and the menu called
`entry.execute()` and `execDetached(["bash", "-c", action])`. All three are
children of qs, inside `haseen-shell.service`'s cgroup, and the unit has
`KillMode=control-group`, so a restart kills them. Helium is worse:
`/usr/bin/helium-wrapper` does `exec > >(exec cat)` and
`exec 2> >(exec cat >&2)`, then execs helium, which can move itself into an
`app-org.chromium.Chromium-PID.scope`. The two `cat` readers of its stdout and
stderr stay in the shell's unit. The restart kills them, the browser's next
stderr write hits a broken pipe, and it dies with SIGTRAP (io coredumps at
13:55:54 and 15:07:51, under 1 s after the unit stopped). A Chromium started
outside the shell survived four restarts.

## Change

- `share/haseen/shell/Haseen/Apps.qml`, a `qs.Haseen` singleton:
  - `launch(argv, {desktopId, workingDirectory})` hands a short `sh` the
    argv. The sh `cd`s to the working directory and execs, in order:
    1. `uwsm-app [-a <id>] -- argv` when `uwsm-app` is on PATH and uwsm
       runs the session (`UWSM_FINALIZE_VARNAMES` or `UWSM_WAIT_VARNAMES`
       set), as Hyprland's `haseen.launch`;
    2. `systemd-run --user --scope --slice=app-graphical.slice --collect
       --quiet --unit=app-haseen-<id>-<8 hex>.scope -- argv`, named like
       uwsm's `app-<desktop>-<id>-<random>.scope` (the id's characters
       outside `[A-Za-z0-9_.]` become `_`, since dashes separate the parts);
    3. the bare argv.
    The sh is replaced by the tool, so nothing of the app stays in the
    shell's cgroup.
  - `launchEntry(entry)` runs `entry.command` with the field codes removed
    (`%f %F %u %U %d %D %n %N %v %m %i %c %k`; `%%` is `%`), in the entry's
    `workingDirectory`, with the desktop id as unit name. A `Terminal=true`
    entry runs as `${TERMINAL:-foot} -e argv`, the terminal SUPER+RETURN
    opens. (`DesktopEntry.execute()` ignores both.)
- Callers:
  - `haseen.launcher`: app rows call `Apps.launchEntry`.
  - `haseen.menu`: app rows (`launchApp`) and actions (`run`) go through
    `Apps`; an action runs in its own `app-haseen-haseen_menu-*` scope, so
    the terminals and apps it starts survive.
  - Omarchy compat: `Util.execDetached`/`execArgv` and the host API's
    `run` start plugin commands through `Apps`.
  - `haseen.network`: the speed test (a floating terminal).
- Left alone, as the shell's own helpers: `qs ipc`, `wl-copy`, the `haseen`
  CLI writes (theme, bar, flags, context), probes, `systemctl`/`loginctl`,
  notify-send. The screensaver's terminals start through Hyprland's
  `exec_cmd` already; the tray and notifications activate over D-Bus into
  apps that are already running.

## Tests

`tests/test-apps.sh`, the real Quickshell engine with fixture desktop
entries and stub binaries that record argv and working directory. It loads
the actual launcher and menu panels and checks three PATHs:
uwsm session → `uwsm-app -a <id> --`; no uwsm session → `systemd-run` scope
with the unit name pattern; neither → the bare argv. In each, it checks the
stripped field codes, the entry's `Path=`, the `$TERMINAL -e` case, the
menu action's bash and `Apps.launch` without an id.

## Nested proof (io, 2026-10-07)

A nested Hyprland (`nest-launch.sh`), scratch `HOME` with a `shell.json`
of no services (so no `haseen.polkit`) and the launcher's `debugIpc`. Each
tree's shell ran as a transient user service with `KillMode=control-group`,
like `haseen-shell.service`, with the UWSM variables empty. The nest runs no
uwsm, so this is the `systemd-run` path. The nest's qs talks to its own
`dbus-run-session` bus, but `systemd-run --user` reaches the user manager
over `$XDG_RUNTIME_DIR/systemd/private`, and the scope was created. Helium
was started over the launcher's IPC hook (`setQuery Helium`, `accept`).

- Before (origin/main): helium 1777758 and its two `cat`s (1777761,
  1777762, its fd 1 and 2 pipes) were in `haseen-appscope-before.service`.
  Stopping the unit killed helium. (In the nest helium did not move itself
  into a Chromium scope, as it did on io, so it died with the shell instead
  of on the broken pipe; either way it went with the shell.)
- After: helium 1779031 and its `cat`s 1779034, 1779035 were in
  `app-graphical.slice/app-haseen-helium-64226ffa.scope`; the shell's unit
  held only qs. Stopping the unit left helium, both cats and the scope
  running.
