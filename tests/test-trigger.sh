# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Trigger commands (plan 018): capture, screen recording flag lifecycle,
# reminders, Hyprland toggles, hardware switches, share, tests, transcode.
# Dry runs print a plan and touch nothing; real runs only hit scripted fakes.

# trig_sandbox NAME [MODE] — sandbox with fakes. MODE=live makes hyprctl
# answer every call (logged to $CALLS); default hyprctl answers reads only and
# fails like any stub on a mutation.
trig_sandbox() {
    sandbox "$1"
    export XDG_RUNTIME_DIR="$SANDBOX/run" HASEEN_INLINE=1
    mkdir -p "$XDG_RUNTIME_DIR"
    CALLS="$SANDBOX/calls"
    : >"$CALLS"
    FLAG="$HOME/.local/state/haseen/flags/recording"
    export CALLS
    stub notify-send 'echo "notify-send $*" >>"$CALLS"'
    stub wl-copy 'printf "wl-copy %s: " "$*" >>"$CALLS"; cat >>"$CALLS"; echo >>"$CALLS"'
    stub xdg-user-dir 'echo "$HOME/$1"'
    stub systemd-run 'echo "systemd-run $*" >>"$CALLS"'
    stub localsend 'echo "localsend $*" >>"$CALLS"'
    # Present (so dry-run plans do not depend on the host having it) but
    # fatal if run; the lifecycle test replaces it with a fake recorder.
    stub gpu-screen-recorder 'echo "STUB-CALLED: gpu-screen-recorder $*" >&2; exit 97'
    local mut='echo "STUB-CALLED: hyprctl $*" >&2; exit 97'
    [[ ${2:-} == live ]] && mut='echo "hyprctl $*" >>"$CALLS"; echo ok'
    stub hyprctl "case \"\$1\" in
activeworkspace) echo '{\"id\":3,\"tiledLayout\":\"dwindle\"}' ;;
devices) echo '{\"mice\":[{\"name\":\"elan0001:00 04f3:3140 touchpad\"}],\"touch\":[{\"name\":\"wacom hid 52b5 finger\"}]}' ;;
monitors) echo '[{\"name\":\"eDP-1\",\"disabled\":false,\"focused\":true},{\"name\":\"DP-2\",\"disabled\":false,\"focused\":false}]' ;;
activewindow) echo '{\"at\":[10,20],\"size\":[300,200]}' ;;
*) $mut ;;
esac"
}

tree() { (cd "$HOME" && find . -mindepth 1 | LC_ALL=C sort); }

# wait_for COND_CMD... — poll up to 5 s.
wait_for() {
    local i
    for ((i = 0; i < 50; i++)); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}
no_flag() { [[ ! -e $FLAG ]]; }
has_flag() { [[ -e $FLAG ]]; }

