# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 060: `haseen battery status` (and the omarchy-battery-status shim
# behind Omarchy power plugins) reads the battery and its charge-limit window
# from the kernel, never UPower's fixed 75-80% default. Fake power_supply
# trees under HASEEN_SYSROOT stand in for the hardware.
sandbox battery-status

# A UPower that reports the ThinkPad default window whatever the hardware
# holds: if anything still asked it, the 75-80% would show up below.
stub upower 'printf "  charge-start-threshold:        75%%\n  charge-end-threshold:          80%%\n"'

# battery ROOT STATUS CAPACITY START END [AC] — a ThinkPad-like BAT0 with
# energy files (46.7 Wh full, 6.6 W draw) and a mains supply.
battery() {
    local root="$1" d="$1/sys/class/power_supply"
    rm -rf "$root"
    mkdir -p "$d/BAT0" "$d/AC" "$d/hidpp_battery_0"
    printf 'Battery\n' >"$d/BAT0/type"
    printf '%s\n' "$2" >"$d/BAT0/status"
    printf '%s\n' "$3" >"$d/BAT0/capacity"
    printf '%s\n' "$4" >"$d/BAT0/charge_control_start_threshold"
    printf '%s\n' "$5" >"$d/BAT0/charge_control_end_threshold"
    printf '46700000\n' >"$d/BAT0/energy_full"
    printf '%s\n' "$(($3 * 467000))" >"$d/BAT0/energy_now"
    printf '6600000\n' >"$d/BAT0/power_now"
    printf '272\n' >"$d/BAT0/cycle_count"
    printf 'Mains\n' >"$d/AC/type"
    printf '%s\n' "${6:-1}" >"$d/AC/online"
    # A wireless mouse is a Battery too, scoped to its device: never ours.
    printf 'Battery\n' >"$d/hidpp_battery_0/type"
    printf 'Device\n' >"$d/hidpp_battery_0/scope"
    printf '5\n' >"$d/hidpp_battery_0/capacity"
    export HASEEN_SYSROOT="$root"
}

# --- the limit off: the hardware's 0-100%, not UPower's 75-80% ---------------
battery "$SANDBOX/off" Charging 95 0 100
capture haseen battery status --shell
assert_status "shell output succeeds" 0 "$STATUS"
assert_contains "percentage from the system battery, not the mouse" "$OUTPUT" "percentage	95%"
assert_contains "charging" "$OUTPUT" "state	charging"
assert_contains "draw in watts" "$OUTPUT" "rate	6.6W"
assert_contains "capacity in whole Wh" "$OUTPUT" "size	46Wh"
assert_contains "time to full" "$OUTPUT" "time	21m"
assert_contains "cycles" "$OUTPUT" "cycles	272"
assert_contains "the window is the hardware's" "$OUTPUT" "threshold	0-100%"
assert_not_contains "never UPower's default" "$OUTPUT" "75-80"

# --- a limit set: the window follows the sysfs files -------------------------
battery "$SANDBOX/limit" "Not charging" 80 75 80
capture haseen battery status --shell
assert_contains "the set window" "$OUTPUT" "threshold	75-80%"
assert_contains "held by the limit on AC" "$OUTPUT" "state	holding"
capture haseen battery status
assert_eq "one-line form says it is holding" "Battery 80%  ·  Holding at 75-80%  ·  6.6W / 46Wh" "$OUTPUT"

# Charging with no current at the end threshold also holds.
battery "$SANDBOX/idle" Charging 80 75 80
printf '0\n' >"$HASEEN_SYSROOT/sys/class/power_supply/BAT0/power_now"
capture haseen battery status --shell
assert_contains "no current at the ceiling is holding" "$OUTPUT" "state	holding"

# Equal start and end print one number.
battery "$SANDBOX/single" Discharging 50 80 80 0
capture haseen battery status --shell
assert_contains "a single-value window" "$OUTPUT" "threshold	80%"
assert_contains "on battery it discharges" "$OUTPUT" "state	discharging"
assert_contains "time to empty" "$OUTPUT" "time	3h 32m"
capture haseen battery status
assert_contains "one-line form on battery" "$OUTPUT" "Battery 50%  ·  3h 32m left"

# --- no battery: nothing, successfully ---------------------------------------
mkdir -p "$SANDBOX/desktop/sys/class/power_supply"
export HASEEN_SYSROOT="$SANDBOX/desktop"
capture haseen battery status --shell
assert_status "a desktop succeeds" 0 "$STATUS"
assert_eq "and prints nothing" "" "$OUTPUT"

capture haseen battery status --bogus
assert_status "an unknown flag is refused" 2 "$STATUS"
