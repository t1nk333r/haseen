# shellcheck shell=bash
# haseen:covers bin/haseen-capture-audiorecord bin/haseen-capture-screenrecord bin/haseen-plugin-validate
# haseen:covers share/haseen/VERSION share/haseen/default/shell.json share/haseen/shell/Compat/**
# haseen:covers share/haseen/shell/Haseen/** share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.capture/** share/haseen/shell/plugins/*/manifest.json
# haseen:covers share/haseen/i18n/** tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.capture (plan 150): the toolbar's logic (Model.js) under Qt's own
# engine, the controller listener (gamepad.py) against fake evdev nodes, the
# sound recorder (haseen capture audiorecord) with a fake ffmpeg, and the
# toolbar and its service together in the real Quickshell engine.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.capture"
QML=/usr/lib/qt6/bin/qml
QS_BIN=${QS_BIN:-/usr/bin/qs}

sandbox capture-toolbar
capture haseen plugin validate haseen.capture
assert_status "haseen.capture validates" 0 "$STATUS"
assert_contains "haseen.capture ok" "$OUTPUT" "ok: haseen.capture (builtin:"
assert_eq "a service with a panel" "service panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "it answers the capture role" "capture" "$(jq -r '.provides | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "the controller is off until asked for" "false" "$(jq -r '.settings.controller.default' "$PLUGIN/manifest.json")"
assert_eq "debug hook off by default" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGIN/manifest.json")"
assert_eq "a new built-in plugin ships off" "false" "$(jq -r '.plugins["haseen.capture"].enabled' "$HASEEN_PATH/default/shell.json")"
assert_eq "and is no default service" "0" "$(jq '[.services[] | select(. == "haseen.capture")] | length' "$HASEEN_PATH/default/shell.json")"

# --- Model.js in Qt's engine -----------------------------------------------------
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
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        const s0 = M.initialState({});
        eq("defaults", { mode: "screenshot", targets: { screenshot: "region", video: "region", audio: "" }, delay: 0, desktop: false, mic: false, format: "mp3", edit: false }, s0);
        const bad = M.initialState({ mode: "film", target: "moon", delay: 7, desktopAudio: "yes", audioFormat: "aiff" });
        eq("bad settings fall back", ["screenshot", "region", 0, false, "mp3"], [bad.mode, bad.targets.screenshot, bad.delay, bad.desktop, bad.format]);
        const v0 = M.initialState({ mode: "video", target: "window", delay: 5, microphone: true });
        eq("settings pick the first mode and target", ["video", "window", 5, true], [v0.mode, M.currentTarget(v0), v0.delay, v0.mic]);
        eq("all screens is a screenshot target only", "region", M.target("video", "screen"));

        // Commands.
        eq("screenshot region", ["haseen", "capture", "screenshot", "region"], M.startCommand(s0, false));
        eq("screenshot edit", ["haseen", "capture", "screenshot", "region", "--edit"], M.startCommand(s0, true));
        eq("the editor switch edits every screenshot", ["haseen", "capture", "screenshot", "region", "--edit"], M.startCommand(M.initialState({ edit: true }), false));
        const all = M.withChange(s0, "target", "screen");
        eq("every screen", ["haseen", "capture", "screenshot", "screen"], M.startCommand(all, false));
        let v = M.withChange(M.withChange(s0, "mode", "video"), "desktop", true);
        eq("video region with desktop audio", ["haseen", "capture", "screenrecord", "--desktop-audio"], M.startCommand(v, true));
        v = M.withChange(M.withChange(v, "target", "window"), "mic", true);
        eq("video window, both sources", ["haseen", "capture", "screenrecord", "--window", "--desktop-audio", "--microphone"], M.startCommand(v, false));
        eq("video screen", ["haseen", "capture", "screenrecord", "--fullscreen", "--desktop-audio", "--microphone"], M.startCommand(M.withChange(v, "target", "output"), false));
        eq("a mode keeps its own target", ["region", "window"], [M.currentTarget(M.withChange(v, "mode", "screenshot")), M.currentTarget(M.withChange(M.withChange(v, "mode", "screenshot"), "mode", "video"))]);
        let a = M.withChange(s0, "mode", "audio");
        eq("audio needs a source", false, M.canCapture(a));
        a = M.withChange(M.withChange(a, "mic", true), "format", "flac");
        eq("audio command", ["haseen", "capture", "audiorecord", "--format", "flac", "--microphone"], M.startCommand(a, false));
        eq("an unknown format is mp3", "mp3", M.withChange(a, "format", "aiff").format);
        eq("stop commands", [["haseen", "capture", "screenrecord", "--stop"], ["haseen", "capture", "audiorecord", "--stop"]], [M.stopCommand("video"), M.stopCommand("audio")]);
        eq("video wins when both flags are up", ["video", "audio", ""], [M.recordingKind(true, true), M.recordingKind(false, true), M.recordingKind(false, false)]);

        // The delay: never under the toolbar's own close, never for sound.
        eq("no delay still waits for the toolbar", 300, M.waitMs(s0, 300));
        eq("five seconds", 5000, M.waitMs(M.withChange(s0, "delay", 5), 300));
        eq("sound never waits", 300, M.waitMs(M.withChange(M.withChange(s0, "delay", 10), "mode", "audio"), 300));

        // The clock.
        eq("since", [1700000000, 0, 0], [M.sinceSeconds("1700000000\n"), M.sinceSeconds(""), M.sinceSeconds("soon")]);
        eq("elapsed", ["0:00", "1:15", "1:02:05", "0:00"], [M.elapsedText(0), M.elapsedText(75.9), M.elapsedText(3725), M.elapsedText(-4)]);

        // Rows and the cursor: the bar, and the options card above it.
        const bar = ["mode:screenshot", "mode:video", "mode:audio", "target:region", "target:window", "target:output", "target:screen", "capture", "options", "close"];
        const r0 = M.rows(s0, false);
        const ro = M.rows(s0, false, true);
        eq("the bar is one row", [bar], r0);
        eq("screenshot options: the delay, then the editor", [["delay:0", "delay:3", "delay:5", "delay:10"], ["edit"], bar], ro);
        eq("video options: the sound, then the delay", [["desktop", "mic"], ["delay:0", "delay:3", "delay:5", "delay:10"]], M.rows(M.withChange(s0, "mode", "video"), false, true).slice(0, 2));
        eq("sound: its sources on the bar, its formats in the options", [["format:mp3", "format:opus", "format:flac", "format:wav", "format:m4a", "format:ogg"], ["mode:screenshot", "mode:video", "mode:audio", "desktop", "mic", "capture", "options", "close"]], M.rows(a, false, true));
        eq("a recording is stop and close", [["stop", "close"]], M.rows(s0, true, true));
        eq("home is the capture button, or stop", ["capture", "capture", "stop"], [M.home(r0), M.home(ro), M.home(M.rows(s0, true))]);
        eq("up from the bar into the card takes the row's last", ["edit", "delay:0"], [M.move(ro, "capture", "up"), M.move(ro, "edit", "up")]);
        eq("down keeps the column where it can", ["edit", "mode:screenshot"], [M.move(ro, "delay:10", "down"), M.move(ro, "edit", "down")]);
        eq("left and right stop at the ends", ["mode:screenshot", "close"], [M.move(r0, "mode:screenshot", "left"), M.move(r0, "close", "right")]);
        eq("with the card closed up stays on the bar", "capture", M.move(r0, "capture", "up"));
        eq("Tab walks the card and the bar and wraps", ["delay:0", "close"], [M.move(ro, "close", "next"), M.move(ro, "delay:0", "previous")]);
        eq("a control gone starts at home", "capture", M.move(r0, "edit", "down"));

        // Activation.
        eq("activate", [{ key: "mode", value: "video" }, { key: "delay", value: 3 }, { key: "mic", value: true }, { key: "desktop", value: false }, { key: "edit", value: true }, { action: "options" }, { action: "close" }, null],
            [M.activate(s0, "mode:video"), M.activate(s0, "delay:3"), M.activate(s0, "mic"), M.activate(M.withChange(s0, "desktop", true), "desktop"), M.activate(s0, "edit"), M.activate(s0, "options"), M.activate(s0, "close"), M.activate(s0, "nonsense")]);
        eq("the editor switch is kept", true, M.withChange(s0, "edit", true).edit);

        // The names the hint shows for the icon buttons; chips carry their own.
        eq("labels", ["Video", "All screens", "Microphone", "Capture", "Record", "Options", "Close", "Stop", ""],
            [M.label(s0, "mode:video"), M.label(s0, "target:screen"), M.label(s0, "mic"), M.label(s0, "capture"), M.label(a, "capture"), M.label(s0, "options"), M.label(s0, "close"), M.label(s0, "stop"), M.label(s0, "delay:3")]);

        // The controller.
        eq("pad moves, presses and closes", [{ move: "up" }, { press: true }, { close: true }], [M.padAction(s0, "up", false), M.padAction(s0, "a", false), M.padAction(s0, "b", false)]);
        eq("Y opens the options, not while recording", [{ action: "options" }, null], [M.padAction(s0, "y", false), M.padAction(s0, "y", true)]);
        eq("pad triggers change the mode, wrapping", [{ change: { key: "mode", value: "video" } }, { change: { key: "mode", value: "audio" } }], [M.padAction(s0, "rt", false), M.padAction(s0, "lt", false)]);
        eq("pad bumpers change the target", [{ change: { key: "target", value: "window" } }, { change: { key: "target", value: "screen" } }], [M.padAction(s0, "rb", false), M.padAction(s0, "lb", false)]);
        eq("sound has no target to change", null, M.padAction(a, "rb", false));
        eq("start captures, or stops a recording", [{ action: "capture" }, { action: "stop" }], [M.padAction(s0, "start", false), M.padAction(s0, "start", true)]);
        eq("guide only stops", [null, { action: "stop" }], [M.padAction(s0, "guide", false), M.padAction(s0, "guide", true)]);
        eq("a recording keeps the mode", null, M.padAction(s0, "rt", true));
        eq("listener lines", [{ kind: "press", value: "a" }, { kind: "connected", value: 2 }, { kind: "error", value: "cannot read event3: Permission denied" }, null, null],
            [M.padLine("press a\n"), M.padLine("connected 2"), M.padLine("error cannot read event3: Permission denied"), M.padLine("connected two"), M.padLine("hello")]);
        eq("toList", [[], [1, 2]], [M.toList(null), M.toList([1, 2])]);
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
    assert_eq "js unit count" "47" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- gamepad.py against fake evdev nodes ----------------------------------------
# A FIFO stands in for /dev/input/eventN, a directory for its sysfs node. It
# is opened read-write here, so the listener never sees end of file.
pads="$SANDBOX/pads"
sys_dir="$pads/sys" dev_dir="$pads/dev"
mkdir -p "$dev_dir"
# caps NAME KEYS ABS: sysfs capability bitmaps (hex words, highest first).
caps() {
    mkdir -p "$sys_dir/$1/device/capabilities"
    python3 -I - "$sys_dir/$1/device/capabilities" "$2" "$3" <<'PY'
import sys
out, keys, axes = sys.argv[1], sys.argv[2], sys.argv[3]
def words(codes):
    value = 0
    for c in codes.split():
        value |= 1 << int(c, 0)
    parts = []
    while True:
        parts.append("%x" % (value & (2**64 - 1)))
        value >>= 64
        if not value:
            break
    return " ".join(reversed(parts))
open(out + "/key", "w").write(words(keys) + "\n")
open(out + "/abs", "w").write(words(axes) + "\n")
PY
}
# events FD TYPE CODE VALUE...: write struct input_event records.
events() {
    local fd=$1
    shift
    python3 -I -c '
import struct, sys
args = [int(a, 0) for a in sys.argv[1:]]
data = b"".join(struct.pack("llHHi", 0, 0, *args[i:i + 3]) for i in range(0, len(args), 3))
sys.stdout.buffer.write(data)' "$@" >&"$fd"
}
pad_out="$SANDBOX/pad.out"
pad_wait() { # NEEDLE: wait up to 5 s for a line in the listener's output
    local i
    for ((i = 0; i < 50; i++)); do
        grep -qxF -- "$1" "$pad_out" 2>/dev/null && return 0
        sleep 0.1
    done
    return 1
}
# An Xbox-style pad: face buttons, bumpers, Start/Select/Guide; sticks and
# analog triggers, the right stick on ABS_RX. A keyboard beside it.
caps event3 "0x130 0x131 0x133 0x134 0x136 0x137 0x13a 0x13b 0x13c" "0 1 2 3 4 5 0x10 0x11"
caps event4 "30 31 32" ""
mkfifo "$dev_dir/event3" "$dev_dir/event4"
exec {pad3}<>"$dev_dir/event3" {kbd4}<>"$dev_dir/event4"
python3 -I "$PLUGIN/gamepad.py" --sysfs "$sys_dir" --dev "$dev_dir" >"$pad_out" 2>&1 &
pad_pid=$!
pad_wait "connected 1" || true
assert_eq "the pad is found, the keyboard is not" "connected 1" "$(head -n1 "$pad_out")"
# A, release; D-pad left, centre, right; stick right twice (one press), back,
# left; the left trigger; Guide. A keyboard key on the other node.
events "$kbd4" 1 30 1
events "$pad3" 1 0x130 1 1 0x130 0 3 0x10 -1 3 0x10 0 3 0x10 1 3 0 30000 3 0 26000 3 0 0 3 0 -30000 3 2 250 3 2 10 1 0x13c 1
pad_wait "press guide" || true
assert_eq "presses in order, each once" "press a|press left|press right|press right|press left|press lt|press guide" \
    "$(grep '^press' "$pad_out" | paste -sd'|')"
# A second pad comes and goes: one inotify event each.
caps event5 "0x130 0x138 0x139" "0 1 2 5"
mkfifo "$dev_dir/event5"
exec {pad5}<>"$dev_dir/event5"
pad_wait "connected 2" || true
assert_eq "a pad plugged in is counted" "yes" "$(grep -qx 'connected 2' "$pad_out" && echo yes)"
# Its digital triggers win: the analog ABS_Z pull is not a second lt.
events "$pad5" 3 2 255 1 0x138 1
pad_wait "press lt" || true
sleep 0.3
assert_eq "a digital trigger, once (one lt from each pad)" "2" "$(grep -c '^press lt$' "$pad_out")"
rm -rf "$sys_dir/event5"
exec {pad5}>&-
rm -f "$dev_dir/event5"
for ((i = 0; i < 50; i++)); do
    [[ $(tail -n1 "$pad_out") == "connected 1" ]] && break
    sleep 0.1
done
assert_eq "and unplugged, it is gone" "connected 1" "$(grep '^connected' "$pad_out" | tail -n1)"
if ((EUID != 0)); then
    caps event6 "0x130" "0 1"
    mkfifo -m 000 "$dev_dir/event6"
    pad_wait "error cannot read event6: Permission denied" || true
    assert_eq "a pad it may not read is reported once" "1" "$(grep -c '^error cannot read event6' "$pad_out")"
fi
kill "$pad_pid" 2>/dev/null || true
wait "$pad_pid" 2>/dev/null || true
exec {pad3}>&- {kbd4}>&-
assert_eq "the listener grabs nothing (no EVIOCGRAB)" "0" "$(grep -c 'EVIOCGRAB\|0x40044590' "$PLUGIN/gamepad.py")"

# --- haseen capture audiorecord ---------------------------------------------------
sandbox capture-audiorecord
export XDG_RUNTIME_DIR="$SANDBOX/run" HASEEN_INLINE=1
mkdir -p "$XDG_RUNTIME_DIR"
CALLS="$SANDBOX/calls"
: >"$CALLS"
export CALLS
FLAG="$HOME/.local/state/haseen/flags/audio-recording"
stub notify-send 'echo "notify-send $*" >>"$CALLS"'
stub xdg-user-dir 'echo "$HOME/$1"'
stub ffmpeg 'echo "STUB-CALLED: ffmpeg $*" >&2; exit 97'
no_flag() { [[ ! -e $FLAG ]]; }
wait_for() {
    local i
    for ((i = 0; i < 50; i++)); do
        "$@" && return 0
        sleep 0.1
    done
    return 1
}

capture haseen capture audiorecord --dry-run
assert_status "sound dry run exits 0" 0 "$STATUS"
assert_contains "the microphone by default, as mp3" "$OUTPUT" \
    "DRYRUN: ffmpeg -hide_banner -loglevel error -nostdin -f pulse -i @DEFAULT_SOURCE@ -c:a libmp3lame -q:a 2 -y $HOME/MUSIC/audiorecording-"
assert_contains "the flag holds the start" "$OUTPUT" "DRYRUN: date +%s >$FLAG"
assert_dry_pure "sound dry run" "$OUTPUT"
capture haseen capture audiorecord --desktop-audio --microphone --format flac --dry-run
assert_contains "both sources mixed into one track" "$OUTPUT" \
    "-f pulse -i @DEFAULT_MONITOR@ -f pulse -i @DEFAULT_SOURCE@ -filter_complex [0:a][1:a]amix=inputs=2:duration=longest[a] -map [a] -c:a flac -y"
assert_contains "a flac file" "$OUTPUT" ".flac"
capture haseen capture audiorecord --desktop-audio --dry-run
assert_not_contains "the desktop alone has no microphone" "$OUTPUT" "@DEFAULT_SOURCE@"
for pair in "opus:-c:a libopus -b:a 128k" "wav:-c:a pcm_s16le" "m4a:-c:a aac -b:a 192k" "ogg:-c:a libvorbis -q:a 5"; do
    capture haseen capture audiorecord --format="${pair%%:*}" --dry-run
    assert_contains "format ${pair%%:*}" "$OUTPUT" "${pair#*:} -y $HOME/MUSIC/audiorecording-"
done
capture haseen capture audiorecord --format aiff
assert_status "an unknown format is refused" 2 "$STATUS"
assert_contains "and named" "$OUTPUT" "--format wants mp3, opus, flac, wav, m4a or ogg, got: aiff"
assert_eq "dry runs wrote nothing" "" "$(find "$HOME" -mindepth 1 -not -path "$HOME/.local" -not -path "$HOME/.local/state" -not -path "$HOME/.local/state/haseen*" -print -quit 2>/dev/null)"

# A fake ffmpeg: writes its output file (the last argument), finalises on SIGINT.
stub ffmpeg 'echo "ffmpeg $*" >>"$CALLS"
out=""
for a in "$@"; do out=$a; done
trap "echo finalised >>\"\$out\"; exit 0" INT
echo started >"$out"
while :; do sleep 0.1; done'
capture haseen capture audiorecord --format ogg
assert_status "sound start" 0 "$STATUS"
assert_contains "it reports the file" "$OUTPUT" "Recording to $HOME/MUSIC/audiorecording-"
assert_eq "the flag holds the start in epoch seconds" yes "$([[ -e $FLAG && $(head -n1 "$FLAG") =~ ^[0-9]+$ ]] && echo yes)"
sup="$(cat "$XDG_RUNTIME_DIR/haseen-audiorecord/pid" 2>/dev/null)"
assert_eq "the supervisor runs" yes "$(kill -0 "$sup" 2>/dev/null && echo yes)"
assert_contains "ffmpeg got the microphone" "$(<"$CALLS")" "ffmpeg -hide_banner -loglevel error -nostdin -f pulse -i @DEFAULT_SOURCE@ -c:a libvorbis"
capture haseen capture audiorecord
assert_status "the second call stops" 0 "$STATUS"
assert_contains "stop reported" "$OUTPUT" "Recording stopped"
wait_for no_flag || true
assert_eq "the flag goes on stop" no "$([[ -e $FLAG ]] && echo yes || echo no)"
assert_contains "ffmpeg finalised on SIGINT" "$(cat "$HOME"/MUSIC/audiorecording-*.ogg)" "finalised"
assert_contains "start and save notified" "$(<"$CALLS")" "notify-send -a haseen Sound recording saved"
capture haseen capture audiorecord --stop
assert_status "--stop with nothing running" 1 "$STATUS"
# A killed supervisor leaves the flag; the next run clears it.
haseen capture audiorecord >/dev/null 2>&1
sup="$(cat "$XDG_RUNTIME_DIR/haseen-audiorecord/pid" 2>/dev/null)"
rec="$(cat "$XDG_RUNTIME_DIR/haseen-audiorecord/ffmpeg.pid" 2>/dev/null)"
kill -9 "$sup" "$rec" 2>/dev/null
sleep 0.2
assert_eq "the flag outlives a killed supervisor" yes "$([[ -e $FLAG ]] && echo yes)"
capture haseen capture audiorecord --stop
assert_contains "the stale flag is cleared" "$OUTPUT" "Cleared a stale recording flag"
assert_eq "and gone" no "$([[ -e $FLAG ]] && echo yes || echo no)"

# --- the toolbar and its service in the real engine --------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: Quickshell not installed; capture engine scenarios not run" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "capture: required engine prerequisite" available unavailable
    return 0
fi
sandbox capture-engine
export XDG_RUNTIME_DIR="$SANDBOX/run"
mkdir -p "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME/haseen"
FLAGS="$HOME/.local/state/haseen/flags"
mkdir -p "$FLAGS"
# The recording the probe starts at step 3: a flag with an hour-old start
# and no recorder, which screenrecord --stop clears as stale.
started=$(($(date +%s) - 3600))
printf '#!/bin/sh\necho %s >"%s"\n' "$started" "$FLAGS/recording" >"$SANDBOX/mkflag"
chmod +x "$SANDBOX/mkflag"
jq -n '{plugins: {"haseen.capture": {enabled: true, settings: {delay: 3, pill: false}}}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
harness="$SANDBOX/shell"
mkdir -p "$harness"
for module in Haseen Compat Ui Commons; do
    ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
done
ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
cat >"$harness/shell.qml" <<EOF
import QtQuick
import Quickshell
import qs.Haseen

ShellRoot {
    id: probe

    property var svc: null
    property var panel: null
    property int step: 0
    property int ticks: 0
    property var seen: ({})

    function make(file: string, props: var): var {
        const c = Qt.createComponent("file://$PLUGIN/" + file);
        const o = c.createObject(win.contentItem, props);
        if (!o)
            console.log("RESULT " + JSON.stringify({ error: file + ": " + c.errorString() }));
        return o;
    }

    function find(item: var, name: string): var {
        if (item.objectName === name)
            return item;
        for (let i = 0; i < item.children.length; i++) {
            const hit = probe.find(item.children[i], name);
            if (hit)
                return hit;
        }
        return null;
    }

    function shown(name: string): bool {
        const item = probe.find(probe.panel, name);
        let v = item !== null;
        for (let it = item; v && it && it !== probe.panel; it = it.parent)
            v = it.visible;
        return v;
    }

    FloatingWindow {
        id: win

        visible: true
        implicitWidth: 700
        implicitHeight: 400
    }

    // haseen:ui-timeout
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (++probe.ticks > 150) {
                console.log("RESULT " + JSON.stringify({ error: "timeout at step " + probe.step, seen: probe.seen }));
                Qt.quit();
                return;
            }
            if (!probe.svc) {
                if (!Plugins.registry["haseen.capture"])
                    return;
                probe.svc = probe.make("Service.qml", { pluginId: "haseen.capture", settings: Qt.binding(() => Plugins.settingsFor("haseen.capture")) });
                Plugins.registerRole("capture", "haseen.capture", probe.svc);
                return;
            }
            const s = probe.svc;
            if (probe.step === 0) {
                // Off the window's corner: the offscreen platform's pointer rests
                // there, and a hovered control takes the cursor.
                probe.panel = probe.make("Panel.qml", { pluginId: "haseen.capture", x: 80, y: 80, settings: Qt.binding(() => Plugins.settingsFor("haseen.capture")) });
                probe.step = 1;
            } else if (probe.step === 1) {
                probe.seen.open = { panelOpen: s.panelOpen, cursor: probe.panel.cursor, delay: s.state.delay, edit: probe.shown("captureEdit"), mic: probe.shown("captureMic"), go: probe.shown("captureGo") };
                // Y opens the options card above the bar; up from Capture
                // reaches its editor switch, up again its delays, right twice
                // and Enter pick 5 s.
                s.padLine("press y");
                probe.panel.moveCursor("up");
                probe.panel.moveCursor("up");
                probe.panel.moveCursor("right");
                probe.panel.moveCursor("right");
                probe.panel.press(probe.panel.cursor);
                // The controller: RT to Video, RB to its Window.
                s.padLine("press rt");
                s.padLine("press rb");
                probe.step = 2;
            } else if (probe.step === 2) {
                probe.seen.driven = { cursor: probe.panel.cursor, delay: s.state.delay, mode: s.state.mode, target: s.state.targets.video, shotTarget: s.state.targets.screenshot,
                    card: probe.panel.cardShown, mic: probe.shown("captureOption-mic"), edit: probe.shown("captureEdit") };
                probe.panel.press("mic");
                // B closes the card first; the toolbar stays.
                s.padLine("press b");
                probe.seen.back = { card: probe.panel.cardShown, cursor: probe.panel.cursor };
                probe.panel.capture(false);
                probe.step = 3;
            } else if (probe.step === 3) {
                probe.seen.pending = { pending: s.pending, command: s.pendingCommand };
                s.cancel();
                // Sound with no source cannot record.
                s.change("mode", "audio");
                s.change("mic", false);
                probe.seen.silent = { capture: s.capture(false), pending: s.pending };
                // A recording the CLI started: the flag carries its start.
                Quickshell.execDetached(["$SANDBOX/mkflag"]);
                probe.step = 4;
            } else if (probe.step === 4 && s.recording) {
                probe.seen.recording = { kind: s.recordingKind, since: s.recordingSince, elapsedOk: /^1:00:0[0-9]/.test(s.elapsed),
                    rows: probe.panel.rows, stop: probe.shown("captureStop"), ticking: s.ticking };
                // Closed toolbar: only Guide stops, through the real CLI.
                probe.panel.destroy();
                probe.step = 5;
            } else if (probe.step === 5) {
                probe.seen.closed = { panelOpen: s.panelOpen, ticking: s.ticking };
                s.padLine("press a");
                s.padLine("press guide");
                probe.step = 6;
            } else if (probe.step === 6 && !s.recording) {
                probe.seen.stopped = true;
                console.log("RESULT " + JSON.stringify(probe.seen));
                Qt.quit();
            }
        }
    }
}
EOF
capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
    timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
