# shellcheck shell=bash
# Power profiles: what the daemon offers, setting one, and remembering the
# choice per power source so a plug or unplug restores it.
sandbox powerprofile

export PPD_LOG="$SANDBOX/ppd.log"
: >"$PPD_LOG"
# A power-profiles-daemon that offers all three profiles, strongest first and
# with the active one starred, the way powerprofilesctl prints it.
stub powerprofilesctl '
case "$1" in
  list)
    printf "* performance:\n    Driver:     platform_profile\n  balanced:\n    Driver:     platform_profile\n  power-saver:\n    Driver:     platform_profile\n"
    ;;
  set)
    echo "$2" >>"$PPD_LOG"
    ;;
esac
'
last_set() { tail -n1 "$PPD_LOG"; }
state_dir="$HOME/.local/state/haseen/powerprofile"

# --- listing -----------------------------------------------------------------
capture haseen powerprofile list
assert_status "list succeeds" 0 "$STATUS"
assert_eq "profiles are listed weakest first" "power-saver
balanced
performance" "$OUTPUT"

capture haseen powerprofile list --active-state
assert_contains "--active-state marks the active profile" "$OUTPUT" "performance	1"
assert_contains "--active-state marks the inactive ones" "$OUTPUT" "balanced	0"

capture haseen powerprofile list --bogus
assert_status "an unknown flag is refused" 2 "$STATUS"

# --- on AC -------------------------------------------------------------------
export HASEEN_SYSROOT="$FIXTURES/power-ac"

capture haseen powerprofile set
assert_status "autodetect on AC succeeds" 0 "$STATUS"
assert_contains "the AC power source is detected" "$OUTPUT" "(ac)"
assert_eq "with nothing remembered, AC gets performance" performance "$(last_set)"

capture haseen powerprofile set autodetect power-saver
assert_status "naming a profile succeeds" 0 "$STATUS"
assert_eq "the named profile is applied" power-saver "$(last_set)"
assert_eq "and remembered under ac" power-saver "$(cat "$state_dir/ac")"

capture haseen powerprofile set autodetect turbo
assert_status "a profile the daemon does not offer is refused" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "power profile is not available: turbo"

# --- on battery --------------------------------------------------------------
export HASEEN_SYSROOT="$FIXTURES/power-battery"

capture haseen powerprofile set
assert_contains "the battery power source is detected" "$OUTPUT" "(battery)"
assert_eq "with nothing remembered, battery gets balanced" balanced "$(last_set)"
assert_eq "an autodetect fallback is not remembered" no "$([[ -e $state_dir/battery ]] && echo yes || echo no)"

capture haseen powerprofile set battery power-saver
assert_eq "the battery profile is applied" power-saver "$(last_set)"
assert_eq "and remembered under battery" power-saver "$(cat "$state_dir/battery")"

# Naming the other source without unplugging anything.
capture haseen powerprofile set ac performance
assert_eq "the AC profile can be set while on battery" performance "$(last_set)"

# --- the remembered profile survives a switch back ---------------------------
export HASEEN_SYSROOT="$FIXTURES/power-ac"
capture haseen powerprofile init
assert_status "init succeeds" 0 "$STATUS"
assert_eq "plugging in restores the remembered AC profile" performance "$(last_set)"

export HASEEN_SYSROOT="$FIXTURES/power-battery"
capture haseen powerprofile init
assert_eq "unplugging restores the remembered battery profile" power-saver "$(last_set)"

# A remembered profile the daemon stopped offering falls back instead of failing.
printf 'turbo\n' >"$state_dir/battery"
capture haseen powerprofile set
assert_status "a stale remembered profile does not fail" 0 "$STATUS"
assert_eq "it falls back to balanced on battery" balanced "$(last_set)"
printf 'power-saver\n' >"$state_dir/battery"

# --- a desktop: no battery at all --------------------------------------------
export HASEEN_SYSROOT="$FIXTURES/power-desktop"
capture haseen powerprofile set
assert_status "a machine with no battery succeeds" 0 "$STATUS"
assert_contains "a desktop counts as AC even with no mains sensor online" "$OUTPUT" "(ac)"
assert_eq "and gets the remembered AC profile" performance "$(last_set)"

# --- dry run changes nothing -------------------------------------------------
export HASEEN_SYSROOT="$FIXTURES/power-ac"
before="$(cat "$PPD_LOG")"
rm -f "$state_dir/ac"
capture haseen powerprofile set autodetect balanced --dry-run
assert_status "a dry run succeeds" 0 "$STATUS"
assert_dry_pure "powerprofile set" "$OUTPUT"
assert_contains "the dry run plans the daemon call" "$OUTPUT" "DRYRUN: powerprofilesctl set balanced"
assert_contains "and plans the remembered state file" "$OUTPUT" "DRYRUN: write $state_dir/ac"
assert_eq "the daemon was not called" "$before" "$(cat "$PPD_LOG")"
assert_eq "no state file was written" no "$([[ -e $state_dir/ac ]] && echo yes || echo no)"

capture haseen powerprofile init --dry-run
assert_dry_pure "powerprofile init" "$OUTPUT"
assert_eq "init changed nothing either" "$before" "$(cat "$PPD_LOG")"
