# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The migration ledger: a shipped tree with no migrations has nothing pending, a
# migration runs exactly once per user, a failure is retried, and the ledger
# outlives the installed tree.
sandbox migrate

tree="$SANDBOX/tree"
mkdir -p "$tree/migrations"
cp "$REPO/share/haseen/VERSION" "$tree/VERSION"
cp -r "$REPO/share/haseen/lib" "$tree/lib"
export HASEEN_PATH="$tree"
ledger="$XDG_STATE_HOME/haseen/migrations"

write_migration() { # NAME BODY
    printf '%s\n' "$2" >"$tree/migrations/$1"
}

capture haseen migrate --pending
assert_status "nothing pending in a tree with no migrations" 1 "$STATUS"
capture haseen migrate
assert_contains "a run with nothing pending says so" "$OUTPUT" "no pending migrations"
assert_eq "an empty run writes no ledger" "" "$(ls "$ledger" 2>/dev/null || true)"

write_migration 1790000001-first.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
export MIGRATE_LOG="$SANDBOX/ran.log"

capture haseen migrate --pending
assert_status "a new migration is pending" 0 "$STATUS"
assert_eq "pending lists the migration" "1790000001-first.sh" "$OUTPUT"

capture haseen migrate --dry-run
assert_dry_pure "dry run" "$OUTPUT"
assert_contains "a dry run plans the migration" "$OUTPUT" "DRYRUN: run migration 1790000001-first.sh"
assert_eq "a dry run records nothing" "" "$(ls "$ledger" 2>/dev/null || true)"
assert_eq "a dry run runs nothing" "" "$(cat "$MIGRATE_LOG" 2>/dev/null || true)"

capture haseen migrate
assert_status "the migration runs" 0 "$STATUS"
capture haseen migrate
assert_status "a second run is a no-op" 0 "$STATUS"
assert_eq "the migration ran exactly once across two invocations" "ran 1790000001-first.sh" "$(cat "$MIGRATE_LOG")"
assert_contains "the marker records how it was applied" "$(cat "$ledger/1790000001-first.sh")" "applied "

# Ordering and failure handling: the older script runs first, and a failure
# stops the run with its own marker unwritten, so the next run retries it.
write_migration 1790000003-third.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
write_migration 1790000002-second.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"; exit 1'
capture haseen migrate
assert_status "a failing migration fails the run" 1 "$STATUS"
assert_contains "the failure names the migration" "$OUTPUT" "migration 1790000002-second failed"
assert_eq "nothing after the failure ran" "ran 1790000001-first.sh
ran 1790000002-second.sh" "$(cat "$MIGRATE_LOG")"
assert_eq "a failed migration keeps no marker" "" "$(compgen -G "$ledger/*second*" || true)"

write_migration 1790000002-second.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
capture haseen migrate
assert_status "the fixed migration completes the run" 0 "$STATUS"
assert_eq "the retry resumes in order" "ran 1790000001-first.sh
ran 1790000002-second.sh
ran 1790000002-second.sh
ran 1790000003-third.sh" "$(cat "$MIGRATE_LOG")"

# A reinstall replaces the tree; the ledger is the user's and must survive it.
rm -rf "$tree/migrations"
mkdir -p "$tree/migrations"
write_migration 1790000001-first.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
write_migration 1790000002-second.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
write_migration 1790000003-third.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
capture haseen migrate --pending
assert_status "a reinstalled tree replays nothing" 1 "$STATUS"

# A first install seals what it ships instead of running it.
rm -rf "$ledger" "$MIGRATE_LOG"
capture haseen migrate --seal
assert_status "sealing succeeds" 0 "$STATUS"
assert_eq "sealing runs nothing" "" "$(cat "$MIGRATE_LOG" 2>/dev/null || true)"
assert_eq "sealing records every shipped migration" 3 "$(ls "$ledger" | wc -l)"
assert_contains "the marker says it was sealed" "$(cat "$ledger/1790000003-third.sh")" "sealed "
capture haseen migrate --pending
assert_status "a sealed install has nothing pending" 1 "$STATUS"

# A name without a timestamp would never sort, so it is refused, not skipped.
write_migration later.sh 'true'
capture haseen migrate --pending
assert_status "a malformed name aborts" 1 "$STATUS"
assert_contains "the abort names the file" "$OUTPUT" "malformed migration name: later.sh"
rm -f "$tree/migrations/later.sh"

# The notifier is quiet when nothing is pending and asks once when something is.
stub notify-send 'echo "NOTIFY: $*"; echo run'
capture haseen migrate notify
assert_eq "no toast when nothing is pending" "" "$OUTPUT"
write_migration 1790000004-fourth.sh 'true'
capture haseen migrate notify --dry-run
assert_dry_pure "notify dry run" "$OUTPUT"
assert_contains "the notifier counts what is pending" "$OUTPUT" "DRYRUN: notify about 1 pending migration"
