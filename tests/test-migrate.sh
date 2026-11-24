# shellcheck shell=bash
# haseen:covers bin/haseen-{config-terminal,migrate,migrate-notify} share/haseen/VERSION
# haseen:covers share/haseen/lib/{ledger,migrate,terminal}.sh share/haseen/lib/*
# haseen:covers share/haseen/migrations/*.sh
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
# Checked with migrations pending on both sides of the bad name: the abort
# must not run, seal or list the ones before it, and must not drop the ones
# after it (plan 186: a die inside migrate_names' pipeline only ended that
# subshell, so the run went on with a partial list and exited 0).
write_migration later.sh 'true'
capture haseen migrate --pending
assert_status "a malformed name aborts" 1 "$STATUS"
assert_contains "the abort names the file" "$OUTPUT" "malformed migration name: later.sh"
rm -rf "$ledger" "$MIGRATE_LOG"
write_migration 1790000002-Bad.sh 'true'
capture haseen migrate --pending
assert_status "with migrations pending, a malformed name still fails --pending" 1 "$STATUS"
assert_not_contains "and lists none of them" "$OUTPUT" "1790000001-first.sh"
capture haseen migrate
assert_status "a malformed name fails the run" 1 "$STATUS"
assert_contains "the run names the file" "$OUTPUT" "malformed migration name: 1790000002-Bad.sh"
assert_eq "the run runs nothing, not even the migrations before it" "" "$(cat "$MIGRATE_LOG" 2>/dev/null || true)"
capture haseen migrate --seal
assert_status "a malformed name fails sealing" 1 "$STATUS"
assert_eq "sealing records nothing" "" "$(ls "$ledger" 2>/dev/null || true)"
rm -f "$tree/migrations/later.sh" "$tree/migrations/1790000002-Bad.sh"
capture haseen migrate --seal
assert_status "with the name fixed, sealing works again" 0 "$STATUS"
assert_eq "and records every shipped migration" 3 "$(ls "$ledger" | wc -l)"

# A migration that repairs system state is marked `# haseen:seal run`, and a
# first install runs it instead of sealing it: a HOME new to haseen says
# nothing about /etc (plan 186: the polkit repair was sealed on a fresh
# install and never ran). One that fails is named and stays pending, and the
# rest are still sealed.
rm -rf "$ledger" "$MIGRATE_LOG"
write_migration 1790000002-second.sh '# haseen:seal run
printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
capture haseen migrate --seal --dry-run
assert_dry_pure "seal dry run" "$OUTPUT"
assert_contains "a dry seal plans the marked migration's run" "$OUTPUT" "DRYRUN: run migration 1790000002-second.sh"
assert_contains "and the others' records" "$OUTPUT" "DRYRUN: record migrations 1790000003-third.sh (sealed)"
assert_eq "a dry seal runs nothing" "" "$(cat "$MIGRATE_LOG" 2>/dev/null || true)"
capture haseen migrate --seal
assert_status "sealing with a marked migration succeeds" 0 "$STATUS"
assert_eq "only the marked migration ran" "ran 1790000002-second.sh" "$(cat "$MIGRATE_LOG")"
assert_eq "it is recorded as applied" "applied" "$(cut -d' ' -f1 "$ledger/1790000002-second.sh")"
assert_eq "the others are sealed" "sealed sealed" "$(cut -d' ' -f1 "$ledger/1790000001-first.sh" "$ledger/1790000003-third.sh" | xargs)"
assert_contains "the count leaves it out" "$OUTPUT" "sealed 2 migration(s)"
rm -rf "$ledger" "$MIGRATE_LOG"
write_migration 1790000002-second.sh '# haseen:seal run
printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"; exit 1'
capture haseen migrate --seal
assert_status "a marked migration that fails does not fail the seal" 0 "$STATUS"
assert_contains "the failure is named" "$OUTPUT" "migration 1790000002-second failed; it stays pending"
assert_eq "the migrations after it are still sealed" "sealed" "$(cut -d' ' -f1 "$ledger/1790000003-third.sh")"
capture haseen migrate --pending
assert_eq "and it stays pending for the next run" "1790000002-second.sh" "$OUTPUT"
write_migration 1790000002-second.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
rm -rf "$ledger" "$MIGRATE_LOG"
# The marker is a line of its own; a mention of it elsewhere is not one.
write_migration 1790000002-second.sh '# see `# haseen:seal run` in lib/migrate.sh
printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
capture haseen migrate --seal
assert_eq "a mention of the marker is not the marker" "" "$(cat "$MIGRATE_LOG" 2>/dev/null || true)"
write_migration 1790000002-second.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
rm -rf "$ledger" "$MIGRATE_LOG"
assert_eq "the shipped migrations a first install runs: the polkit repair and Omarchy's seal" \
    "1792605416-seal-omarchy-migrations.sh 1792605417-polkit-faillock.sh" \
    "$(grep -lx '# haseen:seal run' "$REPO"/share/haseen/migrations/*.sh | xargs -n1 basename | xargs)"

# A migration's prompts read this command's stdin, not the list of names, and
# --yes reaches it (plan 113: on IO, pacman's prompt inside the Omasnap
# migration took the next migration's name as its answer and the run failed).
rm -rf "$ledger" "$MIGRATE_LOG"
rm -f "$tree"/migrations/*
write_migration 1790000005-asks.sh 'source "$HASEEN_PATH/lib/common.sh"
IFS= read -r reply || reply=EOF
printf "asks read=%s yes=%s\n" "$reply" "$ASSUME_YES" >>"$MIGRATE_LOG"
confirm "go on?" || exit 1'
write_migration 1790000006-after.sh 'printf "ran %s\n" "$HASEEN_MIGRATION" >>"$MIGRATE_LOG"'
capture haseen migrate --yes </dev/null
assert_status "an unattended --yes run passes the prompt" 0 "$STATUS"
assert_eq "the migration read its own stdin and saw --yes; the next one still ran" "asks read=EOF yes=true
ran 1790000006-after.sh" "$(cat "$MIGRATE_LOG")"

rm -rf "$ledger" "$MIGRATE_LOG"
capture haseen migrate <<<$'y\ny'
assert_status "answered prompts reach the migration" 0 "$STATUS"
assert_eq "the user's answer, not a migration name, is what the migration read" "asks read=y yes=false
ran 1790000006-after.sh" "$(cat "$MIGRATE_LOG")"

rm -rf "$ledger" "$MIGRATE_LOG"
capture haseen migrate </dev/null
assert_status "without --yes an unanswered prompt declines and stops the run" 1 "$STATUS"
assert_eq "the declined migration is not recorded and nothing after it ran" "asks read=EOF yes=false" "$(cat "$MIGRATE_LOG")"
assert_eq "no marker for the declined migration" "" "$(compgen -G "$ledger/*asks*" || true)"
rm -f "$tree"/migrations/*
rm -rf "$ledger" "$MIGRATE_LOG"

# The notifier is quiet when nothing is pending and asks once when something is.
stub notify-send 'echo "NOTIFY: $*"; echo run'
capture haseen migrate notify
assert_eq "no toast when nothing is pending" "" "$OUTPUT"
write_migration 1790000004-fourth.sh 'true'
capture haseen migrate notify --dry-run
assert_dry_pure "notify dry run" "$OUTPUT"
assert_contains "the notifier counts what is pending" "$OUTPUT" "DRYRUN: notify about 1 pending migration"
