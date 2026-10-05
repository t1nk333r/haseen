# shellcheck shell=bash
# migrate.sh — migrations, the run-once upgrade steps. Sourced, never executed.
#
# Adapted from Omarchy bin/omarchy-migrate (MIT, Copyright (c) David Heinemeier
# Hansson): a migration is a shell script named <unix-timestamp>-<slug>.sh in
# $HASEEN_PATH/migrations. It runs once per user, oldest first, and is recorded
# in the shared ledger (lib/ledger.sh), which lives in the user's state dir.

[[ -n ${HASEEN_MIGRATE_SH:-} ]] && return 0
HASEEN_MIGRATE_SH=1

# shellcheck source=ledger.sh
source "$(dirname "${BASH_SOURCE[0]}")/ledger.sh"

MIGRATION_RE='^[0-9]{10,}-[a-z0-9][a-z0-9-]*\.sh$'

migrate_dir() { printf '%s\n' "${HASEEN_MIGRATIONS_DIR:-$HASEEN_PATH/migrations}"; }
migrate_ledger_dir() { ledger_dir migrations; }

# migrate_names — every shipped migration, oldest first. The timestamp prefix
# is fixed-width enough that a plain sort is chronological; a file that does not
# match the naming rule is refused rather than silently skipped, because a
# migration nobody runs is worse than a loud install.
migrate_names() {
    local dir file name
    dir="$(migrate_dir)"
    [[ -d $dir ]] || return 0
    for file in "$dir"/*.sh; do
        [[ -f $file ]] || continue
        name="${file##*/}"
        [[ $name =~ $MIGRATION_RE ]] || die "malformed migration name: $name (expected <unix-timestamp>-<slug>.sh)"
        printf '%s\n' "$name"
    done | LC_ALL=C sort
}

migrate_applied() { ledger_applied migrations "$1"; }

migrate_pending() {
    local name
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        migrate_applied "$name" || printf '%s\n' "$name"
    done < <(migrate_names)
}

# migrate_record NAME HOW — mark NAME done. HOW is `applied` or `sealed`.
migrate_record() { ledger_record migrations "$1" "$2"; }

# migrate_wait_for_pacman — a migration that installs or removes packages cannot
# run while pacman holds its lock, and login is exactly when an update is likely
# to be running. Waits up to 15 minutes, then leaves the work for the next run.
migrate_wait_for_pacman() {
    local lock i
    lock="$(sysroot_path /var/lib/pacman/db.lck)"
    [[ -e $lock ]] || return 0
    info "waiting for the running pacman transaction"
    for ((i = 0; i < 900; i++)); do
        [[ -e $lock ]] || return 0
        sleep 1
    done
    return 1
}
