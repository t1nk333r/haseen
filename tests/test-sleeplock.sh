# shellcheck shell=bash
# Lock before sleep: the screen is locked while logind is still waiting on our
# delay inhibitor, the inhibitor is released so the sleep can happen, and a
# new one is taken after resume.
sandbox sleeplock

log="$SANDBOX/calls"
: >"$log"
# logind's two announcements around one suspend, the way dbus-monitor prints
# them (the boolean is on its own line). The stub then ends, which ends the
# monitor; the pause lets the post-resume inhibitor start before that.
stub dbus-monitor "printf '%s\n' \"signal time=1 sender=:1.3 -> destination=(null) path=/org/freedesktop/login1; interface=org.freedesktop.login1.Manager; member=PrepareForSleep\" '   boolean true' \"signal time=2 sender=:1.3 -> destination=(null) path=/org/freedesktop/login1; interface=org.freedesktop.login1.Manager; member=PrepareForSleep\" '   boolean false'; sleep 0.5"
# The inhibitor records when it is taken and when it is let go.
stub systemd-inhibit "echo \"inhibit \$*\" >>'$log'; trap 'echo release >>\"$log\"; exit 0' TERM; while :; do sleep 0.05; done"
stub haseen "echo \"haseen \$*\" >>'$log'"

HASEEN_LOCK_GRACE=0.1 capture timeout 10 "$REPO/bin/haseen-lock-before-sleep"
assert_status "one sleep/resume cycle is handled" 0 "$STATUS"
calls="$(cat "$log")"
assert_contains "a delay inhibitor is held while waiting" "$calls" "inhibit --what=sleep --mode=delay"
assert_contains "the screen is locked when sleep is announced" "$calls" "haseen shell ipc lock lock"

order="$(grep -o '^inhibit\|^haseen\|^release' "$log" | tr '\n' ' ')"
assert_eq "inhibit, lock, release, then inhibit again after resume" \
    "inhibit haseen release inhibit release " "$order"

# A lock that does not answer must not cancel the sleep: the inhibitor still goes.
: >"$log"
stub haseen "echo \"haseen \$*\" >>'$log'; exit 1"
HASEEN_LOCK_GRACE=0.1 capture timeout 10 "$REPO/bin/haseen-lock-before-sleep"
assert_contains "a failed lock is reported" "$OUTPUT" "sleeping anyway"
order="$(grep -o '^inhibit\|^haseen\|^release' "$log" | tr '\n' ' ')"
assert_eq "and the inhibitor is still released" "inhibit haseen release inhibit release " "$order"

