# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen screen off|on` (plan 084): the DPMS dispatcher for Lua-mode and
# legacy Hyprland, dry-run purity, and the off never reaching Hyprland before
# its delay (a stub hyprctl stamps every dispatch with the time).

sandbox screen
export SCREEN_LOG="$SANDBOX/hyprctl.log" SCREEN_MODE="$SANDBOX/mode"
: >"$SCREEN_LOG"
echo lua >"$SCREEN_MODE"
# Hyprland 0.56 answers `status -j` with its config provider; an older one
# has no such request. Dispatches are logged as "NANOS ARGC ARGS".
stub hyprctl 'case "$1" in
status)
    if [ "$(cat "$SCREEN_MODE")" = lua ]; then echo "{\"configProvider\":\"lua\",\"backend\":\"drm\"}"; else echo "unknown request"; fi
    ;;
dispatch)
    shift
    printf "%s %s %s\n" "$(date +%s%N)" "$#" "$*" >>"$SCREEN_LOG"
    if [ -n "${SCREEN_REFUSE:-}" ]; then echo "Invalid dispatcher"; else echo ok; fi
    ;;
*) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;;
esac'
now() { date +%s%N; }
ms_since() { echo $((($(now) - $1) / 1000000)); }
dispatches() { cut -d' ' -f2- "$SCREEN_LOG"; }

# --- help and listing --------------------------------------------------------
capture haseen screen off --help
assert_status "off --help" 0 "$STATUS"
assert_contains "off --help: usage" "$OUTPUT" "Usage: haseen screen off [--delay MS] [--dry-run]"
capture haseen screen on --help
assert_contains "on --help: usage" "$OUTPUT" "Usage: haseen screen on [--dry-run]"
capture haseen commands screen
assert_contains "listed: off" "$OUTPUT" "haseen screen off [--delay MS] [--dry-run]"
assert_contains "listed: on" "$OUTPUT" "haseen screen on [--dry-run]"

# --- dry-run argv, Lua mode -------------------------------------------------------
start=$(now)
capture haseen screen off --dry-run
assert_status "off --dry-run (lua)" 0 "$STATUS"
assert_eq "off --dry-run (lua): the wait, then the Lua dispatcher" 'DRYRUN: sleep 1.000
DRYRUN: hyprctl dispatch hl.dsp.dpms({ action = "disable" })' "$OUTPUT"
assert_eq "off --dry-run does not wait" yes "$( (($(ms_since "$start") < 700)) && echo yes || echo no)"
capture haseen screen off --delay 250 --dry-run
assert_eq "off --delay 250 --dry-run (lua)" 'DRYRUN: sleep 0.250
DRYRUN: hyprctl dispatch hl.dsp.dpms({ action = "disable" })' "$OUTPUT"
capture haseen screen off --delay=0 --dry-run
assert_eq "off --delay=0 --dry-run (lua): no wait" 'DRYRUN: hyprctl dispatch hl.dsp.dpms({ action = "disable" })' "$OUTPUT"
capture haseen screen on --dry-run
assert_status "on --dry-run (lua)" 0 "$STATUS"
assert_eq "on --dry-run (lua)" 'DRYRUN: hyprctl dispatch hl.dsp.dpms({ action = "enable" })' "$OUTPUT"
assert_eq "dry-runs dispatch nothing (lua)" "" "$(cat "$SCREEN_LOG")"

# --- dry-run argv, legacy ---------------------------------------------------------
echo legacy >"$SCREEN_MODE"
capture haseen screen off --dry-run
assert_eq "off --dry-run (legacy)" 'DRYRUN: sleep 1.000
DRYRUN: hyprctl dispatch dpms off' "$OUTPUT"
capture haseen screen off --delay 1500 --dry-run
assert_eq "off --delay 1500 --dry-run (legacy)" 'DRYRUN: sleep 1.500
DRYRUN: hyprctl dispatch dpms off' "$OUTPUT"
capture haseen screen on --dry-run
assert_eq "on --dry-run (legacy)" 'DRYRUN: hyprctl dispatch dpms on' "$OUTPUT"
assert_eq "dry-runs dispatch nothing (legacy)" "" "$(cat "$SCREEN_LOG")"

# --- the off waits for its delay ------------------------------------------------------
# Legacy: the dispatcher and its argument are separate words (argc 2).
start=$(now)
capture haseen screen off
assert_status "off (legacy)" 0 "$STATUS"
assert_eq "off (legacy): dpms off, two words" "2 dpms off" "$(dispatches)"
took=$((($(cut -d' ' -f1 "$SCREEN_LOG") - start) / 1000000))
assert_eq "off (legacy): no dispatch before the default 1000 ms" yes "$( ((took >= 1000)) && echo yes || echo "no ($took ms)")"
: >"$SCREEN_LOG"
capture haseen screen on
assert_eq "on (legacy): dpms on, at once" "2 dpms on" "$(dispatches)"

echo lua >"$SCREEN_MODE"
: >"$SCREEN_LOG"
# Watched while it waits: nothing at 1.2 s, the off once 1.5 s have passed.
start=$(now)
haseen screen off --delay 1500 >"$SANDBOX/off.out" 2>&1 &
off_pid=$!
sleep 1.2
assert_eq "off --delay 1500 (lua): nothing dispatched at 1.2 s" "" "$(cat "$SCREEN_LOG")"
rc=0
wait "$off_pid" || rc=$?
assert_eq "off --delay 1500 (lua): exits 0" 0 "$rc"
assert_eq "off (lua): one Lua dispatcher, one word" '1 hl.dsp.dpms({ action = "disable" })' "$(dispatches)"
took=$((($(cut -d' ' -f1 "$SCREEN_LOG") - start) / 1000000))
assert_eq "off --delay 1500 (lua): dispatched at 1500 ms or later" yes "$( ((took >= 1500)) && echo yes || echo "no ($took ms)")"
: >"$SCREEN_LOG"
start=$(now)
capture haseen screen off --delay 0
assert_eq "off --delay 0 (lua): at once" '1 hl.dsp.dpms({ action = "disable" })' "$(dispatches)"
assert_eq "off --delay 0: under 700 ms" yes "$( (($(ms_since "$start") < 700)) && echo yes || echo no)"
: >"$SCREEN_LOG"
capture haseen screen on
assert_status "on (lua)" 0 "$STATUS"
assert_eq "on (lua)" '1 hl.dsp.dpms({ action = "enable" })' "$(dispatches)"

# --- refusals ------------------------------------------------------------------------
: >"$SCREEN_LOG"
capture haseen screen off --delay abc
assert_status "off --delay abc" 1 "$STATUS"
assert_contains "off --delay abc says why" "$OUTPUT" "--delay takes 0-60000 milliseconds, not 'abc'"
capture haseen screen off --delay 60001
assert_status "off --delay over a minute" 1 "$STATUS"
capture haseen screen off --delay
assert_status "off --delay without a value" 2 "$STATUS"
capture haseen screen off now
assert_status "off rejects an unknown argument" 2 "$STATUS"
capture haseen screen on please
assert_status "on rejects an argument" 2 "$STATUS"
assert_eq "refused arguments dispatch nothing" "" "$(cat "$SCREEN_LOG")"
capture env SCREEN_REFUSE=1 haseen screen on
assert_status "a refused dispatcher fails" 1 "$STATUS"
assert_contains "a refused dispatcher says so" "$OUTPUT" "Hyprland refused"