[[ -n $result ]] || _fail "capture engine produced no result" "$OUTPUT"
r() { jq -r "$1" <<<"${result:-"{}"}"; }
assert_eq "engine: no error" "null" "$(r .error)"
assert_eq "engine: the open toolbar tells the service, cursor on Capture, the options closed" "true|capture|3|false|false|true" \
    "$(r '[.open.panelOpen, .open.cursor, .open.delay, .open.edit, .open.mic, .open.go] | map(tostring) | join("|")')"
assert_eq "engine: Y, arrows and Enter pick 5 s in the card; RT and RB switch to a video of the window, screenshots keep theirs" "delay:5|5|video|window|region|true|true|false" \
    "$(r '[.driven.cursor, .driven.delay, .driven.mode, .driven.target, .driven.shotTarget, .driven.card, .driven.mic, .driven.edit] | map(tostring) | join("|")')"
assert_eq "engine: B closes the card first, the cursor back on Capture" "false|capture" "$(r '[.back.card, .back.cursor] | map(tostring) | join("|")')"
assert_eq "engine: a capture waits out its delay with the command ready" 'true|["haseen","capture","screenrecord","--window","--microphone"]' \
    "$(r '[.pending.pending, (.pending.command | tojson)] | map(tostring) | join("|")')"
assert_eq "engine: sound without a source does not start" "false|false" "$(r '[.silent.capture, .silent.pending] | map(tostring) | join("|")')"
assert_eq "engine: a running recording, its start from the flag" "video|$started|true|true|true" \
    "$(r '[.recording.kind, .recording.since, .recording.elapsedOk, .recording.stop, .recording.ticking] | map(tostring) | join("|")')"
assert_eq "engine: the bar is stop and close" '[["stop","close"]]' "$(r '.recording.rows | tojson')"
assert_eq "engine: closed, the service knows and the clock stops (no pill)" "false|false" "$(r '[.closed.panelOpen, .closed.ticking] | map(tostring) | join("|")')"
assert_eq "engine: the Guide button stops it" "true" "$(r .stopped)"
# Offscreen has no layer-shell backend, so the pill's window type is missing
# there (as the OSD's is); every other warning naming the plugin fails.
assert_eq "engine: no QML warnings" "" "$(grep 'haseen.capture/' <<<"$OUTPUT" | grep -v 'PillWindow.qml:[0-9]*:[0-9]*: No PanelWindow backend loaded' || true)"