# --- dry-run plans and purity ------------------------------------------------
trig_sandbox trigger-dry
before="$(tree)"
check_dry() { # LABEL NEEDLE CMD...
    local label=$1 needle=$2
    shift 2
    capture "$@" --dry-run
    assert_status "$label exits 0" 0 "$STATUS"
    assert_contains "$label plan" "$OUTPUT" "$needle"
    assert_dry_pure "$label" "$OUTPUT"
}
check_dry "screenshot region" "DRYRUN: grim -g 1,2 30x40 $HOME/PICTURES/screenshot-" haseen capture screenshot --geometry "1,2 30x40"
check_dry "screenshot output" "grim -o <focused monitor>" haseen capture screenshot output
check_dry "screenshot clipboard only" "DRYRUN: rm " haseen capture screenshot screen --no-save
check_dry "screenrecord" "-w 640x480+10+20 -c mp4" haseen capture screenrecord --geometry "10,20 640x480" --desktop-audio --microphone
assert_contains "screenrecord merges audio" "$OUTPUT" "-a default_output|default_input -ac aac"
assert_contains "screenrecord writes the flag" "$OUTPUT" "touch $FLAG"
assert_contains "screenrecord into Videos" "$OUTPUT" "-o $HOME/VIDEOS/screenrecording-"
check_dry "screenrecord fullscreen" "-w focused" haseen capture screenrecord --fullscreen
check_dry "text" "tesseract stdin stdout -l eng | wl-copy" haseen capture text --geometry "0,0 10x10"
check_dry "qr" "zbarimg -q --raw -Sdisable -Sqrcode.enable - | wl-copy --sensitive" haseen capture qr
check_dry "color" "hyprpicker -z -f hex" haseen capture color
check_dry "reminder set" "--on-active=5m --unit=haseen-reminder-5m-" haseen reminder set 5 tea is ready
assert_contains "reminder message file planned" "$OUTPUT" "tea is ready"
check_dry "reminder clear" "systemctl --user stop 'haseen-reminder-*.timer'" haseen reminder clear
check_dry "toggle gaps" "hyprctl eval <no-gaps.lua>" haseen toggle gaps
check_dry "toggle animations" "no-animations.lua" haseen toggle animations off
check_dry "toggle one-window-ratio" "single_window_aspect_ratio" haseen toggle one-window-ratio on
check_dry "toggle workspace-layout" 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' haseen toggle workspace-layout
check_dry "toggle bar" "DRYRUN: haseen-shell-ipc bar toggle" haseen toggle bar
check_dry "touchpad" 'hl.device({ name = "elan0001:00 04f3:3140 touchpad", enabled = false })' haseen hardware touchpad
check_dry "touchscreen" 'name = "wacom hid 52b5 finger"' haseen hardware touchscreen off
check_dry "laptop display" 'hl.monitor({ output = "eDP-1", disabled = true })' haseen hardware laptop-display off
check_dry "mirror display" 'output = "DP-2", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1"' haseen hardware mirror-display on
check_dry "share file" "DRYRUN: systemd-run --user --quiet --collect localsend --headless send $HASEEN_PATH/VERSION" haseen share file "$HASEEN_PATH/VERSION"
check_dry "share folder" "--headless send $HASEEN_PATH" haseen share folder "$HASEEN_PATH"
check_dry "share clipboard" "DRYRUN: wl-paste > $XDG_RUNTIME_DIR/haseen-share/clipboard-" haseen share clipboard
check_dry "share receive" "DRYRUN: systemd-run --user --quiet --collect localsend" haseen share receive
check_dry "disk test" "write+read 64MB in $SANDBOX/x/disktest-" haseen test disk "$SANDBOX/x" --size 64
# 1x1 PNG as transcode input (outside HOME, so the tree check still holds).
base64 -d >"$SANDBOX/in.png" <<<"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
check_dry "transcode" "-resize 2160x> -quality 85 -strip $SANDBOX/in-medium.jpg" haseen transcode "$SANDBOX/in.png"
assert_eq "dry runs leave HOME untouched" "$before" "$(tree)"
assert_eq "dry runs call nothing" "" "$(<"$CALLS")"

capture haseen capture screenshot --geometry "nonsense"
assert_status "bad geometry is a usage error" 2 "$STATUS"
capture haseen reminder set 0
assert_status "reminder needs minutes >= 1" 2 "$STATUS"
for c in capture-screenshot capture-screenrecord capture-text capture-qr capture-color reminder-set reminder-show \
    reminder-clear toggle-bar toggle-gaps toggle-animations toggle-workspace-layout toggle-one-window-ratio \
    hardware-laptop-display hardware-mirror-display hardware-touchpad hardware-touchscreen hardware-hybrid-gpu \
    share-clipboard share-file share-folder share-receive test-network test-disk transcode; do
    capture "$REPO/bin/haseen-$c" --help
    assert_status "$c --help" 0 "$STATUS"
    assert_contains "$c has a summary" "$(<"$REPO/bin/haseen-$c")" "# haseen:summary "
done

assert_eq "transcode wrote nothing" no "$([[ -e $SANDBOX/in-medium.jpg ]] && echo yes || echo no)"

