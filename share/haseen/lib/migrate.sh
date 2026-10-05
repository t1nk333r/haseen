# shellcheck shell=bash
# migrate.sh — the migration ledger. Sourced, never executed.
#
# Adapted from Omarchy bin/omarchy-migrate (MIT, Copyright (c) David Heinemeier
# Hansson): a migration is a shell script named <unix-timestamp>-<slug>.sh in
# $HASEEN_PATH/migrations. It runs once per user, oldest first, and leaves a
# marker file in the ledger. The ledger lives in the user's state dir, not in
# the installed tree, so reinstalling or repackaging haseen never replays it.

[[ -n ${HASEEN_MIGRATE_SH:-} ]] && return 0
HASEEN_MIGRATE_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

MIGRATION_RE='^[0-9]{10,}-[a-z0-9][a-z0-9-]*\.sh$'

migrate_dir() { printf '%s\n' "${HASEEN_MIGRATIONS_DIR:-$HASEEN_PATH/migrations}"; }
migrate_ledger_dir() { printf '%s\n' "${HASEEN_MIGRATION_LEDGER:-$HASEEN_USER_STATE/migrations}"; }

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

migrate_applied() { [[ -f "$(migrate_ledger_dir)/$1" ]]; }

migrate_pending() {
    local name
    while IFS= read -r name; do
        [[ -n $name ]] || continue
        migrate_applied "$name" || printf '%s\n' "$name"
    done < <(migrate_names)
}

# migrate_record NAME HOW — mark NAME done. HOW is `applied` or `sealed`; the
# marker keeps it, so a later bug report can tell a first install from an upgrade.
migrate_record() {
    local name="$1" how="$2" ledger
    ledger="$(migrate_ledger_dir)"
    if $DRY_RUN; then
        echo "DRYRUN: record migration $name ($how)"
        return 0
    fi
    mkdir -p "$ledger"
    printf '%s %s %s\n' "$how" "$(date -Is)" "$(cat "$HASEEN_PATH/VERSION")" >"$ledger/$name"
}

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
