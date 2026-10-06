# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Ambient features (plan 019): the state flags and their toggles, the
# screensaver command, the idle decision table, the screensaver drift and
# the night light schedule. The pure JS runs in Qt's own engine (qml), the
# same one Quickshell uses.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
AMBIENT=(haseen.screensaver haseen.nightlight haseen.idle haseen.notifications)
TOGGLES=(dnd idle screensaver nightlight)

# --- manifests and roles ------------------------------------------------------
sandbox ambient-validate
capture haseen plugin validate "${AMBIENT[@]}"
assert_status "ambient plugins validate" 0 "$STATUS"
for id in "${AMBIENT[@]}"; do
    assert_contains "plugin $id ok" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "ambient plugins request no network" "$OUTPUT" "warning:"
assert_eq "screensaver role has one provider" "haseen.screensaver" \
    "$(jq -r 'select((.provides // []) | index("screensaver")) | .id' "$PLUGINS"/*/manifest.json | paste -sd' ')"
assert_eq "screensaver style defaults to ttfx (Omarchy's)" "ttfx" "$(jq -r .settings.style.default "$PLUGINS/haseen.screensaver/manifest.json")"
assert_eq "screensaver debug hooks default off" "false" "$(jq -r .settings.debugIpc.default "$PLUGINS/haseen.screensaver/manifest.json")"
assert_eq "idle screensaverAfter defaults to 150 s" "150" "$(jq -r .settings.screensaverAfter.default "$PLUGINS/haseen.idle/manifest.json")"
assert_eq "nightlight temperature defaults to 4000 K" "4000" "$(jq -r .settings.temperature.default "$PLUGINS/haseen.nightlight/manifest.json")"
for id in haseen.idle haseen.notifications; do
    assert_contains "$id has a bar indicator" "$(jq -r '.kinds | join(" ")' "$PLUGINS/$id/manifest.json")" "bar-widget"
done

# Entry contract and resource rules for the new and edited plugin files.
for id in "${AMBIENT[@]}"; do
    while read -r entry; do
        body="$(cat "$PLUGINS/$id/$entry")"
        for prop in "property string pluginId" "property var settings" "property var screen"; do
            assert_contains "$id/$entry declares $prop" "$body" "$prop"
        done
    done < <(jq -r '.entry[]' "$PLUGINS/$id/manifest.json")
done
dirs=("$SHELL_DIR/Haseen/Flags.qml")
for id in "${AMBIENT[@]}"; do dirs+=("$PLUGINS/$id"); done
assert_eq "no hex colour literals in ambient QML/JS" "" \
    "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "${dirs[@]}" --include='*.qml' --include='*.js' || true)"
assert_eq "flags are read only through qs.Haseen Flags" "" \
    "$(grep -rln 'flags/' "${dirs[@]:1}" --include='*.qml' || true)"
# Windows and the dismiss monitor exist only while shown: every LazyLoader
# is gated on root.active, and there is no window outside them.
ss="$PLUGINS/haseen.screensaver/Service.qml"
assert_eq "screensaver: every LazyLoader is gated on active" \
    "$(grep -c 'LazyLoader {' "$ss")" "$(grep -A2 'LazyLoader {' "$ss" | grep -c 'active: root.active')"
assert_eq "screensaver: one PanelWindow, inside a LazyLoader" "1" \
    "$(awk '/LazyLoader \{/{l=1} l && /PanelWindow \{/{n++} END{print n+0}' "$ss")"
# IdleMonitors are never reconfigured in place (Quickshell 0.3.1 loses
# isIdle after an in-place change): no enabled:/timeout: bound to state.
assert_eq "no IdleMonitor toggled through enabled:" "" \
    "$(grep -rn -A3 'IdleMonitor {' "$PLUGINS/haseen.idle" "$PLUGINS/haseen.screensaver" | grep 'enabled:' || true)"
assert_contains "screensaver tick runs only while shown" \
    "$(grep -A3 'interval: 2000' "$PLUGINS/haseen.screensaver/Service.qml")" "running: root.active"
assert_contains "nightlight schedule check runs only with a schedule" \
    "$(grep -A3 'interval: 60000' "$PLUGINS/haseen.nightlight/Service.qml")" "running: root.hasSchedule"
