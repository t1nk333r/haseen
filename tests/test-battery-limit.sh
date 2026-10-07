# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 060: `haseen battery limit` writes and records the charge window, and
# `restore` (the boot unit, the sleep hook) puts it back after the battery
# controller forgot it. A fake power_supply tree under HASEEN_SYSROOT is the
# hardware; sudo runs the command for real inside the sandbox and logs it.
sandbox battery-limit
export HASEEN_INLINE=1
HOOK="$HASEEN_PATH/systemd/system-sleep/haseen-charge-limit"
UNIT_FILE="$HASEEN_PATH/systemd/system/haseen-charge-limit.service"

# laptop NAME START END — a ThinkPad-like BAT0 holding START-END.
laptop() {
    local root="$SANDBOX/$1" b="$SANDBOX/$1/sys/class/power_supply/BAT0"
    rm -rf "$root"
    mkdir -p "$b" "$root/etc/systemd/system" "$root/sys/class/power_supply/AC"
    printf 'Battery\n' >"$b/type"
    printf '%s\n' "$2" >"$b/charge_control_start_threshold"
    printf '%s\n' "$3" >"$b/charge_control_end_threshold"
    printf 'Mains\n' >"$root/sys/class/power_supply/AC/type"
    export HASEEN_SYSROOT="$root"
    BAT="$b"
}
held() { echo "$(<"$BAT/charge_control_start_threshold") $(<"$BAT/charge_control_end_threshold")"; }
conf() { cat "$HASEEN_SYSROOT/etc/haseen/charge-limit" 2>/dev/null || true; }
# writes — the threshold files sudo wrote, in order, as "start|end".
writes() { sed -n 's#^tee .*/charge_control_\([a-z]*\)_threshold$#\1#p' "$SANDBOX/sudo.log" | paste -sd'|'; }
real_sudo() {
    : >"$SANDBOX/sudo.log"
    stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'; exec \"\$@\""
}

# --- set: thresholds written in an order the kernel accepts, then recorded -----
laptop io 0 100
real_sudo
capture haseen battery limit set 80
assert_status "set succeeds" 0 "$STATUS"
assert_eq "the battery holds 75-80" "75 80" "$(held)"
assert_eq "moving down: floor first, then ceiling" "start|end" "$(writes)"
assert_contains "the window is recorded" "$(conf)" "start=75"
assert_contains "with its ceiling" "$(conf)" "end=80"
assert_contains "it says the limit" "$OUTPUT" "charge limit: 75-80%"
assert_contains "and that nothing restores it yet" "$OUTPUT" "haseen setup battery-limit on"

real_sudo
capture haseen battery limit set 90
assert_eq "the window moves up to 85-90" "85 90" "$(held)"
assert_eq "moving up: ceiling first, then floor" "end|start" "$(writes)"

capture haseen battery limit set 60 70
assert_status "a start above the end is refused" 1 "$STATUS"
assert_eq "and nothing changed" "85 90" "$(held)"
capture haseen battery limit set 101
assert_status "an end above 100 is refused" 1 "$STATUS"

capture haseen battery limit off
assert_eq "off charges to 100" "0 100" "$(held)"
assert_contains "off is recorded too" "$(conf)" "end=100"

# --- the controller forgets; restore puts the record back ---------------------
capture haseen battery limit set 80
printf '0\n' >"$BAT/charge_control_start_threshold"
printf '100\n' >"$BAT/charge_control_end_threshold"
real_sudo
capture haseen battery limit restore
assert_status "restore succeeds" 0 "$STATUS"
assert_eq "restore brings 75-80 back" "75 80" "$(held)"
assert_contains "and says so" "$OUTPUT" "restored: 75-80%"
real_sudo
capture haseen battery limit restore
assert_eq "restoring what is already held writes nothing" "" "$(writes)"

# --- save keeps a limit set elsewhere (a power panel's own pkexec) -------------
printf '60\n' >"$BAT/charge_control_start_threshold"
printf '65\n' >"$BAT/charge_control_end_threshold"
capture haseen battery limit save
assert_status "save succeeds" 0 "$STATUS"
assert_contains "save records what the battery holds" "$(conf)" "end=65"
printf '0\n' >"$BAT/charge_control_start_threshold"
printf '100\n' >"$BAT/charge_control_end_threshold"
capture haseen battery limit restore
assert_eq "a saved window round-trips through restore" "60 65" "$(held)"

