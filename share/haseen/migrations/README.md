# Migrations

One-off upgrade steps. `haseen migrate` runs every script here that this user
has not run yet, oldest first, and writes a marker in
`~/.local/state/haseen/migrations/<name>`.

A file is named `<unix-timestamp>-<slug>.sh` (`date +%s`), for example
`1790863209-move-theme-state.sh`. Any other name aborts the run, so a migration
is never silently skipped.

Rules for a migration body:

- It is sourced by `bash -Eeuo pipefail`, with `HASEEN_PATH` and
  `HASEEN_MIGRATION` exported. Source `$HASEEN_PATH/lib/common.sh` for
  `run_root`, `write_user_file`, `info` and friends.
- It must be safe to re-run: a failed migration keeps its marker unwritten and
  runs again on the next login, and nothing after it runs until it succeeds.
- It touches the user's own files and system state, never this tree.
- It must not need the shell to be running; it can be run from a TTY.

A first install has nothing to upgrade, so `install.sh` records every shipped
migration as sealed (`haseen migrate --seal`) instead of running them. The
ledger lives in the user's state dir, so a later reinstall does not replay them.