assert_contains "Flags is a qs.Haseen singleton" "$(cat "$SHELL_DIR/Haseen/qmldir")" "singleton Flags 1.0 Flags.qml"
for name in dnd idle-off screensaver-off nightlight recording; do
    assert_contains "Flags watches $name" "$(cat "$SHELL_DIR/Haseen/Flags.qml")" "name: \"$name\""
done
assert_contains "notifications dnd mirrors the flag" "$(cat "$PLUGINS/haseen.notifications/Service.qml")" "readonly property bool dnd: Flags.dnd"
assert_contains "toggleDnd writes the flag" "$(cat "$PLUGINS/haseen.notifications/Service.qml")" 'Flags.set("dnd", !dnd)'

# --- command headers ------------------------------------------------------------
for f in "${TOGGLES[@]/#/haseen-toggle-}" haseen-screensaver; do
    body="$(cat "$REPO/bin/$f")"
    assert_contains "$f has a summary" "$body" "# haseen:summary "
    assert_contains "$f has args" "$body" "# haseen:args "
    assert_contains "$f takes --dry-run" "$body" "--dry-run"
    capture "$REPO/bin/$f" --help
    assert_status "$f --help" 0 "$STATUS"
    assert_contains "$f --help prints usage" "$OUTPUT" "Usage: haseen "
done

# --- flag toggles ---------------------------------------------------------------
sandbox ambient-toggles
FLAGS_DIR="$XDG_STATE_HOME/haseen/flags"
# toggle NAME FLAG ON_MEANS_FLAG(yes|no)
check_toggle() {
    local name="$1" flag="$2" set_on="$3" on_state off_state
    if [[ $set_on == yes ]]; then on_state=present off_state=absent; else on_state=absent off_state=present; fi
    flag_state() { if [[ -e $FLAGS_DIR/$flag ]]; then echo present; else echo absent; fi; }

    capture haseen toggle "$name" status
    assert_eq "$name: starts on/off by default" "$([[ $set_on == yes ]] && echo off || echo on)" "$OUTPUT"

    capture haseen toggle "$name" on --dry-run
    assert_status "$name on --dry-run" 0 "$STATUS"
    assert_dry_pure "$name on" "$OUTPUT"
    assert_contains "$name on --dry-run shows the change" "$OUTPUT" "DRYRUN:"
    assert_contains "$name on --dry-run names the flag" "$OUTPUT" "flags/$flag"
    assert_eq "$name on --dry-run leaves the flag" "absent" "$(flag_state)"

    capture haseen toggle "$name" on
    assert_status "$name on" 0 "$STATUS"
    assert_eq "$name on: flag $on_state" "$on_state" "$(flag_state)"
    capture haseen toggle "$name" status
    assert_eq "$name status after on" "on" "$OUTPUT"
    capture haseen toggle "$name" on
    assert_eq "$name on is idempotent" "$on_state" "$(flag_state)"

    capture haseen toggle "$name"
    assert_status "$name toggle" 0 "$STATUS"
    assert_eq "$name toggle from on: flag $off_state" "$off_state" "$(flag_state)"
    assert_contains "$name toggle reports off" "$OUTPUT" " off"

    capture haseen toggle "$name" off --dry-run
    assert_dry_pure "$name off" "$OUTPUT"
    capture haseen toggle "$name" on --dry-run
    assert_eq "$name --dry-run from off changes nothing" "$off_state" "$(flag_state)"

    capture haseen toggle "$name"
    assert_eq "$name toggle back: flag $on_state" "$on_state" "$(flag_state)"
    capture haseen toggle "$name" off
    assert_eq "$name off: flag $off_state" "$off_state" "$(flag_state)"

    capture haseen toggle "$name" sideways
    assert_status "$name: unknown action is a usage error" 2 "$STATUS"
    capture haseen toggle "$name" on off
    assert_status "$name: two actions is a usage error" 2 "$STATUS"
}
check_toggle dnd dnd yes
check_toggle nightlight nightlight yes
check_toggle idle idle-off no
stub notify-send 'echo "NOTIFY $*" >>"$HOME/notify.log"'
check_toggle screensaver screensaver-off no
assert_contains "screensaver toggle notifies (no other visual cue)" "$(cat "$HOME/notify.log" 2>/dev/null)" "NOTIFY -a haseen -u low Screensaver off"
# HASEEN_USER_STATE wins over XDG_STATE_HOME, as everywhere else.
HASEEN_USER_STATE="$SANDBOX/alt-state" capture haseen toggle dnd on
assert_eq "toggles honour HASEEN_USER_STATE" "yes" "$([[ -e $SANDBOX/alt-state/flags/dnd ]] && echo yes || echo no)"