capture haseen battery limit status
assert_contains "status shows the battery" "$OUTPUT" "battery:   BAT0"
assert_contains "status shows what it holds" "$OUTPUT" "now:       60-65%"
assert_contains "status shows that restore is off" "$OUTPUT" "restore:   off"

# --- the sleep hook restores after resume, never before sleep ------------------
printf '0\n' >"$BAT/charge_control_start_threshold"
printf '100\n' >"$BAT/charge_control_end_threshold"
capture "$HOOK" pre suspend-then-hibernate
assert_eq "pre: the hook does nothing" "0 100" "$(held)"
capture "$HOOK" post suspend-then-hibernate
assert_status "post: the hook succeeds" 0 "$STATUS"
assert_eq "post: the recorded window is back after resume" "60 65" "$(held)"

# --- dry run -------------------------------------------------------------------
laptop dry 0 100
real_sudo
capture haseen battery limit set 80 --dry-run
assert_status "dry-run succeeds" 0 "$STATUS"
assert_contains "it plans the floor write" "$OUTPUT" "DRYRUN: echo 75 | sudo tee $BAT/charge_control_start_threshold"
assert_contains "it plans the record" "$OUTPUT" "DRYRUN: write $HASEEN_SYSROOT/etc/haseen/charge-limit"
assert_eq "dry-run touched nothing" "0 100" "$(held)"
assert_eq "dry-run ran no sudo" "" "$(cat "$SANDBOX/sudo.log")"

# --- a machine without thresholds: restore is a quiet no-op ------------------
rm -rf "$SANDBOX/desktop"
mkdir -p "$SANDBOX/desktop/sys/class/power_supply/AC" "$SANDBOX/desktop/etc/haseen"
printf 'start=75\nend=80\n' >"$SANDBOX/desktop/etc/haseen/charge-limit"
export HASEEN_SYSROOT="$SANDBOX/desktop"
real_sudo
capture haseen battery limit restore
assert_status "restore on a desktop succeeds" 0 "$STATUS"
assert_eq "and does nothing" "" "$OUTPUT"
capture "$HOOK" post suspend
assert_status "the hook on a desktop succeeds" 0 "$STATUS"
capture haseen battery limit set 80
assert_status "set on a desktop is refused" 1 "$STATUS"
assert_contains "with the reason" "$OUTPUT" "no battery with charge_control thresholds"
capture haseen battery limit status
assert_contains "status says why" "$OUTPUT" "no charge_control thresholds"
capture haseen setup battery-limit on --yes
assert_status "setup on a desktop is refused" 1 "$STATUS"
assert_eq "without running sudo" "" "$(cat "$SANDBOX/sudo.log")"

# --- setup battery-limit: off by default, installs unit and hook --------------
laptop setup 75 80
real_sudo
capture haseen setup battery-limit status
assert_contains "off by default: not installed" "$OUTPUT" "installed: no"
assert_contains "off by default: not enabled" "$OUTPUT" "enabled:   no"
capture haseen setup battery-limit on --dry-run
assert_status "setup dry-run succeeds" 0 "$STATUS"
assert_contains "it installs the unit" "$OUTPUT" "DRYRUN: sudo install -Dm0644 $UNIT_FILE /etc/systemd/system/haseen-charge-limit.service"
assert_contains "it installs the sleep hook" "$OUTPUT" "DRYRUN: sudo install -Dm0755 $HOOK /usr/lib/systemd/system-sleep/haseen-charge-limit"
assert_contains "it records the current window" "$OUTPUT" "DRYRUN: write $HASEEN_SYSROOT/etc/haseen/charge-limit"
assert_contains "it enables the unit" "$OUTPUT" "DRYRUN: sudo systemctl enable --now haseen-charge-limit.service"
assert_eq "setup dry-run ran no sudo" "" "$(cat "$SANDBOX/sudo.log")"

unit="$(cat "$UNIT_FILE")"
assert_contains "the unit restores at start" "$unit" "ExecStart=/usr/bin/env haseen battery limit restore"
assert_contains "the unit records at stop" "$unit" "ExecStop=/usr/bin/env haseen battery limit save"
assert_contains "the unit is a lasting oneshot" "$unit" "RemainAfterExit=yes"

mkdir -p "$HASEEN_SYSROOT/etc/systemd/system/multi-user.target.wants"
touch "$HASEEN_SYSROOT/etc/systemd/system/multi-user.target.wants/haseen-charge-limit.service"
capture haseen battery limit status
assert_contains "status sees an enabled restore" "$OUTPUT" "restore:   on"
