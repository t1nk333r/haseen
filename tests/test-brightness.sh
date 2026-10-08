# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# `haseen brightness`, `haseen setup ddc` and the haseen.display panel
# (plan 077): list/get over a fixture sysfs tree under HASEEN_SYSROOT, the
# brightnessctl and ddcutil calls recorded by stubs (the brightnessctl stub
# writes the fixture as the real one writes sysfs; the ddcutil stub answers
# detect/getvcp from files), the percent maths and clamping, the DDC bus
# cache, the dry run, the setup step, the manifest and default, the panel's
# Model.js under the real Qt JS engine, and the panel itself in the real
# Quickshell engine against the same fixture.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.display"
DEFAULT="$HASEEN_PATH/default/shell.json"

sandbox brightness
export LOG="$SANDBOX/calls.log" DDC_DETECT="$SANDBOX/ddc-detect.txt" DDC_VALUE="$SANDBOX/ddc-value" DDC_BUS=7
CACHE="$XDG_CACHE_HOME/haseen/ddc-displays.tsv"

# fixture NAME [nobacklight] [noi2c] — a machine: a 48000-step backlight at
# half, a 2-level keyboard backlight at 1, a caps-lock LED (not a keyboard
# backlight) and two i2c buses.
fixture() {
    local root="$SANDBOX/$1"
    rm -rf "$root"
    mkdir -p "$root/sys/class/leds/tpacpi::kbd_backlight" "$root/sys/class/leds/input3::capslock" "$root/dev"
    printf '2\n' >"$root/sys/class/leds/tpacpi::kbd_backlight/max_brightness"
    printf '1\n' >"$root/sys/class/leds/tpacpi::kbd_backlight/brightness"
    printf '1\n' >"$root/sys/class/leds/input3::capslock/max_brightness"
    printf '0\n' >"$root/sys/class/leds/input3::capslock/brightness"
    if [[ ${2:-} != nobacklight ]]; then
        mkdir -p "$root/sys/class/backlight/intel_backlight"
        printf '48000\n' >"$root/sys/class/backlight/intel_backlight/max_brightness"
        printf '24000\n' >"$root/sys/class/backlight/intel_backlight/brightness"
        printf '24000\n' >"$root/sys/class/backlight/intel_backlight/actual_brightness"
    fi
    [[ ${3:-} == noi2c ]] || touch "$root/dev/i2c-6" "$root/dev/i2c-7"
    printf '%s\n' "$root"
}

# detect_output BUS — `ddcutil detect --brief` as ddcutil 2.2 prints it: a
# monitor without DDC/CI ("Invalid display") and one on BUS.
detect_output() {
    printf '%s\n' 'Invalid display' '   I2C bus:          /dev/i2c-6' '   DRM connector:    card1-HDMI-A-1' \
        '   drm_connector_id: 415' '   Monitor:          AUS:ROG PG248Q:SERIAL1' '' 'Display 1' \
        "   I2C bus:          /dev/i2c-$1" '   DRM connector:    card1-DP-1' '   drm_connector_id: 393' \
        '   Monitor:          GSM:LG ULTRAGEAR:SERIAL2' '' >"$DDC_DETECT"
}

stub brightnessctl 'printf "brightnessctl %s\n" "$*" >>"$LOG"
for a; do case "$a" in --class=*) c=${a#--class=} ;; --device=*) d=${a#--device=} ;; esac; v=$a; done
dir="$HASEEN_SYSROOT/sys/class/$c/$d"
printf "%s\n" "$v" >"$dir/brightness"
[ -e "$dir/actual_brightness" ] && printf "%s\n" "$v" >"$dir/actual_brightness"
exit 0'
stub ddcutil 'printf "ddcutil %s\n" "$*" >>"$LOG"
case "$*" in
"detect --brief") [ -e "$DDC_DETECT.fail" ] && exit 1; cat "$DDC_DETECT" ;;
"--bus $DDC_BUS getvcp 10 --brief") echo "VCP 10 C $(cat "$DDC_VALUE") 100" ;;
*getvcp*) echo "No monitor detected on bus" >&2; exit 1 ;;
*" setvcp 10 "*) [ -e "$DDC_VALUE.refuse" ] && exit 1; for a; do v=$a; done; echo "$v" >"$DDC_VALUE" ;;
*) exit 1 ;;
esac'
detect_output 7
printf '40\n' >"$DDC_VALUE"
ROOT="$(fixture laptop)"
export HASEEN_SYSROOT="$ROOT"
BL="$ROOT/sys/class/backlight/intel_backlight"
KB="$ROOT/sys/class/leds/tpacpi::kbd_backlight"
T=$'\t'
calls() { cat "$LOG" 2>/dev/null; }
reset_log() { : >"$LOG"; }

# --- list and get -----------------------------------------------------------------
reset_log
capture haseen brightness list
assert_status "list succeeds" 0 "$STATUS"
assert_eq "list: backlight, keyboard backlight, the DDC monitor; no caps-lock LED, no invalid display" \
    "intel_backlight${T}backlight${T}50${T}24000${T}48000${T}Built-in display${T}$BL/actual_brightness