# --- haseen screensaver ---------------------------------------------------------
sandbox ambient-screensaver
capture haseen screensaver --dry-run
assert_status "screensaver --dry-run" 0 "$STATUS"
assert_dry_pure "screensaver" "$OUTPUT"
assert_contains "screensaver asks the shell for the configured style" "$OUTPUT" "DRYRUN: haseen shell ipc screensaver start default"
capture haseen screensaver --style ttfx --dry-run
assert_contains "screensaver --style ttfx" "$OUTPUT" "DRYRUN: haseen shell ipc screensaver start ttfx"
capture haseen screensaver --style tte --dry-run
assert_status "screensaver: the old tte name is gone" 2 "$STATUS"
capture haseen screensaver --style=native --dry-run
assert_contains "screensaver --style=native" "$OUTPUT" "DRYRUN: haseen shell ipc screensaver start native"
capture haseen screensaver --style matrix --dry-run
assert_status "screensaver: unknown style is a usage error" 2 "$STATUS"
capture haseen screensaver extra --dry-run
assert_status "screensaver: stray argument is a usage error" 2 "$STATUS"

haseen toggle screensaver off >/dev/null 2>&1 || true
capture haseen screensaver --dry-run
assert_status "screensaver off: not an error" 0 "$STATUS"
assert_contains "screensaver off: says so" "$OUTPUT" "the screensaver is off"
assert_not_contains "screensaver off: no IPC" "$OUTPUT" "ipc screensaver start"
capture haseen screensaver --force --dry-run
assert_contains "screensaver --force overrides the flag" "$OUTPUT" "DRYRUN: haseen shell ipc screensaver start default"
# Without --dry-run the IPC call reaches qs (stubbed here: exit 97).
capture haseen screensaver --force
assert_contains "screensaver calls qs ipc" "$OUTPUT" "STUB-CALLED: qs -p $HASEEN_PATH/shell ipc call screensaver start default"

# --- haseen screensaver style -----------------------------------------------------
capture haseen screensaver style
assert_eq "style: ttfx by default" "ttfx" "$OUTPUT"
mkdir -p "$XDG_CONFIG_HOME/haseen"
echo '{"bar":{"position":"bottom"}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen screensaver style native --dry-run
assert_status "style native --dry-run" 0 "$STATUS"
assert_dry_pure "style native" "$OUTPUT"
assert_contains "style --dry-run shows the new setting" "$OUTPUT" '"style": "native"'
assert_eq "style --dry-run writes nothing" '{"bar":{"position":"bottom"}}' "$(cat "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen screensaver style native
assert_status "style native" 0 "$STATUS"
assert_eq "style native saved" "native" "$(jq -r '.plugins["haseen.screensaver"].settings.style' "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_eq "style keeps the rest of shell.json" "bottom" "$(jq -r .bar.position "$XDG_CONFIG_HOME/haseen/shell.json")"
capture haseen screensaver style
assert_eq "style reads back native" "native" "$OUTPUT"
capture haseen screensaver style ttfx
assert_eq "style back to ttfx" "ttfx" "$(haseen screensaver style)"
capture haseen screensaver style tte
assert_status "style: unknown value is a usage error" 2 "$STATUS"
jq '.plugins["haseen.screensaver"].settings.style = "matrix"' "$XDG_CONFIG_HOME/haseen/shell.json" >"$SANDBOX/s.json"
mv "$SANDBOX/s.json" "$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen screensaver style
assert_eq "style: an invalid saved value reads as the default" "ttfx" "$OUTPUT"

# --- the ttfx screensaver (port of Omarchy's) ------------------------------------
unset TERMINAL
# A fake Hyprland: two monitors (HDMI-A-1 showing the scratchpad), clients
# in $HOME/clients.json; an exec_cmd dispatch maps a fake terminal.
cat >"$HOME/monitors.json" <<'EOF'
[{"name":"DP-1","focused":true,"specialWorkspace":{"id":0,"name":""}},
 {"name":"HDMI-A-1","focused":false,"specialWorkspace":{"id":-98,"name":"special:scratchpad"}}]
