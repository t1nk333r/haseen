# Plan 142: `haseen update haseen` reads the units again before the restart

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One `systemctl --user daemon-reload` between the install
  and the shell restart, only on the path that already restarts; it starts,
  stops and restarts nothing itself. Measured at 119–129 ms on luna
  (systemd 262).
- **Depends on**: 134 (`haseen update haseen`)
- **Category**: install
- **Planned at**: 2026-10-28
- **State**: DONE 2026-10-28 (`tests/test-update-haseen.sh` 49/49; the
  affected set, 7 files, 974/974).

## Problem

On 2026-10-28 the owner ran `haseen update haseen --tree-only` on IO to
install 14c0547 (plans 140 and 141). It installed, restarted the shell, and
systemd added:

> Warning: The unit file, source configuration file or drop-ins of
> haseen-shell.service changed on disk. Run 'systemctl --user daemon-reload'
> to reload units.

The same flag was set on luna, installed from the same commit the evening
before: `systemctl --user show haseen-shell.service -p NeedDaemonReload`
read `yes` on both hosts until a manual `systemctl --user daemon-reload`
cleared it. Neither range changed a unit (`git diff --stat ccb0832 14c0547 --
share/haseen/systemd` and `git diff --stat 9aab848 14c0547 --
share/haseen/systemd` print nothing). The flag comes from the install
itself: `install.sh:249-251` copies every file in
`share/haseen/systemd/user/` through `install_root_file`, which is
`sudo install -Dm0644` (`share/haseen/lib/common.sh:359`). That gives the
file a new mtime even when its bytes are the same, and the user manager then
counts it as changed.

So every update prints that warning. Worse, when a unit does change, the
restart in `reload_desktop` (`bin/haseen-update-haseen:225-231` before this
plan) runs the copy the manager read at login. A disposable unit in
`$XDG_RUNTIME_DIR/systemd/user/` on luna showed it: started as
`ExecStart=/bin/sh -c "echo probe-A; exec sleep 60"`, rewritten to echo
`probe-B`, then `systemctl --user restart`. The journal read `probe-A`
twice, and the restart printed the same warning. A new `Environment=` or
`ExecStart=` in `haseen-shell.service` would wait for the next login, while
`haseen update` reports the shell as restarted on the new tree.

## What changed

`reload_desktop` in `bin/haseen-update-haseen` now runs
`run systemctl --user daemon-reload` after the Hyprland reload and before the
shell check. It sits outside the `is-active` branch, because install.sh
rewrites every haseen unit (`haseen-background`, `haseen-splash-follow.timer`
and the rest), not only the shell's. `run` makes `--dry-run` print
`DRYRUN: systemctl --user daemon-reload`. When no user manager answers (ssh
without `XDG_RUNTIME_DIR`), it warns that the units are read again at the
next login and goes on: the update itself has succeeded.

`--no-reload` and an already-installed commit both exit before
`reload_desktop` (`bin/haseen-update-haseen:243-249`), so neither reloads
units, as before.

## What this does not do

- Running `install.sh` by hand and then `haseen shell restart` still restarts
  from the old unit and prints the warning. `haseen shell restart` is also the
  restart button in panels, so it does not reload every time; after a bare
  install, run `systemctl --user daemon-reload` first, as IO's deploy note
  does.
- Running services other than the shell keep their old process. The reload
  makes systemd read their new unit, which applies at their next start.
  Restarting them is a separate decision for each unit.

## Rejected options

- **Reload from `install.sh`.** It writes the units, but into any `--prefix`
  (a staging directory, an image build), and the user manager it would reach
  is not always the one reading that prefix. The update command is the step
  that restarts the shell, so the reload belongs next to the restart.
- **Install a unit only when its bytes differ (`cmp -s` first).** That stops
  the warning when nothing changed, but a changed unit still needs the reload,
  so it cannot replace it. Once the reload runs, the extra mtime does no
  harm.
- **Reload only when `NeedDaemonReload=yes` on `haseen-shell.service`.** The
  other haseen units change too, and one reload costs about 125 ms
  (measured above).

## Tests

`tests/test-update-haseen.sh` (49/49). Its `systemctl` stub logs every call,
and `SYSTEMCTL_NO_MANAGER` makes `daemon-reload` fail. The new assertions:

- **The update:** the log holds exactly `daemon-reload`, then
  `restart haseen-shell.service`, in that order.
- **`--dry-run`:** prints the reload and makes no `daemon-reload` call.
- **No manager:** with `SYSTEMCTL_NO_MANAGER` it exits 0, prints the warning
  and still reaches the shell step.
- **`--no-reload`:** the existing empty-log assertion now also covers the
  reload.

Mutations:
- Without the fix it is 46/49: the dry-run line, the order and the warning
  fail.
- With the reload moved after the restart it is 47/49: the dry-run line and
  the order fail.
