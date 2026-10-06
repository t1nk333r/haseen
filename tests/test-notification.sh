# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The notification CLI: wait blocks only until the bus name has an owner, send
# hands notify-send one argv (never a shell string), and dismiss calls the
# haseen.pager IPC verbs that exist.
sandbox notification

# --- haseen notification wait -----------------------------------------------

stub busctl 'exit 0'
start=$SECONDS
capture haseen notification wait --timeout 30
assert_status "wait succeeds once the name has an owner" 0 "$STATUS"
assert_eq "wait returns as soon as the owner is there" fast \
    "$([[ $((SECONDS - start)) -lt 5 ]] && echo fast || echo slow)"

capture haseen notification wait --timeout=2
assert_status "--timeout=N is accepted too" 0 "$STATUS"

stub busctl 'exit 1'
capture haseen notification wait --timeout 1
assert_status "wait fails when nothing claims the name" 1 "$STATUS"
assert_contains "the failure says how long it waited" "$OUTPUT" "within 1s"

capture haseen notification wait --timeout soon
assert_status "a non-numeric timeout is refused" 1 "$STATUS"
assert_contains "the refusal names the unit" "$OUTPUT" "whole seconds"

capture haseen notification wait 5
assert_status "the timeout is an option, not a positional" 2 "$STATUS"

# A dry run plans the wait and never touches the bus.
stub busctl 'echo "STUB-CALLED: busctl $*" >&2; exit 97'
capture haseen notification wait --dry-run --timeout 5
assert_status "wait dry run succeeds" 0 "$STATUS"
assert_dry_pure "wait dry run" "$OUTPUT"
assert_eq "wait dry run prints the plan" \
    "DRYRUN: wait up to 5s for org.freedesktop.Notifications" "$OUTPUT"

# --- haseen notification send -----------------------------------------------

argv="$SANDBOX/argv"
stub notify-send "printf '%s\n' \"\$@\" >'$argv'"

capture haseen notification send -u critical -i battery -t 5000 -r 7 "Headline" "Body"
assert_status "send succeeds" 0 "$STATUS"
assert_eq "send hands notify-send one argv, app name first and text behind --" "-a
haseen
-u
critical
-i
battery
-t
5000
-r
7
--
Headline
Body" "$(cat "$argv")"

# A headline that looks like an option, and a body that starts with a dash, are
# text: `--` keeps them positional and the body slot is never parsed as a flag.
capture haseen notification send "--hint=string:x:y" "-50% off"
assert_eq "dash-leading headline and body stay text" "-a
haseen
--
--hint=string:x:y
-50% off" "$(cat "$argv")"

capture haseen notification send -p --app-name other "Head"
assert_eq "--print-id and --app-name pass through" "-a
other
-p
--
Head" "$(cat "$argv")"

capture haseen notification send -u shout "Head"
assert_status "an unknown urgency is refused" 1 "$STATUS"
assert_contains "the refusal lists the urgencies" "$OUTPUT" "low, normal or critical"

capture haseen notification send -r abc "Head"
assert_status "a non-numeric replace id is refused" 1 "$STATUS"
assert_contains "the refusal says what -r takes" "$OUTPUT" "numeric id"

capture haseen notification send -i
assert_status "an option without its value is refused" 1 "$STATUS"
assert_contains "the refusal names the option" "$OUTPUT" "missing value for -i"

capture haseen notification send
assert_status "send needs a headline" 2 "$STATUS"

# --exec is a real freedesktop action: notify-send -A waits and prints the
# clicked action's name, and the argv runs as the words it was given.
stub clicked-cmd 'printf "CLICKED:%s\n" "$@"'
stub notify-send "printf '%s\n' \"\$@\" >'$argv'; echo exec"
capture haseen notification send "Head" --exec clicked-cmd one "two three"
assert_status "a clicked action runs its command" 0 "$STATUS"
assert_eq "the command's argv is not re-split" "CLICKED:one
CLICKED:two three" "$OUTPUT"
assert_contains "the action is offered to the daemon" "$(cat "$argv")" "-A
exec=Open"

stub notify-send "printf '%s\n' \"\$@\" >'$argv'"
capture haseen notification send "Head" --exec clicked-cmd one
assert_status "an unanswered notification succeeds" 0 "$STATUS"
assert_eq "an unanswered notification runs nothing" "" "$OUTPUT"

capture haseen notification send "Head" --exec "clicked-cmd one"
assert_status "a quoted command string is refused" 1 "$STATUS"
assert_contains "the refusal shows the unquoted form" "$OUTPUT" "separate words"

capture haseen notification send -p "Head" --exec clicked-cmd
assert_status "--print-id with --exec is refused" 1 "$STATUS"
assert_contains "the refusal says why" "$OUTPUT" "cannot be combined"

rm -f "$argv"
capture haseen notification send --dry-run -u low "Head" "Body" --exec clicked-cmd a
assert_status "send dry run succeeds" 0 "$STATUS"
assert_dry_pure "send dry run" "$OUTPUT"
assert_contains "send dry run prints the whole call" "$OUTPUT" \
    "DRYRUN: notify-send -a haseen -u low -A exec=Open -- Head Body"
assert_contains "send dry run names the click command" "$OUTPUT" "DRYRUN: on click: clicked-cmd a"
assert_eq "send dry run sends nothing" no "$([[ -e $argv ]] && echo yes || echo no)"

# --- haseen notification dismiss --------------------------------------------

stub qs 'echo "qs: $*"'
capture haseen notification dismiss "Pending haseen migrations"
assert_status "dismiss succeeds" 0 "$STATUS"
assert_eq "dismiss calls the pager with the summary" \
    "qs: -p $HASEEN_PATH/shell ipc call pager dismiss Pending haseen migrations" "$OUTPUT"

capture haseen notification dismiss --all
assert_eq "--all clears the deck" "qs: -p $HASEEN_PATH/shell ipc call pager dismissAll" "$OUTPUT"

capture haseen notification dismiss
assert_status "dismiss needs a summary" 2 "$STATUS"
capture haseen notification dismiss a b
assert_status "dismiss takes one argument" 2 "$STATUS"
capture haseen notification dismiss --everything
assert_status "an unknown flag is a usage error" 2 "$STATUS"

capture haseen notification dismiss --dry-run Reminder
assert_status "dismiss dry run succeeds" 0 "$STATUS"
assert_dry_pure "dismiss dry run" "$OUTPUT"
assert_eq "dismiss dry run prints the IPC call" \
    "DRYRUN: haseen-shell-ipc pager dismiss Reminder" "$OUTPUT"

# The verbs the CLI sends exist in the daemon.
pager_qml="$REPO/share/haseen/shell/plugins/haseen.pager/Service.qml"
assert_eq "pager.dismiss(summary) exists" 1 "$(grep -c 'function dismiss(summary: string): string' "$pager_qml")"
assert_eq "pager.dismissAll() exists" 1 "$(grep -c 'function dismissAll(): string' "$pager_qml")"