# --- recording flag lifecycle (stub recorder) --------------------------------
trig_sandbox trigger-record
# Fake gpu-screen-recorder: creates its -o file, finalises on SIGINT.
stub gpu-screen-recorder 'echo "gsr $*" >>"$CALLS"
out=""; prev=""
for a in "$@"; do [ "$prev" = "-o" ] && out=$a; prev=$a; done
trap "echo finalised >>\"\$out\"; exit 0" INT
echo started >"$out"
while :; do sleep 0.1; done'
capture haseen capture screenrecord --geometry "0,0 100x100"
assert_status "record start" 0 "$STATUS"
assert_contains "record start reports the file" "$OUTPUT" "Recording to $HOME/VIDEOS/screenrecording-"
assert_eq "flag exists while recording" yes "$([[ -e $FLAG ]] && echo yes)"
sup="$(cat "$XDG_RUNTIME_DIR/haseen-screenrecord/pid" 2>/dev/null)"
assert_eq "supervisor alive" yes "$(kill -0 "$sup" 2>/dev/null && echo yes)"
assert_contains "recorder got the region" "$(<"$CALLS")" "gsr -w 100x100+0+0"
capture haseen capture screenrecord
assert_status "second call stops" 0 "$STATUS"
assert_contains "stop reported" "$OUTPUT" "Recording stopped"
wait_for no_flag || true
assert_eq "flag removed on stop" no "$([[ -e $FLAG ]] && echo yes || echo no)"
assert_contains "recorder finalised on SIGINT" "$(cat "$HOME"/VIDEOS/screenrecording-*.mp4)" "finalised"
assert_contains "start and stop notified" "$(<"$CALLS")" "notify-send -a haseen Screen recording saved"
capture haseen capture screenrecord --stop
assert_status "--stop with nothing running" 1 "$STATUS"

# Recorder crash: the supervisor's trap still removes the flag.
haseen capture screenrecord --geometry "0,0 100x100" >/dev/null 2>&1
gsr="$(cat "$XDG_RUNTIME_DIR/haseen-screenrecord/gsr.pid" 2>/dev/null)"
kill -9 "$gsr" 2>/dev/null
wait_for no_flag || true
assert_eq "flag removed when the recorder crashes" no "$([[ -e $FLAG ]] && echo yes || echo no)"
assert_contains "crash notified" "$(<"$CALLS")" "Screen recording saved"

# Supervisor SIGKILLed: flag is stale; the next run clears it.
haseen capture screenrecord --geometry "0,0 100x100" >/dev/null 2>&1
sup="$(cat "$XDG_RUNTIME_DIR/haseen-screenrecord/pid" 2>/dev/null)"
gsr="$(cat "$XDG_RUNTIME_DIR/haseen-screenrecord/gsr.pid" 2>/dev/null)"
kill -9 "$sup" 2>/dev/null
kill -9 "$gsr" 2>/dev/null
sleep 0.2
assert_eq "flag left behind by a killed supervisor" yes "$([[ -e $FLAG ]] && echo yes)"
capture haseen capture screenrecord --stop --dry-run
assert_contains "dry run plans the stale cleanup" "$OUTPUT" "DRYRUN: rm -f $FLAG"
assert_eq "dry run keeps the stale flag" yes "$([[ -e $FLAG ]] && echo yes)"
capture haseen capture screenrecord --stop
assert_contains "stale flag cleared" "$OUTPUT" "Cleared a stale recording flag"
assert_status "stale --stop then reports not recording" 1 "$STATUS"
assert_eq "stale flag gone" no "$([[ -e $FLAG ]] && echo yes || echo no)"

# --- reminders ---------------------------------------------------------------
trig_sandbox trigger-reminder
capture haseen reminder set 10 call mum
assert_status "reminder set" 0 "$STATUS"
assert_contains "systemd-run timer" "$(<"$CALLS")" "systemd-run --user --quiet --collect --on-active=10m --unit=haseen-reminder-10m-"
unit="$(grep -o 'haseen-reminder-10m-[0-9]*' "$CALLS" | head -n1)"
assert_eq "message saved" "call mum" "$(cat "$XDG_RUNTIME_DIR/haseen-reminders/$unit.message" 2>/dev/null)"
next=$((($(date +%s) + 600) * 1000000))
stub systemctl "case \"\$*\" in
*list-timers*) echo '[{\"unit\":\"$unit.timer\",\"next\":$next},{\"unit\":\"haseen-reminder-1m-1.timer\",\"next\":1}]' ;;
*stop*) echo \"systemctl \$*\" >>\"\$CALLS\" ;;
esac"
capture haseen reminder show --json
assert_eq "show lists the pending reminder only" "call mum|1" "$(jq -r '"\(.[0].message)|\(length)"' <<<"$OUTPUT")"
capture haseen reminder clear
assert_contains "clear stops timers" "$(<"$CALLS")" "systemctl --user stop haseen-reminder-*.timer"
assert_eq "clear removes messages" "" "$(ls "$XDG_RUNTIME_DIR/haseen-reminders")"

