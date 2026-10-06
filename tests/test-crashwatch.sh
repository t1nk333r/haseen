# shellcheck shell=bash
# The crash watcher: a core dump of one of this user's programs becomes one
# "diagnose with AI" notification; other users' crashes, our own tools, crash
# loops and machines without an agent stay quiet.
sandbox crashwatch

log="$SANDBOX/sent"
: >"$log"
me="$(id -u)"
entry() { # uid comm pid exe signal
    printf '{"_UID":"%s","COREDUMP_COMM":"%s","COREDUMP_PID":"%s","COREDUMP_EXE":"%s","COREDUMP_SIGNAL_NAME":"%s"}\n' "$@"
}
{
    entry "$me" quickshell 101 /usr/bin/quickshell SIGSEGV
    entry "$me" quickshell 102 /usr/bin/quickshell SIGSEGV # the same crash loop
    entry 0 sshd 103 /usr/bin/sshd SIGABRT                 # not ours
    entry "$me" haseen-crash-wa 104 /usr/local/bin/haseen-crash-watch SIGSEGV
    entry "$me" verylongprogram 105 /opt/app/verylongprogramname SIGBUS
    entry "$me" bad 106 - SIGSEGV
} >"$SANDBOX/journal"
stub journalctl "cat '$SANDBOX/journal'"
stub haseen-notification-wait "exit 0"
stub haseen-notification-send "printf '%s|' \"\$@\" >>'$log'; echo >>'$log'"

HASEEN_AGENT=claude capture "$REPO/bin/haseen-crash-watch"
assert_status "the watcher reads the journal to its end" 0 "$STATUS"
sent="$(cat "$log")"
assert_eq "one notification per program, none for others' or our own" 3 "$(grep -c . "$log")"
assert_contains "the crash is named" "$sent" "Program crashed: quickshell"
assert_contains "the click hands it to the agent, details as separate words" "$sent" "--exec|haseen-agent-crash|101|quickshell|/usr/bin/quickshell|SIGSEGV|"
assert_not_contains "a crash loop is announced once" "$sent" "|102|"
assert_not_contains "another user's crash is not ours to report" "$sent" "sshd"
assert_not_contains "the watcher never reports itself" "$sent" "haseen-crash-watch"
assert_contains "the executable's name beats the 15-character comm" "$sent" "Program crashed: verylongprogramname"
assert_contains "a crash without an executable keeps its comm" "$sent" "Program crashed: bad"

: >"$log"
HASEEN_CRASH_IGNORE='^quickshell$' HASEEN_AGENT=claude capture "$REPO/bin/haseen-crash-watch"
assert_not_contains "an ignored program stays quiet" "$(cat "$log")" "quickshell"

: >"$log"
stub haseen-setup-default "exit 0"
env -u HASEEN_AGENT "$REPO/bin/haseen-crash-watch" >/dev/null 2>&1
assert_eq "without an agent there is nothing to offer" "" "$(cat "$log")"

: >"$log"
stub haseen-notification-send "exit 1"
HASEEN_AGENT=claude capture "$REPO/bin/haseen-crash-watch"
stub haseen-notification-send "printf '%s|' \"\$@\" >>'$log'; echo >>'$log'"
assert_status "a failed send does not stop the watcher" 0 "$STATUS"