EOF
echo '[]' >"$HOME/clients.json"
echo '{"class":"org.haseen.screensaver"}' >"$HOME/active.json"
stub hyprctl '
case "$1" in
monitors) cat "$HOME/monitors.json" ;;
clients) cat "$HOME/clients.json" ;;
activewindow) cat "$HOME/active.json" ;;
dispatch|eval)
    printf "%s\n" "$*" >>"$HOME/hypr.log"
    case "$2" in *exec_cmd*)
        jq --argjson p "$((40000 + $(jq length "$HOME/clients.json")))" ". + [{class: \"org.haseen.screensaver\", pid: \$p}]" "$HOME/clients.json" >"$HOME/c.tmp"
        mv "$HOME/c.tmp" "$HOME/clients.json" ;;
    esac
    echo ok ;;
*) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;;
esac'
capture haseen screensaver --ttfx-launch --dry-run
if [[ -e /usr/bin/ttfx || -e /bin/ttfx ]]; then
    echo "  skip: ttfx is installed system-wide; the missing-ttfx message is not exercised" >&2
else
    assert_status "ttfx-launch without ttfx fails" 1 "$STATUS"
    assert_contains "ttfx-launch names the package" "$OUTPUT" "AUR: ttfx"
fi
stub ttfx 'exit 0'
for t in foot alacritty kitty ghostty xterm; do stub "$t" 'exit 0'; done
self="$REPO/bin/haseen-screensaver"
foot_cmd="foot --app-id=org.haseen.screensaver --fullscreen -o main.pad=0x0 -o main.font=monospace:size=18 -e $self --ttfx-run "
capture haseen screensaver --ttfx-launch --dry-run
assert_status "ttfx-launch --dry-run" 0 "$STATUS"
assert_dry_pure "ttfx-launch" "$OUTPUT"
assert_eq "ttfx-launch: per monitor focus + exec on its special workspace, then focus back" \
    "DRYRUN: hyprctl dispatch hl.dsp.focus({ monitor = \"DP-1\" })