# --- toggles and hardware (real runs against the fake hyprctl) ----------------
trig_sandbox trigger-toggle live
T="$HOME/.local/state/haseen/toggles/hypr"
haseen toggle gaps >/dev/null
assert_contains "gaps on writes the toggle" "$(cat "$T/no-gaps.lua" 2>/dev/null)" "gaps_in = 0"
assert_contains "gaps on applies live" "$(<"$CALLS")" "hyprctl eval -- haseen toggle: no window gaps"
haseen toggle gaps >/dev/null
assert_eq "gaps off removes the toggle" no "$([[ -e $T/no-gaps.lua ]] && echo yes || echo no)"
assert_contains "gaps off reloads" "$(<"$CALLS")" "hyprctl reload"
haseen toggle animations off >/dev/null
assert_eq "animations off persists" yes "$([[ -e $T/no-animations.lua ]] && echo yes)"
haseen toggle animations on >/dev/null
assert_eq "animations on clears" no "$([[ -e $T/no-animations.lua ]] && echo yes || echo no)"
haseen toggle workspace-layout >/dev/null
assert_eq "workspace layout persisted" 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' "$(cat "$T/workspace-layout-3.lua" 2>/dev/null)"
haseen hardware touchpad off >/dev/null
assert_contains "touchpad off persisted" "$(cat "$T/touchpad-disabled.lua" 2>/dev/null)" "enabled = false"
haseen hardware touchpad >/dev/null
assert_contains "touchpad toggles back on" "$(<"$CALLS")" "enabled = true"
haseen hardware laptop-display off >/dev/null
capture haseen hardware mirror-display on
assert_eq "mirror replaces laptop-off" "no yes" "$([[ -e $T/laptop-display-off.lua ]] && echo yes || echo no) $([[ -e $T/mirror-display.lua ]] && echo yes)"
capture haseen hardware laptop-display off
assert_status "laptop off refused while mirroring" 1 "$STATUS"
stub hyprctl 'case "$1" in monitors) echo "[{\"name\":\"eDP-1\",\"disabled\":false}]" ;; *) echo "hyprctl $*" >>"$CALLS" ;; esac'
rm -f "$T/mirror-display.lua"
capture haseen hardware laptop-display off
assert_status "never disables the only display" 1 "$STATUS"
assert_contains "only-display message" "$OUTPUT" "only active display"

# --- QR decode, clipboard, disk test (real tools, sandboxed files) -----------
trig_sandbox trigger-real
if command -v qrencode >/dev/null && command -v zbarimg >/dev/null; then
    qrencode -o "$SANDBOX/qr.png" "otpauth://totp/haseen?secret=ABC"
    capture haseen capture qr --image "$SANDBOX/qr.png"
    assert_status "qr decode" 0 "$STATUS"
    assert_not_contains "qr secret not printed" "$OUTPUT" "secret=ABC"
    assert_contains "qr copied as sensitive" "$(<"$CALLS")" "wl-copy --sensitive: otpauth://totp/haseen?secret=ABC"
    assert_not_contains "qr secret not notified" "$(grep notify-send "$CALLS")" "secret"
fi
HASEEN_DISKTEST_NO_FIO=1 capture haseen test disk "$SANDBOX/disk" --size 16
assert_status "disk test (dd)" 0 "$STATUS"
assert_contains "disk test write rate" "$OUTPUT" "write"
assert_eq "disk test cleans up" "" "$(ls -A "$SANDBOX/disk")"
