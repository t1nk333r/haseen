# Plan 142: `haseen update haseen` reads the units again before the restart

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW. One `systemctl --user daemon-reload` after the install,
  before the shell restart. It queues no job, so it starts, stops and
  restarts nothing itself (`systemctl(1)`, `systemd.unit(5)`); measured at
  119–129 ms on luna (systemd 262). What it changes is which unit the next
  start runs. A broken `haseen-shell.service` now takes the shell down
  through its start limit and plan 061's recovery offer, where the stale
  copy used to keep the old shell running. That is the point: the update
  now runs what it installed.
- **Depends on**: 134 (`haseen update haseen`)
- **Category**: install
- **Planned at**: 2026-10-28
- **State**: DONE 2026-10-28 (`tests/test-update-haseen.sh` 53/53; the
  affected set, 7 files, 978/978). Review: DeepSeek V4.1 Flash approved
  rounds 1 and 2 with four nits in all, every one taken (see "Review").

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
`DRYRUN: systemctl --user daemon-reload`. When the reload fails (no user
manager answers, as over ssh without `XDG_RUNTIME_DIR`), it warns that the
units are read again at the next login and goes on, because the update
itself has succeeded. systemctl's own error stays on stderr, above the
warning.

`--no-reload` and an already-installed commit both exit before
`reload_desktop` (`bin/haseen-update-haseen:243-249`), so neither reloads
units, as before.

## What this does not do

Two of the commands that start the shell read the units first:
`haseen update haseen`, and `haseen shell use`, which reloads before it
switches units (`bin/haseen-shell-use:53-55`). After a bare `install.sh`, or
`haseen update haseen --no-reload`, run `systemctl --user daemon-reload`
before the shell starts again, as IO's deploy note does. Until then, these
paths start or restart the shell from the copy read at login:

- `haseen shell restart` (`bin/haseen-shell-restart:26-30`). It is also the
  restart button in panels, so it does not reload every time.
- The recovery offer: `resume_shell` in `bin/haseen-shell-recover:68-74`
  (`reset-failed`, then `start`), reached through `OnFailure=` when the shell
  hits its start limit.
- `haseen lock release` (`bin/haseen-lock-release:82`), which starts the
  shell after an unlock from a TTY.
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

`tests/test-update-haseen.sh` (53/53). Its `systemctl` stub logs every call,
`SYSTEMCTL_NO_MANAGER` makes `daemon-reload` fail, and
`SYSTEMCTL_SHELL_STOPPED` makes `is-active` report the shell stopped. The
new assertions:

- **The update:** the log holds exactly `daemon-reload`, then
  `restart haseen-shell.service`, in that order.
- **`--dry-run`:** prints the reload and makes no `daemon-reload` call.
- **No manager:** with `SYSTEMCTL_NO_MANAGER` it exits 0, prints the warning
  and still reaches the shell step.
- **Shell stopped:** with `SYSTEMCTL_SHELL_STOPPED` the units are still read
  again, the shell is not restarted, and the update says it is not running.
  This pins the reload outside the `is-active` branch.
- **`--no-reload`:** the existing empty-log assertion now also covers the
  reload.

Mutations:
- Without the fix it is 49/53: the dry-run line, the order, the warning and
  the stopped-shell reload fail.
- With the reload moved after the restart it is 50/53: the dry-run line, the
  order and the stopped-shell reload fail.
- With the reload moved inside the `is-active` branch it is 52/53: the
  stopped-shell reload fails.

## Review

DeepSeek V4.1 Flash, run through `codex exec`, reviewed each round on the
exact head.

**Round 1 (10b09f1): APPROVE.** It re-ran 49/49, both mutations (46/49,
47/49) and the affected set (974/974), and checked every citation, the
`install -D` mtime claim and the no-ERR-trap fall-through. It raised three
nits, all taken:

- **N1.** "What this does not do" missed the recovery offer and
  `haseen lock release`. Both are now listed.
- **N2.** Nothing pinned the reload outside the `is-active` branch: moved
  inside, all 49 still passed. The stopped-shell case now catches it
  (52/53).
- **N3.** Risk did not say that a broken unit now takes effect. It does now.

The reviewer also noted that the warning named "no user manager" for any
failure. It now names the failed command.

**Round 2 (4c4be14): APPROVE.** It re-ran 53/53, the three mutations
(49/53, 50/53, 52/53) and the affected set (978/978), and confirmed the
stopped-shell case reaches the "not running" branch through `is-active`, not
the DMS branch. Its one nit was taken:

- **N4.** "Only `haseen update haseen` reads the units again" was false:
  `haseen shell use` reloads too. The paragraph now names both.