tpacpi::kbd_backlight${T}keyboard${T}50${T}1${T}2${T}Keyboard backlight${T}$KB/brightness
ddc:DP-1${T}ddc${T}40${T}40${T}100${T}LG ULTRAGEAR (DP-1)${T}-" "$OUTPUT"
assert_eq "list: one detect, one read of the monitor" "ddcutil detect --brief
ddcutil --bus 7 getvcp 10 --brief" "$(calls)"
assert_eq "the DDC bus is cached without the serial" "7${T}DP-1${T}LG ULTRAGEAR" "$(grep -v '^#' "$CACHE")"
assert_eq "with what the map depends on" "# boot= outputs= i2c=6,7" "$(head -n1 "$CACHE")"

reset_log
capture haseen brightness list --kind ddc
assert_eq "list --kind ddc: the monitor only" "ddc:DP-1" "$(cut -f1 <<<"$OUTPUT")"
assert_eq "a second list reads the cache, no detect" "ddcutil --bus 7 getvcp 10 --brief" "$(calls)"

reset_log
capture haseen brightness list --kind backlight,keyboard
assert_eq "list --kind backlight,keyboard" "intel_backlight tpacpi::kbd_backlight" "$(cut -f1 <<<"$OUTPUT" | paste -sd' ')"
assert_eq "sysfs kinds never probe DDC" "" "$(calls)"

capture haseen brightness get
assert_eq "get: the first backlight by default" "intel_backlight${T}backlight${T}50${T}24000${T}48000" "$(cut -f1-5 <<<"$OUTPUT")"
capture haseen brightness get kbd
assert_eq "get kbd: the keyboard backlight" "tpacpi::kbd_backlight${T}keyboard${T}50" "$(cut -f1-3 <<<"$OUTPUT")"
capture haseen brightness get tpacpi::kbd_backlight
assert_eq "get by sysfs name" "tpacpi::kbd_backlight" "$(cut -f1 <<<"$OUTPUT")"
capture haseen brightness get ddc:DP-1
assert_eq "get ddc:DP-1" "ddc:DP-1${T}ddc${T}40${T}40${T}100" "$(cut -f1-5 <<<"$OUTPUT")"
capture haseen brightness get input3::capslock
assert_status "a LED that is no keyboard backlight is no device" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "no brightness device 'input3::capslock'"

# The monitor moved to another bus: the cached one stops answering. While
# the map is fresh that is a monitor asleep or with DDC/CI off: it is left
# out and nothing is detected again (before, every call ran a detect).
detect_output 9
export DDC_BUS=9
reset_log
capture haseen brightness list --kind ddc
assert_eq "a fresh map: a monitor that does not answer is left out" "" "$OUTPUT"
assert_eq "and no detect on every call" "ddcutil --bus 7 getvcp 10 --brief" "$(calls)"
reset_log
capture haseen brightness up ddc
assert_status "up ddc with no monitor answering fails" 1 "$STATUS"
assert_eq "still without a detect" 0 "$(grep -c 'detect --brief' <<<"$(calls)")"
# Once the map is DDC_RETRY (10 min) old, one fresh detect finds it.
touch -d '-11 minutes' "$CACHE"
reset_log
capture haseen brightness list --kind ddc
assert_eq "an old map: a moved monitor is found again" "ddc:DP-1${T}ddc${T}40" "$(cut -f1-3 <<<"$OUTPUT")"
assert_eq "after exactly one fresh detect" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"
assert_eq "the cache follows" "9" "$(grep -v '^#' "$CACHE" | cut -f1)"
reset_log
capture haseen brightness list --kind ddc --rescan
assert_eq "--rescan detects again" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"

# A map with no monitor (made while it was off): looked for again once old.
printf '%s\n' 'Invalid display' '   I2C bus:          /dev/i2c-6' '' >"$DDC_DETECT"
capture haseen brightness list --kind ddc --rescan
detect_output 9
reset_log
capture haseen brightness list --kind ddc
assert_eq "an empty fresh map: nothing, no detect" "|" "$OUTPUT|$(calls)"
touch -d '-11 minutes' "$CACHE"
reset_log
capture haseen brightness list --kind ddc
assert_eq "an empty old map: detected again, the monitor found" "ddc:DP-1" "$(cut -f1 <<<"$OUTPUT")"
assert_eq "with one detect" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"

# A monitor plugged in later: the connected outputs change, the map follows.
mkdir -p "$ROOT/sys/class/drm/card1-DP-1" "$ROOT/sys/class/drm/card1-HDMI-A-1"
printf 'connected\n' >"$ROOT/sys/class/drm/card1-DP-1/status"
printf 'disconnected\n' >"$ROOT/sys/class/drm/card1-HDMI-A-1/status"
reset_log
capture haseen brightness list --kind ddc
assert_eq "a newly connected output detects again" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"
assert_eq "and records it" "# boot= outputs=card1-DP-1 i2c=6,7" "$(head -n1 "$CACHE")"
reset_log
capture haseen brightness list --kind ddc
assert_eq "then the map is used again" 0 "$(grep -c 'detect --brief' <<<"$(calls)")"

