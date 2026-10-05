# Plan 028: Migration ledger

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (a new command and a user-state marker directory)
- **Depends on**: 001
- **Category**: tooling
- **Planned at**: 2026-10-05, owner request to port Omarchy's upgrade mechanism
- **State**: DONE 2026-10-05

## Problem

The only upgrade path was re-running `install.sh`, which replaces the tree and
applies layers. Nothing could move a file the user already owns, drop a setting
that changed shape, or repair state a new version expects. Every later port
needs that step to exist before it can ship a change that is not a fresh install.

## Decision

Port the mechanism of Omarchy's `bin/omarchy-migrate` and
`bin/omarchy-provision-user`, not its 137 migration bodies:

- A migration is `share/haseen/migrations/<unix-timestamp>-<slug>.sh`, run with
  `bash -Eeuo pipefail` and `HASEEN_PATH`/`HASEEN_MIGRATION` exported. A name
  that does not match aborts the run, because a migration nobody runs is worse
  than a loud install.
- The ledger is one marker file per applied migration under
  `~/.local/state/haseen/migrations/`, holding `applied|sealed`, the date and the
  version. It lives in the user's state, so replacing or repackaging the tree
  never replays it.
- A failure stops the run with its marker unwritten; the next run retries it and
  nothing after it has run out of order.
- `install.sh` seals a first install (`--seal`) and runs what is pending on a
  reinstall. A first install has nothing to upgrade.
- `haseen migrate notify`, a login unit, sends one critical notification when
  something is pending and opens `haseen migrate` in a floating terminal if it is
  clicked. haseen.pager is the daemon, so the click is a freedesktop action this
  process waits on, not a command stored by the daemon.
- `haseen migrate` waits for a running pacman transaction (up to 15 minutes) and
  otherwise leaves the work for the next login.

## Verification

- `tests/test-migrate.sh`: nothing pending in a tree with no migrations; a
  migration runs exactly once across two invocations; dry-run plans without
  running or recording; a failure keeps no marker and stops the run; the retry
  resumes in order; a replaced tree replays nothing; sealing records without
  running; a malformed name aborts; the notifier counts what is pending.
- Live on the reference laptop: a dated migration ran once, the second run was a
  no-op, and the marker read `applied <date> 0.1.0-dev`. A first version of that
  smoke used `info` without sourcing `lib/common.sh`, hit GNU texinfo's `info`,
  and exercised the failure path: loud error, no marker, retried on the next run.

## Execution record

`bin/haseen-migrate`, `bin/haseen-migrate-notify`, `share/haseen/lib/migrate.sh`,
`share/haseen/migrations/README.md`,
`share/haseen/systemd/user/haseen-migrate-notify.service`, the seal/run step in
`install.sh`, and `tests/test-migrate.sh` (30 assertions).