DRYRUN: hyprctl dispatch hl.dsp.exec_cmd([[[workspace special:screensaver-DP-1; idle_inhibit none] $foot_cmd]])
DRYRUN: hyprctl dispatch hl.dsp.focus({ monitor = \"HDMI-A-1\" })
DRYRUN: hyprctl dispatch hl.dsp.exec_cmd([[[workspace special:scratchpad; idle_inhibit none] $foot_cmd]])
DRYRUN: hyprctl dispatch hl.dsp.focus({ monitor = \"DP-1\" })" "$OUTPUT"
TERMINAL=/usr/bin/alacritty capture haseen screensaver --ttfx-launch --dry-run
assert_contains "ttfx-launch: alacritty" "$OUTPUT" "alacritty --class=org.haseen.screensaver -o window.startup_mode=\\\"Fullscreen\\\""
TERMINAL=kitty capture haseen screensaver --ttfx-launch --dry-run
assert_contains "ttfx-launch: kitty" "$OUTPUT" "kitty --class=org.haseen.screensaver --start-as=fullscreen"
TERMINAL=ghostty capture haseen screensaver --ttfx-launch --dry-run
assert_contains "ttfx-launch: ghostty" "$OUTPUT" "ghostty --class=org.haseen.screensaver --fullscreen=true"
stub xdg-terminal-exec 'echo com.mitchellh.ghostty.desktop'
TERMINAL=xdg-terminal-exec capture haseen screensaver --ttfx-launch --dry-run
assert_contains "ttfx-launch: asks xdg-terminal-exec which terminal it runs" "$OUTPUT" "ghostty --class=org.haseen.screensaver"
TERMINAL=xterm capture haseen screensaver --ttfx-launch --dry-run
assert_status "ttfx-launch: unsupported terminal fails" 1 "$STATUS"
assert_contains "ttfx-launch: says which terminals work" "$OUTPUT" "foot, alacritty, kitty or ghostty"
# For real: one terminal per monitor, each waited for before the next.
capture timeout 10 haseen screensaver --ttfx-launch
assert_status "ttfx-launch" 0 "$STATUS"
assert_eq "ttfx-launch mapped one terminal per monitor" "2" "$(jq length "$HOME/clients.json")"
assert_eq "ttfx-launch dispatched two execs" "2" "$(grep -c exec_cmd "$HOME/hypr.log")"
capture timeout 10 haseen screensaver --ttfx-launch
assert_eq "ttfx-launch while showing does nothing" "2" "$(grep -c exec_cmd "$HOME/hypr.log")"
# --stop closes the screensaver terminals by PID, and only those.
sleep 60 &
t1=$!
sleep 60 &
t2=$!
sleep 60 &
other=$!
printf '[{"class":"org.haseen.screensaver","pid":%d},{"class":"foot","pid":%d},{"class":"org.haseen.screensaver","pid":%d}]' "$t1" "$other" "$t2" >"$HOME/clients.json"
capture haseen screensaver --stop --dry-run
assert_dry_pure "stop" "$OUTPUT"
assert_eq "stop --dry-run: kills the screensaver PIDs, restores the cursor" \
    "DRYRUN: kill $t1
DRYRUN: kill $t2
DRYRUN: hyprctl eval hl.config({ cursor = { invisible = false } })" "$OUTPUT"
capture haseen screensaver --stop
assert_status "stop" 0 "$STATUS"
sleep 0.2
assert_eq "stop ended the screensaver terminals" "no no" "$(kill -0 "$t1" 2>/dev/null && echo yes || echo no) $(kill -0 "$t2" 2>/dev/null && echo yes || echo no)"
assert_eq "stop left other windows alone" "yes" "$(kill -0 "$other" 2>/dev/null && echo yes || echo no)"
kill "$other" 2>/dev/null || true
wait "$t1" "$t2" "$other" 2>/dev/null || true
capture haseen screensaver --stop
assert_status "stop with nothing showing is fine" 0 "$STATUS"

# --ttfx-run: Omarchy's flags, the branding file, exit on focus loss.
echo '[]' >"$HOME/clients.json"
: >"$HOME/hypr.log"
stub ttfx 'printf "%s\n" "$@" >>"$HOME/ttfx.args"; exit 3'
capture timeout 5 haseen screensaver --ttfx-run </dev/null
assert_status "ttfx-run: a failing ttfx stops the loop" 1 "$STATUS"
assert_contains "ttfx-run: says why" "$OUTPUT" "ttfx failed"
assert_eq "ttfx-run: ttfx ran once" "1" "$(grep -c '^--random-effect$' "$HOME/ttfx.args")"
assert_eq "ttfx-run: Omarchy's ttfx flags" \
    "-i $HASEEN_PATH/default/screensaver/screensaver.txt --frame-rate 120 --canvas-width 0 --canvas-height 0 --reuse-canvas --anchor-canvas c --anchor-text c --random-effect --no-eol --no-restore-cursor" \
    "$(paste -sd' ' "$HOME/ttfx.args")"
assert_contains "ttfx-run hides the cursor" "$(cat "$HOME/hypr.log")" "eval hl.config({ cursor = { invisible = true } })"
assert_contains "ttfx-run restores the cursor on failure" "$(cat "$HOME/hypr.log")" "eval hl.config({ cursor = { invisible = false } })"
# A ttfx that finishes its effect starts the next one, at most once a second.
rm -f "$HOME/ttfx.args"
stub ttfx 'printf "%s\n" "$@" >>"$HOME/ttfx.args"; exit 0'
capture timeout 3 haseen screensaver --ttfx-run </dev/null
assert_status "ttfx-run loops until stopped" 124 "$STATUS"
n="$(grep -c '^--random-effect$' "$HOME/ttfx.args")"
assert_eq "ttfx-run: next effect after each one, no tight loop (2-4 runs in 3 s)" "yes" "$( ((n >= 2 && n <= 4)) && echo yes || echo no)"
# Focus moving to another window ends it (Omarchy's screensaver_in_focus).
stub ttfx 'exec sleep 30'
echo '{"class":"firefox"}' >"$HOME/active.json"
: >"$HOME/hypr.log"
capture timeout 10 haseen screensaver --ttfx-run </dev/null
assert_status "ttfx-run: focus loss ends it cleanly" 0 "$STATUS"
assert_contains "ttfx-run: focus loss restores the cursor" "$(cat "$HOME/hypr.log")" "invisible = false"
echo '{"class":"org.haseen.screensaver"}' >"$HOME/active.json"
rm -f "$HOME/ttfx.args"
stub ttfx 'printf "%s\n" "$@" >>"$HOME/ttfx.args"; exit 3'
mkdir -p "$XDG_CONFIG_HOME/haseen/branding"
echo "hello" >"$XDG_CONFIG_HOME/haseen/branding/screensaver.txt"
capture timeout 5 haseen screensaver --ttfx-run </dev/null
assert_eq "ttfx-run prefers the user's branding" "$XDG_CONFIG_HOME/haseen/branding/screensaver.txt" "$(sed -n 2p "$HOME/ttfx.args")"
assert_eq "default branding text exists" "yes" "$([[ -s $HASEEN_PATH/default/screensaver/screensaver.txt ]] && echo yes || echo no)"

# --- pure logic in Qt's JS engine -----------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.idle/IdleLogic.js" as Idle
import "file://$PLUGINS/haseen.screensaver/Drift.js" as Drift
import "file://$PLUGINS/haseen.nightlight/NightlightLogic.js" as Night
Item {
    function out(name, v) { console.warn("RESULT " + name + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const t = (s, f, have) => { const r = Idle.timeouts(s, f, have); return [r.screensaver, r.lock, r.dpms].join(","); };
        out("defaults", t({}, {}, true));
        out("no-provider", t({}, {}, false));
        out("idle-off", t({}, { idleOff: true }, true));
        out("idle-off-wins", t({}, { idleOff: true, screensaverOff: false }, true));
        out("screensaver-off", t({}, { screensaverOff: true }, true));
        out("custom", t({ screensaverAfter: 60, lockAfter: 120, dpmsAfter: 0 }, {}, true));
        out("ss-after-lock", t({ screensaverAfter: 400, lockAfter: 300 }, {}, true));
        out("ss-equal-lock", t({ screensaverAfter: 300, lockAfter: 300 }, {}, true));
        out("ss-no-lock", t({ screensaverAfter: 400, lockAfter: 0 }, {}, true));
        out("ss-zero", t({ screensaverAfter: 0 }, {}, true));
        out("garbage", t({ screensaverAfter: "x", lockAfter: -5, dpmsAfter: NaN }, {}, true));
        out("rounding", t({ screensaverAfter: 59.6 }, {}, true));
        out("a-ss-idle", Idle.actions("screensaver", true, {}));
        out("a-ss-active", Idle.actions("screensaver", false, {}));
        out("a-lock-idle", Idle.actions("lock", true, {}));
        out("a-lock-active", Idle.actions("lock", false, {}));
        out("a-dpms-idle", Idle.actions("dpms", true, {}));
        out("a-dpms-active-off", Idle.actions("dpms", false, { dpmsOff: true }));
        out("a-dpms-active-on", Idle.actions("dpms", false, { dpmsOff: false }));
        out("a-unknown", Idle.actions("nope", true, {}));
        out("m-default", Idle.monitors(Idle.timeouts({}, {}, true), true));
        out("m-idle-off", Idle.monitors(Idle.timeouts({}, { idleOff: true }, true), true));
        out("m-no-inhibit", Idle.monitors({ screensaver: 0, lock: 60, dpms: 0 }, false));
        out("m-parse", [Idle.parseMonitor("lock:300:1"), Idle.parseMonitor("dpms:5:0")]);
        out("bounce", [0, 3, 10, 11, 20, 25, 40].map(x => Drift.bounce(x, 10)));
        out("bounce-none", [Drift.bounce(5, 0), Drift.bounce(5, -3)]);
        let inside = true, moved = 0, prev = null;
        for (let k = 0; k < 2000; k++) {
            const p = Drift.position(k, 77, 1920, 1080, 600, 400, 48, 4);
            if (p.x < 48 || p.y < 48 || p.x + 600 > 1920 - 48 || p.y + 400 > 1080 - 48) inside = false;
            if (prev && (p.x !== prev.x || p.y !== prev.y)) moved++;
            if (prev && (Math.abs(p.x - prev.x) > 4 || Math.abs(p.y - prev.y) > 4)) inside = false;
            prev = p;
        }
        out("drift-inside-small-steps", inside);
        out("drift-moves", moved > 1900);
        out("drift-too-big", Drift.position(5, 0, 300, 200, 600, 400, 48, 4));
        out("parse", ["20:00", "7:05", "23:59", "24:00", "7:5", "", null, "aa:bb", " 06:30 "].map(Night.parseTime));
        out("sched-none", [Night.scheduled(600, "", "07:00"), Night.scheduled(600, "20:00", "20:00"), Night.scheduled(600, "x", "07:00")]);
        out("sched-overnight", [0, 419, 420, 1199, 1200, 1439].map(m => Night.scheduled(m, "20:00", "07:00")));
        out("sched-same-day", [59, 60, 359, 360].map(m => Night.scheduled(m, "01:00", "06:00")));
        out("temp", [Night.temperature(3000), Night.temperature(undefined), Night.temperature(500), Night.temperature(30000), Night.temperature("5000"), Night.temperature(4500.4)]);
        Qt.quit();
    }
}
EOF
    js_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$js_out"; }
    # Idle decision table: screensaver,lock,dpms seconds (0 = off).
    assert_eq "idle: defaults 150/300/330" '"150,300,330"' "$(r defaults)"
    assert_eq "idle: no screensaver provider, no screensaver" '"0,300,330"' "$(r no-provider)"
    assert_eq "idle: idle-off disables everything" '"0,0,0"' "$(r idle-off)"
    assert_eq "idle: idle-off wins over the rest" '"0,0,0"' "$(r idle-off-wins)"
    assert_eq "idle: screensaver-off keeps lock and dpms" '"0,300,330"' "$(r screensaver-off)"
    assert_eq "idle: custom timeouts" '"60,120,0"' "$(r custom)"
    assert_eq "idle: screensaver after the lock is dropped" '"0,300,330"' "$(r ss-after-lock)"
    assert_eq "idle: screensaver at the lock is dropped" '"0,300,330"' "$(r ss-equal-lock)"
    assert_eq "idle: without a lock the screensaver stays" '"400,0,330"' "$(r ss-no-lock)"
    assert_eq "idle: screensaverAfter 0 = never" '"0,300,330"' "$(r ss-zero)"
    assert_eq "idle: invalid values fall back" '"150,300,330"' "$(r garbage)"
    assert_eq "idle: seconds round" '"60,300,330"' "$(r rounding)"
    assert_eq "idle: screensaver monitor idle starts it" '["screensaver.start"]' "$(r a-ss-idle)"
    assert_eq "idle: input dismisses the screensaver" '["screensaver.dismiss"]' "$(r a-ss-active)"
    assert_eq "idle: lock drops the screensaver, then locks" '["screensaver.dismiss","lock"]' "$(r a-lock-idle)"
    assert_eq "idle: input after lock does nothing" '[]' "$(r a-lock-active)"
    assert_eq "idle: dpms off" '["dpms.off"]' "$(r a-dpms-idle)"
    assert_eq "idle: input turns displays back on" '["dpms.on"]' "$(r a-dpms-active-off)"
    assert_eq "idle: no dpms on unless we turned them off" '[]' "$(r a-dpms-active-on)"
    assert_eq "idle: unknown monitor does nothing" '[]' "$(r a-unknown)"
    assert_eq "idle: one monitor key per active timeout" '["screensaver:150:1","lock:300:1","dpms:330:1"]' "$(r m-default)"
    assert_eq "idle: idle-off runs no monitor" '[]' "$(r m-idle-off)"
    assert_eq "idle: keys carry respectInhibitors" '["lock:60:0"]' "$(r m-no-inhibit)"
    assert_eq "idle: keys parse back" '[{"name":"lock","timeout":300,"respectInhibitors":true},{"name":"dpms","timeout":5,"respectInhibitors":false}]' "$(r m-parse)"
    # Drift.
    assert_eq "drift: triangle wave" '[0,3,10,9,0,5,0]' "$(r bounce)"
    assert_eq "drift: no room pins the card" '[0,0]' "$(r bounce-none)"
    assert_eq "drift: stays inside the margins, at most 4 px per tick" 'true' "$(r drift-inside-small-steps)"
    assert_eq "drift: moves on (nearly) every tick" 'true' "$(r drift-moves)"
    assert_eq "drift: a card larger than the screen sits at the margin" '{"x":48,"y":48}' "$(r drift-too-big)"
    # Night light schedule.
    assert_eq "night: time parsing" '[1200,425,1439,-1,-1,-1,-1,-1,390]' "$(r parse)"
    assert_eq "night: no schedule without two distinct times" '[null,null,null]' "$(r sched-none)"
    assert_eq "night: 20:00-07:00 across midnight" '[true,true,false,false,true,true]' "$(r sched-overnight)"
    assert_eq "night: 01:00-06:00 within a day" '[false,true,true,false]' "$(r sched-same-day)"
    assert_eq "night: temperature range and default" '[3000,4000,4000,4000,4000,4500]' "$(r temp)"
else
    echo "  skip: $QML_BIN not installed, IdleLogic/Drift/NightlightLogic not exercised" >&2
fi
