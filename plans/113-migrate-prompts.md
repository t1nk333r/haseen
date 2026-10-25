# Plan 113: `haseen migrate` gives each migration its own stdin and `--yes`

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. One loop in `bin/haseen-migrate` reads its list on another
  file descriptor and passes `ASSUME_YES` to each migration; the order, the
  ledger and failure handling do not change.
- **Depends on**: 028 (migration ledger)
- **Category**: core, upgrades
- **Planned at**: 2026-10-25, from the IO deploy of main 064e7d8
- **State**: DONE 2026-10-25 (`tests/test-migrate.sh` 37/37; 32/37 on the
  old loop)

## Decision

No new owner decision: this fixes a bug the owner's "Deploy now"
(2026-10-25) ran into.

## Problem

Deploying 064e7d8 to IO, `haseen migrate --yes` stopped at the first of three
migrations:

```
[*] running migration 1792634179-omasnap
…
:: Proceed with installation? [Y/n] 1792669390-splash-follows-theme
Error: migration 1792634179-omasnap failed; nothing after it ran
```

Two faults in the run loop (`bin/haseen-migrate:70-83` before this plan):

1. **The list was every migration's stdin.** The loop read names from
   `done <<<"$pending"`, so a migration that read stdin — pacman's prompt, or
   `confirm` (`share/haseen/lib/common.sh`, `read -r -p`) — took the next
   migration's name as its answer. pacman read
   `1792669390-splash-follows-theme` as "no", the Omasnap migration failed, and
   the splash migration never ran. The same happened without `--yes`: the
   migration notifier opens `haseen-migrate` in a floating terminal
   (`bin/haseen-migrate-notify:56`), and the user was never asked.
2. **`--yes` stopped at the parent.** `parse_common_flags` sets `ASSUME_YES`
   in `haseen-migrate`, but each migration is a new `bash` that sources
   `common.sh`, where `ASSUME_YES=${ASSUME_YES:-false}` (`common.sh:20`) reads
   only the environment. So `pkg_install_omarchy` ran pacman without
   `--noconfirm` (`share/haseen/lib/packages.sh:332-334`) under
   `haseen migrate --yes`.

IO was finished by hand with `ASSUME_YES=true haseen migrate --yes </dev/null`
(all three migrations applied; `pacman -Q omasnap layer-shell-qt`).

## Change

`bin/haseen-migrate` reads the list with `read -u 3` from `3<<<"$pending"`
and closes fd 3 for the migration (`3<&-`), so a migration's stdin is the
command's own: a terminal asks the user, `</dev/null` reads end of file. Each
migration gets `ASSUME_YES="$ASSUME_YES"` in its environment, which
`common.sh` picks up when the migration sources it. `--dry-run` still runs no
migration, so it needs nothing passed on.

## Rejected

- **`</dev/null` for every migration.** It would fix the unattended run but
  leave the floating-terminal run unable to ask anything: every prompt would
  read end of file and decline.
- **`export ASSUME_YES` in `common.sh`.** Every script that sources it would
  hand `--yes` to every child it starts, including ones that should ask.

## Evidence

- `tests/test-migrate.sh`: a migration that reads one line, prints
  `ASSUME_YES` and calls `confirm`, followed by a second migration:
  - `haseen migrate --yes </dev/null`: the first reads end of file, sees
    `yes=true`, passes `confirm`, and the second runs;
  - `haseen migrate` fed `y` twice: the migration reads `y` (not a migration
    name), `confirm` takes the second `y`, and the second migration runs;
  - `haseen migrate </dev/null`: `confirm` declines, the run fails, nothing is
    recorded for it and the second migration does not run.
- Hermetic run: 37/37. The same file against the loop on main: 32/37, the
  five new assertions failing.

## Owner steps

None. The next deploy's `haseen migrate --yes` no longer needs the
`ASSUME_YES=true` prefix.