# A map from before maps had a signature (or a corrupt one) is replaced.
printf '9\tDP-1\tLG ULTRAGEAR\n' >"$CACHE"
reset_log
capture haseen brightness list --kind ddc
assert_eq "a map without a signature detects again" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"

# A failing detect: no temporary file left, and no detect on the next call.
rm -f "$CACHE"
touch "$DDC_DETECT.fail"
reset_log
capture haseen brightness list --kind ddc
capture haseen brightness list --kind ddc
rm "$DDC_DETECT.fail"
assert_eq "a failing detect runs once for two calls" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"
assert_eq "and leaves no temporary file" "ddc-displays.tsv" "$(find "${CACHE%/*}" -name 'ddc-displays*' -printf '%f\n')"

# A monitor detect gives no connector for: an empty field, not merged.
printf '%s\n' 'Display 1' '   I2C bus:          /dev/i2c-9' '   Monitor:          DEL:DELL U2415:SERIAL3' '' >"$DDC_DETECT"
capture haseen brightness list --kind ddc --rescan
assert_eq "no connector: the bus names it" "ddc:i2c-9${T}ddc${T}40${T}40${T}100${T}DELL U2415" "$(cut -f1-6 <<<"$OUTPUT")"
detect_output 9
capture haseen brightness list --kind ddc --rescan

# --- set: percent maths and clamping (brightnessctl gets raw values) ---------------------
last_call() { calls | tail -n1; }
setb() { printf '%s\n' "$1" >"$BL/brightness" && printf '%s\n' "$1" >"$BL/actual_brightness"; }
reset_log
capture haseen brightness set 10%
assert_status "set 10% succeeds" 0 "$STATUS"
assert_eq "set N%: N percent of max, raw, through logind's brightnessctl" \
    "brightnessctl --quiet --class=backlight --device=intel_backlight set 4800" "$(last_call)"
assert_eq "set prints the new line" "intel_backlight${T}backlight${T}10${T}4800${T}48000" "$(cut -f1-5 <<<"$OUTPUT")"
assert_eq "the fixture moved" "4800" "$(cat "$BL/actual_brightness")"
capture haseen brightness set +5%
assert_eq "set +N%: relative" "set 7200" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set intel_backlight -10%
assert_eq "set DEVICE -N%" "set 2400" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set -100%
assert_eq "a backlight never goes below raw 2" "set 2" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set 0%
assert_eq "set 0% at the floor writes nothing" "set 2" "$(last_call | grep -o 'set [0-9]*$')"
assert_eq "and prints the floor" "1" "$(calls | grep -c 'set 2$')"
capture haseen brightness set 1234
assert_eq "set N: a raw value" "set 1234" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set 99999
assert_eq "a raw value above max is clamped" "set 48000" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set 150%
assert_eq "150% is max (already there: no write)" "set 48000" "$(last_call | grep -o 'set [0-9]*$')"
setb 47990
capture haseen brightness set +1%
assert_eq "a relative step stops at max" "set 48000" "$(last_call | grep -o 'set [0-9]*$')"

# Leading zeros are decimal, and digits that would wrap round in 64-bit
# arithmetic are refused (before: 08 failed silently with exit 0, 010 was
# compared as octal 8, 2^63 and 10^20 % set raw 2).
capture haseen brightness set 010
assert_eq "set 010 is raw 10" "set 10|0" "$(last_call | grep -o 'set [0-9]*$')|$STATUS"
capture haseen brightness set 08
assert_eq "set 08 is raw 8, cleanly" "set 8|0|intel_backlight${T}backlight${T}0${T}8" "$(last_call | grep -o 'set [0-9]*$')|$STATUS|$(cut -f1-4 <<<"$OUTPUT")"
capture haseen brightness set 0000000000050%
assert_eq "zeros before a percentage" "set 24000" "$(last_call | grep -o 'set [0-9]*$')"
reset_log
for bad in 9223372036854775808 100000000000000000000% +100000000000000000000% -100000000000000000000% 1234567890; do
    capture haseen brightness set "$bad"
    assert_status "set $bad: too many digits is a usage error" 2 "$STATUS"
done
assert_eq "and nothing was written" "" "$(calls)"
setb 24000
capture haseen brightness up --step 8
eight="$(last_call | grep -o 'set [0-9]*$')"
setb 24000
capture haseen brightness up --step 08
assert_eq "--step 08 is --step 8" "0|$eight" "$STATUS|$(last_call | grep -o 'set [0-9]*$')"

# up/down: brightnessctl -e4's curve, 5 % a step, at least one raw unit.
setb 24000
capture haseen brightness up
assert_eq "up from 50 % on the 4th-power curve" "set 30238" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness down
assert_eq "down comes back" "set 24000" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness up --step 10
assert_eq "--step 10: (0.5^(1/4) + 0.10)^4 of 48000" "set 37619" "$(last_call | grep -o 'set [0-9]*$')"
setb 3
capture haseen brightness down
assert_eq "down near the bottom stops at raw 2" "set 2" "$(last_call | grep -o 'set [0-9]*$')"
reset_log
capture haseen brightness down
assert_status "down at the floor succeeds" 0 "$STATUS"
assert_eq "and writes nothing" "" "$(calls)"
setb 2
capture haseen brightness up
assert_eq "up from the floor: (2/48000)^(1/4) + 0.05, to the 4th, is 14" "set 14" "$(last_call | grep -o 'set [0-9]*$')"

# Keyboard backlight: linear, one level at least, 0 allowed.
capture haseen brightness up kbd
assert_eq "up kbd: one level (5 % of 2 rounds to 0)" \
    "brightnessctl --quiet --class=leds --device=tpacpi::kbd_backlight set 2" "$(last_call)"
reset_log
capture haseen brightness up kbd
assert_eq "up kbd at max writes nothing" "" "$(calls)"
capture haseen brightness set kbd 0%
assert_eq "a keyboard backlight may go off" "set 0" "$(last_call | grep -o 'set [0-9]*$')"
capture haseen brightness set kbd 60%
assert_eq "60% of 2 levels is 1" "set 1" "$(last_call | grep -o 'set [0-9]*$')"

# DDC: ddcutil setvcp on the cached bus, read again under the bus lock.
reset_log
capture haseen brightness set ddc:DP-1 70%
assert_status "set ddc succeeds" 0 "$STATUS"
assert_eq "set ddc: VCP 0x10 on the monitor's bus" "ddcutil --bus 9 setvcp 10 70" "$(last_call)"
assert_contains "read before the write" "$(calls)" "ddcutil --bus 9 getvcp 10 --brief"
capture haseen brightness up ddc
assert_eq "up ddc: every monitor, linear" "ddcutil --bus 9 setvcp 10 75" "$(last_call)"
capture haseen brightness down ddc:DP-1 --step 100
assert_eq "a monitor may go to 0" "ddcutil --bus 9 setvcp 10 0" "$(last_call)"

# A held key on DDC monitors: a repeat while a change runs is dropped, not
# queued (each would wait up to 5 s and keep stepping after the release).
# Sysfs backlights are fast, so a change there waits its turn.
lockf="$XDG_RUNTIME_DIR/haseen-brightness.lock"
hold_lock() { # SECONDS
    flock "$lockf" sleep "$1" &
    holder=$!
    for ((i = 0; i < 50; i++)); do flock -n "$lockf" true || return 0; sleep 0.05; done
}
hold_lock 2
reset_log
began=$SECONDS
capture haseen brightness up ddc
assert_status "a DDC repeat while a change runs succeeds" 0 "$STATUS"
assert_eq "and is dropped at once: no read, no write" "|0" "$(calls)|$((SECONDS - began > 1 ? 1 : 0))"
HASEEN_SYSROOT="$(fixture heldkey nobacklight)" capture haseen brightness up
assert_eq "no backlight: the default key is DDC, dropped too" "0|" "$STATUS|$(calls)"
wait "$holder" 2>/dev/null || true
hold_lock 1
capture haseen brightness down kbd
assert_eq "a keyboard backlight step waits for the one running" "0|set 0" "$STATUS|$(last_call | grep -o 'set [0-9]*$')"
wait "$holder" 2>/dev/null || true
capture haseen brightness set kbd 1

# No backlight: the keys move the monitors.
ROOT2="$(fixture desktop nobacklight)"
reset_log
HASEEN_SYSROOT="$ROOT2" capture haseen brightness up
assert_eq "no backlight: up moves the DDC monitors" "ddcutil --bus 9 setvcp 10 5" "$(last_call)"
ROOT3="$(fixture bare nobacklight noi2c)"
reset_log
HASEEN_SYSROOT="$ROOT3" capture haseen brightness list
assert_eq "no i2c devices: keyboard only, ddcutil never runs" "tpacpi::kbd_backlight|" "$(cut -f1 <<<"$OUTPUT" | paste -sd' ')|$(calls)"
HASEEN_SYSROOT="$ROOT3" capture haseen brightness up
assert_status "nothing to move is an error" 1 "$STATUS"
assert_contains "that says what is missing" "$OUTPUT" "no backlight and no DDC monitor found"

# --- usage errors ------------------------------------------------------------------------
for bad in "" "sideways" "set" "set a b c" "set foo" "set +5" "up --step 0" "list --kind lamp" "list x" "get a b" "up --bogus"; do
    # shellcheck disable=SC2086  # word splitting is the point
    capture haseen brightness $bad
    assert_status "usage error: '$bad'" 2 "$STATUS"
done
capture haseen brightness --help
assert_status "--help" 0 "$STATUS"
assert_contains "--help documents the floor" "$OUTPUT" "never go below raw 2"

# --- dry run -------------------------------------------------------------------------------
setb 24000
reset_log
capture haseen brightness set 25% --dry-run
assert_status "dry-run succeeds" 0 "$STATUS"
assert_dry_pure "set" "$OUTPUT"
assert_eq "dry-run prints the brightnessctl call only" \
    "DRYRUN: brightnessctl --quiet --class=backlight --device=intel_backlight set 12000" "$OUTPUT"
assert_eq "and runs nothing" "" "$(calls)"
assert_eq "the backlight did not move" "24000" "$(cat "$BL/actual_brightness")"
capture haseen brightness up kbd --dry-run
assert_eq "dry-run kbd" "DRYRUN: brightnessctl --quiet --class=leds --device=tpacpi::kbd_backlight set 2" "$OUTPUT"
printf '40\n' >"$DDC_VALUE"
reset_log
capture haseen brightness up ddc:DP-1 --dry-run
assert_eq "dry-run ddc prints the ddcutil call" "DRYRUN: ddcutil --bus 9 setvcp 10 45" "$OUTPUT"
assert_not_contains "and never writes the monitor" "$(calls)" "setvcp"
assert_eq "the monitor did not move" "40" "$(cat "$DDC_VALUE")"

# A dry run that has to detect (no map, or one made for another signature)
# resolves the monitor from that detect and still touches nothing: no cache
# directory, no cache file, no temporary file, an old map left as it was.
rm -rf "${CACHE%/*}"
reset_log
capture haseen brightness up ddc:DP-1 --dry-run
assert_status "dry-run ddc without a map succeeds" 0 "$STATUS"
assert_eq "without a map: the call from a fresh detect" "DRYRUN: ddcutil --bus 9 setvcp 10 45" "$OUTPUT"
assert_eq "without a map: it detected" 1 "$(grep -c 'detect --brief' <<<"$(calls)")"
assert_eq "without a map: no cache directory made" no "$([[ -e ${CACHE%/*} ]] && echo yes || echo no)"
capture haseen brightness list --kind ddc --rescan --dry-run
assert_eq "list --rescan --dry-run lists from the detect" "ddc:DP-1" "$(cut -f1 <<<"$OUTPUT")"
assert_eq "and makes no cache either" no "$([[ -e ${CACHE%/*} ]] && echo yes || echo no)"
mkdir -p "${CACHE%/*}"
printf '# boot=another outputs= i2c=6,7\n7\tDP-1\tLG ULTRAGEAR\n' >"$CACHE"
touch -d '-1 hour' "$CACHE"
stale="$(stat -c '%Y %s' "$CACHE")"
reset_log
capture haseen brightness set ddc:DP-1 50% --dry-run
assert_eq "a map for another signature: the call from a fresh detect, not the stale bus" "DRYRUN: ddcutil --bus 9 setvcp 10 50" "$OUTPUT"
assert_eq "the stale map is not replaced" "# boot=another outputs= i2c=6,7|$stale" "$(head -n1 "$CACHE")|$(stat -c '%Y %s' "$CACHE")"
assert_eq "and no temporary file is left" "ddc-displays.tsv" "$(find "${CACHE%/*}" -name 'ddc-displays*' -printf '%f\n')"
assert_eq "the monitor did not move in any dry run" "40" "$(cat "$DDC_VALUE")"

# --- haseen setup ddc ----------------------------------------------------------------------
export HASEEN_INLINE=1
recorder() {
    : >"$SANDBOX/sudo.log"
    stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'; case \"\$1\" in tee) cat >/dev/null ;; esac; exit 0"
}
# machine NAME — an Arch sysroot (os-release, pacman's local db); the NixOS
# ones copy tests/fixtures/nixos's os-release instead.
machine() {
    local root="$SANDBOX/setup-$1"
    rm -rf "$root"
    mkdir -p "$root/etc" "$root/var/lib/pacman/local" "$root/sys/module" "$root/dev"
    printf 'NAME="Arch Linux"\nID=arch\n' >"$root/etc/os-release"
    printf '%s\n' "$root"
}
nixos_machine() {
    local root="$SANDBOX/setup-$1"
    rm -rf "$root"
    mkdir -p "$root/etc" "$root/sys/module" "$root/dev"
    cp "$REPO/tests/fixtures/nixos/etc/os-release" "$root/etc/os-release"
    printf '%s\n' "$root"
}
SROOT="$(machine empty)"
export HASEEN_SYSROOT="$SROOT"
capture haseen setup ddc on --dry-run
assert_status "setup ddc on --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "setup ddc on" "$OUTPUT"
assert_contains "it installs ddcutil from the repos" "$OUTPUT" "DRYRUN: sudo pacman -S --needed ddcutil"
assert_contains "it loads i2c-dev through common.sh" "$OUTPUT" "DRYRUN: sudo modprobe i2c-dev"
assert_not_contains "a fresh module needs no udev replay" "$OUTPUT" "udevadm"

SROOT="$(machine loaded)"
mkdir -p "$SROOT/sys/module/i2c_dev"
export HASEEN_SYSROOT="$SROOT"
recorder
capture haseen setup ddc on --yes
assert_status "setup ddc on succeeds" 0 "$STATUS"
assert_contains "ddcutil is installed" "$(cat "$SANDBOX/sudo.log")" "pacman -S --needed --noconfirm ddcutil"
assert_contains "i2c-dev already loaded: its devices get the package's uaccess rule" \
    "$(cat "$SANDBOX/sudo.log")" "udevadm trigger --action=add --subsystem-match=i2c-dev"
assert_not_contains "no modprobe" "$(cat "$SANDBOX/sudo.log")" "modprobe"

SROOT="$(machine on)"
mkdir -p "$SROOT/sys/module/i2c_dev" "$SROOT/var/lib/pacman/local/ddcutil-2.2.7-1"
touch "$SROOT/dev/i2c-9"
export HASEEN_SYSROOT="$SROOT"
recorder
capture haseen setup ddc on --yes
assert_contains "installed and loaded: already on" "$OUTPUT" "already on"
assert_eq "and nothing privileged ran" "" "$(cat "$SANDBOX/sudo.log")"
printf '40\n' >"$DDC_VALUE"
capture haseen setup ddc
assert_status "status is the default verb" 0 "$STATUS"
assert_contains "status: installed" "$OUTPUT" "installed: yes"
assert_contains "status: loaded" "$OUTPUT" "i2c-dev:   yes"
assert_contains "status: the monitors" "$OUTPUT" "monitors:  ddc:DP-1  LG ULTRAGEAR (DP-1)"
capture haseen setup ddc off --dry-run
assert_status "off --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "setup ddc off" "$OUTPUT"
assert_contains "off removes ddcutil" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm ddcutil"
assert_contains "and the bus cache" "$OUTPUT" "DRYRUN: rm -f -- $CACHE"

HASEEN_SYSROOT="$(machine off)"
export HASEEN_SYSROOT
capture haseen setup ddc off --yes
assert_contains "off without ddcutil is a no-op" "$OUTPUT" "already off"
capture haseen setup ddc status
assert_contains "status: not installed" "$OUTPUT" "installed: no"
capture haseen setup ddc sideways
assert_status "an unknown verb is a usage error" 2 "$STATUS"

# NixOS: the flake owns DDC. on and off refuse with verb-specific guidance
# and run nothing; status reads the command, not pacman's database.
HASEEN_SYSROOT="$(nixos_machine nixos)"
export HASEEN_SYSROOT
for verb in on off; do
    recorder
    capture haseen setup ddc "$verb" --yes
    assert_status "NixOS: setup ddc $verb refuses" 1 "$STATUS"
    if [[ $verb == on ]]; then
        assert_contains "NixOS: on enables the DDC option" "$OUTPUT" "set haseen.ddc.enable = true"
        assert_contains "NixOS: on names the i2c prerequisite" "$OUTPUT" "hardware.i2c.enable = true"
        assert_contains "NixOS: on names the user's i2c group" "$OUTPUT" "add your user to the i2c group"
    else
        assert_contains "NixOS: off disables the DDC option" "$OUTPUT" "set haseen.ddc.enable = false"
        assert_contains "NixOS: off rebuilds the system" "$OUTPUT" "nixos-rebuild switch"
        assert_not_contains "NixOS: off does not enable DDC" "$OUTPUT" "haseen.ddc.enable = true"
    fi
    assert_not_contains "NixOS: $verb says nothing of pacman" "$OUTPUT" "pacman"
    assert_eq "NixOS: $verb runs nothing privileged" "" "$(cat "$SANDBOX/sudo.log")"
    capture haseen setup ddc "$verb" --dry-run
    assert_status "NixOS: $verb --dry-run refuses too" 1 "$STATUS"
    if [[ $verb == on ]]; then
        assert_contains "NixOS: on --dry-run keeps its option hint" "$OUTPUT" "haseen.ddc.enable = true"
    else
        assert_contains "NixOS: off --dry-run keeps its option hint" "$OUTPUT" "haseen.ddc.enable = false"
    fi
done
mkdir -p "$HASEEN_SYSROOT/sys/module/i2c_dev"
touch "$HASEEN_SYSROOT/dev/i2c-9"
capture haseen setup ddc status
assert_status "NixOS: status works" 0 "$STATUS"
assert_contains "NixOS: ddcutil on PATH counts as installed (no pacman database)" "$OUTPUT" "installed: yes"
assert_contains "NixOS: status finds the monitors" "$OUTPUT" "monitors:  ddc:DP-1  LG ULTRAGEAR (DP-1)"
assert_contains "NixOS: status names the option" "$OUTPUT" "NixOS:     haseen.ddc.enable"
capture haseen setup ddc --help
assert_contains "--help explains enabling DDC on NixOS" "$OUTPUT" "on:  set haseen.ddc.enable = true"
assert_contains "--help explains the i2c prerequisite" "$OUTPUT" "hardware.i2c.enable = true"
assert_contains "--help explains disabling DDC on NixOS" "$OUTPUT" "off: set haseen.ddc.enable = false"
assert_contains "--help explains rebuilding after changing DDC" "$OUTPUT" "nixos-rebuild switch"
unset HASEEN_INLINE

# --- manifest and default ---------------------------------------------------------------------
capture haseen plugin validate haseen.display
assert_status "display validates" 0 "$STATUS"
assert_contains "display ok" "$OUTPUT" "ok: haseen.display (builtin:"
assert_eq "a panel only" '["panel"]' "$(jq -c .kinds "$PLUGIN/manifest.json")"
assert_eq "off by default" "false" "$(jq '.plugins["haseen.display"].enabled' "$DEFAULT")"
assert_eq "in no bar section and no services" "false" \
    "$(jq '[.bar.left, .bar.center, .bar.right, .services] | flatten | index("haseen.display") != null' "$DEFAULT")"

# --- the panel model under the real Qt JS engine -------------------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as M

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL threw " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        const text = "ddc:DP-1\tddc\t40\t40\t100\tLG (DP-1)\t-\n"
            + "intel_backlight\tbacklight\t50\t24000\t48000\tBuilt-in display\t/s/bl/actual_brightness\n"
            + "junk line\n"
            + "x\tlamp\t1\t1\t1\tLamp\t-\n"
            + "acpi_video0\tbacklight\t20\t2\t10\tBuilt-in display\t/s/a/actual_brightness\n"
            + "intel_backlight\tbacklight\t1\t1\t48000\tdup\t/s/dup\n"
            + "k\tkeyboard\t50\t1\t0\tKeyboard\t/s/k\n";
        const list = M.parseList(text);
        eq("parse: kinds in order, junk, unknown kinds, max 0 and duplicate ids dropped",
           ["intel_backlight", "acpi_video0", "ddc:DP-1"], list.map(d => d.id));
        eq("parse: fields", { id: "ddc:DP-1", kind: "ddc", value: 40, max: 100, name: "LG (DP-1)", watch: "", label: "LG (DP-1)" }, list[2]);
        eq("parse: the watch path", "/s/bl/actual_brightness", list[0].watch);
        eq("parse: repeated names get their id", ["Built-in display · intel_backlight", "Built-in display · acpi_video0"], [list[0].label, list[1].label]);
        eq("parse: empty", [], M.parseList(""));
        eq("parse: a value above max is held at max", 10, M.parseList("a\tbacklight\t0\t99\t10\tA\t/a")[0].value);
        eq("merge: sysfs first, an id once", ["a", "b", "c"], M.merge([{ id: "a" }, { id: "b" }], [{ id: "b" }, { id: "c" }]).map(d => d.id));
        eq("percent", [0, 50, 100, 0, 0, 33], [M.percent(0, 100), M.percent(24000, 48000), M.percent(48000, 48000), M.percent(5, 0), M.percent(-1, 10), M.percent(1, 3)]);
        eq("fromFraction: smooth on a fine device", [0, 50, 100, 100, 0], [0, 0.5, 1, 1.4, -0.2].map(x => M.fromFraction(x, 48000)));
        eq("fromFraction: snaps to a 3-level keyboard", [0, 33, 67, 100], [0.1, 0.4, 0.6, 0.9].map(x => M.fromFraction(x, 3)));
        eq("fromFraction: a monitor 0..100", 37, M.fromFraction(0.37, 100));
        eq("setArgs: clamped whole percent", [["set", "a", "42%"], ["set", "a", "100%"], ["set", "a", "0%"]],
           [M.setArgs("a", 41.6), M.setArgs("a", 130), M.setArgs("a", -4)]);
        eq("live: sysfs while dragging, DDC on release", [true, true, false], ["backlight", "keyboard", "ddc"].map(M.live));
        eq("valueFor: DDC shows what was asked", [70, 0, 100], [70, -5, 120].map(p => M.valueFor({ max: 100 }, p)));
        const q1 = M.enqueue([], "a", ["x", "a1"]);
        const q2 = M.enqueue(q1, "b", ["x", "b1"]);
        const q3 = M.enqueue(q2, "a", ["x", "a2"]);
        eq("enqueue: one per device, the newest value, its first place kept", [["a", "a2"], ["b", "b1"]], q3.map(e => [e.id, e.command[1]]));
        eq("enqueue: never mutates", 1, q1.length);
        eq("glyphs", ["\uf185", "\uf11c", "\u{F0379}", "\uf185"], ["backlight", "keyboard", "ddc", "?"].map(M.glyph));
        eq("toInt", [12, -1, -1, 0], ["12\n", "", "x", " 0 "].map(M.toInt));
        eq("emptyText", ["", "", true], [M.emptyText(1, true), M.emptyText(0, false), M.emptyText(0, true).indexOf("haseen setup ddc on") > 0]);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "qml unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" "19" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the panel in the real engine ------------------------------------------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; panel scenario not run" >&2
else
    ROOT="$(fixture engine)"
    export HASEEN_SYSROOT="$ROOT"
    BL="$ROOT/sys/class/backlight/intel_backlight"
    detect_output 7
    export DDC_BUS=7
    printf '40\n' >"$DDC_VALUE"
    rm -f "$CACHE"
    reset_log
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import "plugins/haseen.display" as Display
ShellRoot {
    id: shell

    property var opened: null
    property var watched: null
    property var written: null
    property int asked: -1

    function view() {
        const out = {};
        for (const d of panel.devices)
            out[d.id] = panel.valueOf(d);
        return out;
    }

    function find(id) {
        return panel.find(id);
    }

    Display.Panel {
        id: panel

        pluginId: "haseen.display"
        settings: ({ debugIpc: true })
    }

    // The monitor starts refusing writes.
    Process {
        id: refuse

        command: ["touch", Quickshell.env("DDC_VALUE") + ".refuse"]
    }

    // Firmware moves the backlight: only the watch can tell the panel.
    Process {
        id: firmware

        command: ["sh", "-c", "printf '12000\\n' >\"$1\"", "sh", Quickshell.env("BL") + "/actual_brightness"]
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            shell.opened = { ids: panel.devices.map(d => d.id), labels: panel.devices.map(d => d.label), values: shell.view(), ddcDone: panel.ddcDone };
            firmware.running = true;
            step2.running = true;
        }
    }

    Timer {
        id: step2

        interval: 1000
        onTriggered: {
            shell.watched = shell.view();
            const bl = shell.find("intel_backlight");
            panel.send(bl, 80);
            panel.send(bl, 50);
            panel.send(bl, 30);
            panel.send(shell.find("ddc:DP-1"), 70);
            panel.send(shell.find("tpacpi::kbd_backlight"), 0);
            step3.running = true;
        }
    }

    Timer {
        id: step3

        interval: 5000
        onTriggered: {
            shell.written = { final: shell.view(), sent: panel.sent, busy: panel.busy, errors: panel.errors };
            refuse.running = true;
            step4.running = true;
        }
    }

    Timer {
        id: step4

        interval: 500
        onTriggered: {
            panel.send(shell.find("ddc:DP-1"), 20);
            shell.asked = shell.view()["ddc:DP-1"];
            step5.running = true;
        }
    }

    Timer {
        id: step5

        interval: 3000
        onTriggered: {
            console.warn("RESULT " + JSON.stringify({ opened: shell.opened, watched: shell.watched, final: shell.written.final, sent: shell.written.sent, busy: shell.written.busy, errors: shell.written.errors, nightlight: panel.nightlightShown, asked: shell.asked, refused: shell.view()["ddc:DP-1"], refusedErrors: panel.errors, refusedBusy: panel.busy }));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 BL="$BL" DDC_VALUE="$DDC_VALUE" \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "panel: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    assert_eq "panel: the three devices on open" '["intel_backlight","tpacpi::kbd_backlight","ddc:DP-1"]' "$(jq -c .opened.ids <<<"$RESULT")"
    assert_eq "panel: their labels" '["Built-in display","Keyboard backlight","LG ULTRAGEAR (DP-1)"]' "$(jq -c .opened.labels <<<"$RESULT")"
    assert_eq "panel: their values" '{"intel_backlight":24000,"tpacpi::kbd_backlight":1,"ddc:DP-1":40}' "$(jq -c .opened.values <<<"$RESULT")"
    assert_eq "panel: a firmware change reaches the slider through the watch" 12000 "$(jq '.watched.intel_backlight' <<<"$RESULT")"
    assert_eq "panel: one write at a time; a newer value replaces the waiting one" \
        '["set intel_backlight 80%","set intel_backlight 30%","set ddc:DP-1 70%","set tpacpi::kbd_backlight 0%"]' "$(jq -c .sent <<<"$RESULT")"
    assert_eq "panel: the queue drained" false "$(jq .busy <<<"$RESULT")"
    assert_eq "panel: no error while every write lands" '{}' "$(jq -c .errors <<<"$RESULT")"
    assert_eq "panel: values after the writes (sysfs from the watch, DDC as asked)" \
        '{"intel_backlight":14400,"tpacpi::kbd_backlight":0,"ddc:DP-1":70}' "$(jq -c .final <<<"$RESULT")"
    assert_eq "panel: the writes, through haseen brightness" "brightnessctl --quiet --class=backlight --device=intel_backlight set 38400
brightnessctl --quiet --class=backlight --device=intel_backlight set 14400
ddcutil --bus 7 setvcp 10 70
brightnessctl --quiet --class=leds --device=tpacpi::kbd_backlight set 0
ddcutil --bus 7 setvcp 10 20" "$(grep -E 'brightnessctl|setvcp' "$LOG")"
    assert_eq "panel: DDC read on open and before each write only" 3 "$(grep -c 'getvcp' "$LOG")"
    assert_eq "panel: the night light row with haseen.nightlight running" true "$(jq .nightlight <<<"$RESULT")"
    assert_eq "panel: a DDC write shows the value asked for at once" 20 "$(jq .asked <<<"$RESULT")"
    assert_eq "panel: a refused write puts the slider back to the value the monitor took" 70 "$(jq .refused <<<"$RESULT")"
    assert_eq "panel: and says so under the row" '{"ddc:DP-1":"LG ULTRAGEAR (DP-1) did not accept the change"}' "$(jq -c .refusedErrors <<<"$RESULT")"
    assert_eq "panel: the refused write still ends the queue" false "$(jq .refusedBusy <<<"$RESULT")"
    rm -f "$DDC_VALUE.refuse"
fi
unset HASEEN_SYSROOT
