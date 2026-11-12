# shellcheck shell=bash
# haseen:covers share/haseen/shell/plugins/haseen.stage/**
# haseen:covers share/haseen/migrations/1794512737-stage-service.sh share/haseen/default/shell.json
# haseen:covers share/haseen/shell/Haseen/{Flags,Plugins,Theme,Config,Paths}.qml
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.stage, the Stage Manager (plan 163): the manifest and the default
# shell.json (the service on), the migration that lists it in a user's own
# `services`, the hot strip's contract with the bar, the pure logic in
# Stage.js under Qt's own JS engine (which workspaces, their order, the
# windows of a stack, the cards' offsets, the turn by edge, the sizes and the
# rules that keep the edge quiet), the service in the real Quickshell engine
# (no compositor: nothing to show, the game context keeps the edge quiet),
# and the stage drawn headless on the software renderer at scales 1 and
# 1.25: hidden until shown, inside its column, and turned towards the middle
# (the near side taller than the far side) on either edge, flat at tilt 0.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.stage"
DEFAULT="$HASEEN_PATH/default/shell.json"
MIGRATION=1794512737-stage-service.sh
QML=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

engine_skip() {
    echo "  skip: $1" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]] && assert_eq "$1: required engine prerequisite" available unavailable
    return 0
}

# --- manifest and defaults ---------------------------------------------------
sandbox stage
capture haseen plugin validate haseen.stage
assert_status "stage validates" 0 "$STATUS"
assert_contains "stage ok" "$OUTPUT" "ok: haseen.stage (builtin:"
assert_eq "a service, and only that" "service" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "defaults: left edge, 200 ms dwell, 3 windows, 50 degrees" "left 200 3 50" \
    "$(jq -r '[.settings.edge.default, .settings.dwell.default, .settings.maxWindows.default, .settings.tilt.default] | map(tostring) | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "no permissions: nothing runs, nothing is read" "[]" "$(jq -c .permissions "$PLUGIN/manifest.json")"
assert_eq "default shell.json starts the service (owner, 2026-11-12)" "true" "$(jq '.services | index("haseen.stage") != null' "$DEFAULT")"
assert_eq "default shell.json does not turn it off" "null" "$(jq '.plugins["haseen.stage"].enabled' "$DEFAULT")"
assert_eq "no key is bound by default (none was approved)" "" "$(grep -rn 'stage' "$HASEEN_PATH/default/hypr/" || true)"

# --- what exists at rest, and the strip's contract with the bar ------------------
service="$(cat "$PLUGIN/Service.qml")"
strip="$(cat "$PLUGIN/EdgeStrip.qml")"
assert_not_contains "the service declares no window of its own" "$service" "PanelWindow {"
assert_contains "the strips load by URL" "$service" 'source: Qt.resolvedUrl("EdgeStrip.qml")'
assert_contains "the stage loads by URL, only while open" "$service" 'active: root.stageScreen !== null'
assert_contains "the stage's window is its own file" "$service" 'source: Qt.resolvedUrl("StageWindow.qml")'
# Normal exclusion with no zone of its own: the compositor keeps the strip
# off the bar on whichever edge the bar is, so it never takes the bar's
# input; it reserves nothing either.
assert_contains "the strip moves aside for the bar" "$strip" "exclusionMode: ExclusionMode.Normal"
assert_not_contains "the strip reserves no zone" "$strip" "exclusiveZone"
assert_contains "the strip sits under a fullscreen window" "$strip" "WlrLayer.Top"
assert_contains "the strip never takes the keyboard" "$strip" "WlrKeyboardFocus.None"
assert_contains "a quiet strip lets every click through" "$strip" "width: strip.armed ? strip.width : 0"
assert_contains "a press at the edge stops the dwell" "$strip" "onPressed: dwell.stop()"
assert_contains "the strip draws nothing" "$strip" 'color: "transparent"'
assert_contains "the stage's window reserves nothing either" "$(cat "$PLUGIN/StageWindow.qml")" "exclusionMode: ExclusionMode.Normal"
assert_contains "the pictures are taken once, not streamed" "$(cat "$PLUGIN/StageCard.qml")" "live: false"
assert_eq "no blur or shader (architecture 6)" "" "$(grep -nE 'MultiEffect|ShaderEffect\b|FastBlur|layer\.effect' "$PLUGIN"/*.qml || true)"

# --- migration ------------------------------------------------------------------
run_migration() {
    capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIGRATION" \
        bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIGRATION"
}
sandbox stage-migration
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"services":["haseen.pager","me.svc"],"plugins":{"me.svc":{"enabled":true}}}\n' >"$CFG"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_eq "migration: appended to a user's own services" '["haseen.pager","me.svc","haseen.stage"]' "$(jq -c .services "$CFG")"
assert_eq "migration: the rest of shell.json survives" "true" "$(jq '.plugins["me.svc"].enabled' "$CFG")"
after="$(cat "$CFG")"
run_migration
assert_eq "migration: a re-run is a no-op" "$after" "$(cat "$CFG")"
printf '{"services":["haseen.stage"],"plugins":{"haseen.stage":{"enabled":false}}}\n' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "migration: a user's own off stays off" "$before" "$(cat "$CFG")"
printf '{"bar":{"left":[]}}\n' >"$CFG"
before="$(cat "$CFG")"
run_migration
assert_eq "migration: no own services list, nothing written" "$before" "$(cat "$CFG")"
rm -f "$CFG"
run_migration
assert_status "migration without a shell.json exits 0" 0 "$STATUS"
assert_eq "migration: no shell.json, none written" no "$([[ -e $CFG ]] && echo yes || echo no)"

# --- pure logic under the real Qt JS engine ---------------------------------------
sandbox stage-js
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Stage.js" as S

QtObject {
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

    function c(address, workspace, focus, extra) {
        return Object.assign({ address: address, workspace: workspace, focus: focus, width: 1600, height: 900 }, extra || {});
    }

    function run() {
        // settings
        eq("config defaults", { edge: "left", dwell: 200, maxWindows: 3, tilt: 50 }, S.config({}));
        eq("config: no settings at all", S.config({}), S.config(null));
        eq("config: right edge, clamped numbers", { edge: "right", dwell: 1000, maxWindows: 4, tilt: 60 },
           S.config({ edge: "right", dwell: 5000, maxWindows: 9, tilt: 90 }));
        eq("config: top is not an edge the stage uses", "left", S.config({ edge: "top" }).edge);
        eq("config: junk falls back", [200, 3, 50], [S.config({ dwell: "x" }).dwell, S.config({ maxWindows: true }).maxWindows, S.config({ tilt: "" }).tilt]);
        eq("config: low clamps", [100, 1, 0], [S.config({ dwell: 10 }).dwell, S.config({ maxWindows: 0 }).maxWindows, S.config({ tilt: -5 }).tilt]);

        // the quiet rules, in order
        eq("nothing in the way", "", S.suppressed({ locked: false, context: "", fullscreen: false, buttons: 0, count: 2 }));
        eq("locked beats everything", "locked", S.suppressed({ locked: true, context: "game", fullscreen: true, buttons: 1, count: 0 }));
        eq("the game context", "game", S.suppressed({ context: "game", fullscreen: true }));
        eq("another context does not", "", S.suppressed({ context: "present" }));
        eq("a fullscreen window", "fullscreen", S.suppressed({ fullscreen: true, buttons: 1 }));
        eq("a held button: a drag to the edge", "dragging", S.suppressed({ buttons: 1 }));
        eq("nothing to show", "empty", S.suppressed({ count: 0 }));
        eq("the strip's check leaves the count out", "", S.suppressed({ buttons: 0 }));

        // which workspaces, in what order
        const ws = [
            { id: 4, name: "4", monitor: "DP-1" }, { id: 1, name: "1", monitor: "DP-1" },
            { id: 2, name: "2", monitor: "DP-1" }, { id: 3, name: "3", monitor: "HDMI-A-1" },
            { id: -98, name: "special:scratchpad", monitor: "DP-1" }, { id: 6, name: "6", monitor: "DP-1" },
            { id: 9, name: "special:x", monitor: "DP-1" }
        ];
        const cl = [c("0xa", 1, 0), c("0xb", 2, 3), c("0xc", 2, 1), c("0xd", 4, 2), c("0xe", 3, 4), c("0xf", -98, 5),
                    c("0x10", 4, 7, { hidden: true }), c("0x11", 9, 6)];
        const st = S.stacks(ws, cl, "DP-1", 1, 3);
        eq("this monitor's other non-empty workspaces, by number", [2, 4], st.map(s => s.id));
        eq("most recently focused first", ["0xc", "0xb"], st[0].windows.map(w => w.address));
        eq("a hidden group tab is not drawn", ["0xd"], st[1].windows.map(w => w.address));
        eq("the active workspace is left out", [1, 2, 4], S.stacks(ws, cl, "DP-1", 6, 3).map(s => s.id));
        eq("the other monitor has its own", [3], S.stacks(ws, cl, "HDMI-A-1", 1, 3).map(s => s.id));
        eq("no monitor, nothing", [], S.stacks(ws, cl, "", 1, 3));
        eq("bad input, nothing", [], S.stacks(null, null, "DP-1", 1, 3));
        eq("a workspace listed twice counts once", [2, 4], S.stacks(ws.concat([{ id: 2, name: "2", monitor: "DP-1" }]), cl, "DP-1", 1, 3).map(s => s.id));
        eq("the name is kept for the badge", "2", st[0].name);
        eq("the window object passes through untouched", cl[2], st[0].windows[0]);

        // a stack's windows
        const many = [c("0x1", 5, 4), c("0x2", 5, 0), c("0x3", 5, undefined), c("0x4", 5, 2), c("0x5", 5, 1)];
        eq("at most max, newest first, unnumbered last", ["0x2", "0x5", "0x4"], S.stackWindows(many, 5, 3).map(w => w.address));
        eq("an unnumbered window comes after every numbered one", ["0x2", "0x5", "0x4", "0x1", "0x3"], S.stackWindows(many, 5, 9).map(w => w.address));
        eq("max 0 is nothing", [], S.stackWindows(many, 5, 0));
        eq("ties break on the address, stable", ["0x7", "0x8"], S.stackWindows([c("0x8", 1, 3), c("0x7", 1, 3)], 1, 3).map(w => w.address));

        // sizes
        const m = S.metrics(1536, 840, 4, 3, 30);
        eq("a 1536 px screen: plane and steps", [200, 124, 16, 14], [m.planeWidth, m.planeHeight, m.step, m.rise]);
        eq("four stacks fit, centred", [4, true], [m.shown, m.top > 0]);
        eq("the stack's width holds the fan", m.planeWidth + 2 * m.step, m.stackWidth);
        eq("a wide screen caps the plane", 260, S.metrics(3840, 2000, 2, 3, 30).planeWidth);
        eq("a narrow screen keeps a floor", 160, S.metrics(800, 2000, 2, 3, 30).planeWidth);
        const crowded = S.metrics(1536, 840, 12, 3, 30);
        eq("many stacks shrink, to half at most", [crowded.planeWidth < 200, crowded.planeWidth >= 100], [true, true]);
        eq("and then show what fits", true, crowded.shown < 12 && crowded.shown * crowded.slot <= 840);
        eq("no stacks, no rows", 0, S.metrics(1536, 840, 0, 3, 30).shown);
        eq("one window a stack needs no fan", m.planeWidth, S.metrics(1536, 840, 4, 1, 30).stackWidth);

        // cards keep their windows' relative size, inside the plane
        eq("the front window fills the plane as its shape allows", { width: 196, height: 124 }, S.cardSize(1600, 1012, 1600, 1012, 200, 124));
        eq("a smaller window behind stays smaller", { width: 98, height: 62 }, S.cardSize(800, 506, 1600, 1012, 200, 124));
        eq("a bigger one is cut to the plane", { width: 200, height: 124 }, S.cardSize(3200, 2024, 1600, 1012, 200, 124));
        eq("an unknown size takes the front's", S.cardSize(1600, 1012, 1600, 1012, 200, 124), S.cardSize(0, 0, 1600, 1012, 200, 124));
        eq("never below 16 px", { width: 16, height: 16 }, S.cardSize(10, 10, 1600, 1012, 200, 124));

        // the fan
        eq("the front card", { dx: 0, dy: 0, scale: 1, opacity: 1, z: 3 }, S.fan(0, 3, 16, 14, false));
        eq("the second steps away and up, dimmer", { dx: 16, dy: 14, scale: 0.94, opacity: 0.85, z: 2 }, S.fan(1, 3, 16, 14, false));
        eq("the third further", { dx: 32, dy: 28, scale: 0.88, opacity: 0.7, z: 1 }, S.fan(2, 3, 16, 14, false));
        eq("under the pointer they spread", [24, 21], [S.fan(1, 3, 16, 14, true).dx, S.fan(1, 3, 16, 14, true).dy]);
        eq("an index past the stack is the last card", S.fan(2, 3, 16, 14, false), S.fan(7, 3, 16, 14, false));
        eq("on the left a card steps right", 16, S.cardX("left", 16, 100, 232));
        eq("on the right it steps left", 116, S.cardX("right", 16, 100, 232));

        // the turn towards the middle
        eq("left edge: positive, far side away", 50, S.tilt("left", 50, false));
        eq("right edge: mirrored", -50, S.tilt("right", 50, false));
        eq("under the pointer it turns part way back", [28, -28], [S.tilt("left", 50, true), S.tilt("right", 50, true)]);
        eq("tilt 0 is flat", [0, 0], [S.tilt("left", 0, false), Math.abs(S.tilt("right", 0, true))]);
        eq("over 60 is 60", 60, S.tilt("left", 90, false));
        eq("the axis is the edge side", [0, 232], [S.tiltOriginX("left", 232), S.tiltOriginX("right", 232)]);
        eq("hidden past the edge", [-260, 260, 0, 0], [S.slideX("left", 260, false), S.slideX("right", 260, false), S.slideX("left", 260, true), S.slideX("right", 260, true)]);

        // the switch
        eq("Lua dispatch", "hl.dsp.focus({ workspace = \"3\" })", S.focusCommand(3, true));
        eq("legacy dispatch", "workspace 3", S.focusCommand(3, false));
        eq("only a workspace number reaches the compositor", ["", "", "", ""], [S.focusCommand(0, true), S.focusCommand(-98, true), S.focusCommand("3; exit", false), S.focusCommand(2.5, true)]);
        eq("a plain class is an icon name", "kitty", S.themeIcon("Kitty"));
        eq("a path or URL a client set is not", ["application-x-executable", "application-x-executable"], [S.themeIcon("/tmp/x.svg"), S.themeIcon("http://host/x.png")]);
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
    assert_eq "js unit count" "61" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    engine_skip "qml runner missing: $QML"
fi

# --- the real engine: the service, and the stage drawn --------------------------
have_engine() { [[ -x $QS_BIN ]] && command -v dbus-run-session >/dev/null; }

# harness DIR — a shell dir whose modules and plugins are the tree's.
harness() {
    mkdir -p "$1"
    local module
    for module in Haseen Compat Ui Commons; do ln -s "$HASEEN_PATH/shell/$module" "$1/$module"; done
    ln -s "$HASEEN_PATH/shell/plugins" "$1/plugins"
}

# engine DIR [SCALE] — run the harness in DIR offscreen on the software
# renderer, in its own process group with a short runtime dir of its own (a
# worktree's long path would break qs's socket); OUTPUT and STATUS set.
engine() {
    local dir=$1 scale=${2:-1} run group
    run="$(mktemp -d "${TMPDIR:-/tmp}/stage.XXXXXX")"
    chmod 700 "$run"
    setsid env XDG_RUNTIME_DIR="$run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
        QT_NO_XDG_DESKTOP_PORTAL=1 QT_SCALE_FACTOR="$scale" STAGE_DIR="$SANDBOX" \
        timeout -k 5 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$dir" \
        >"$SANDBOX/engine.out" 2>&1 &
    group=$!
    STATUS=0
    wait "$group" || STATUS=$?
    kill -- -"$group" 2>/dev/null || true
    OUTPUT="$(cat "$SANDBOX/engine.out")"
    rm -rf "$run"
}
result() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT" | head -n1; }

if ! have_engine; then
    engine_skip "quickshell engine missing: the service and the draw were not exercised"
    return 0
fi

# The service with no compositor: nothing to show, so a toggle is refused;
# the edge is quiet in the game context; a held button keeps it quiet.
sandbox stage-service
svc="$SANDBOX/shell"
harness "$svc"
cat >"$svc/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.stage" as St

ShellRoot {
    St.Service {
        id: svc
        pluginId: "haseen.stage"
        settings: ({ edge: "right", dwell: 50 })
    }
    Timer {
        interval: 1200
        running: true
        onTriggered: {
            const s = Quickshell.screens[0];
            console.warn("RESULT cfg " + JSON.stringify(svc.cfg));
            console.warn("RESULT quiet " + JSON.stringify([svc.quietReason(s, 0), svc.quietReason(s, 1)]));
            console.warn("RESULT toggle " + svc.toggle());
            console.warn("RESULT open " + (svc.stageScreen !== null));
            console.warn("RESULT stacks " + JSON.stringify(svc.stacksFor(s)));
            Qt.quit();
        }
    }
}
QML
engine "$svc"
assert_status "the service runs in the real engine" 0 "$STATUS"
assert_eq "its settings are checked" '{"edge":"right","dwell":100,"maxWindows":3,"tilt":50}' "$(result cfg)"
assert_eq "the edge may open; a held button keeps it quiet" '["","dragging"]' "$(result quiet)"
assert_eq "no compositor, nothing to show: the toggle is refused" "refused: empty" "$(result toggle)"
assert_eq "and nothing opened" "false" "$(result open)"
assert_eq "no stacks without a monitor" "[]" "$(result stacks)"
assert_not_contains "the service has no QML error" "$OUTPUT" "plugins/haseen.stage/Service.qml:"
mkdir -p "$XDG_STATE_HOME/haseen/flags"
echo game >"$XDG_STATE_HOME/haseen/flags/context"
engine "$svc"
assert_eq "the game context keeps the edge quiet" '["game","game"]' "$(result quiet)"

# The stage drawn on the software renderer, at 1 and 1.25: a solid blue
# desktop, and stacks whose front windows are red and whose windows behind
# are lime. Before the column slides in nothing is drawn; after, the first
# stack's front card is taller at its edge side than at its far side (the
# turn), nothing is drawn past the column, and tilt 0 draws it flat.
if ! command -v magick >/dev/null; then
    engine_skip "magick missing: the stage's pixels were not read back"
    return 0
fi
sandbox stage-draw
draw="$SANDBOX/shell"
harness "$draw"
magick -size 160x100 xc:red "$SANDBOX/front.png"
magick -size 160x100 xc:lime "$SANDBOX/back.png"
cat >"$draw/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.stage" as St

ShellRoot {
    id: shell
    readonly property string dir: Quickshell.env("STAGE_DIR")
    readonly property string edge: Quickshell.env("STAGE_EDGE")
    function w(address, file) {
        return { address: address, cls: "", width: 1600, height: 1000, toplevel: null, icon: "", preview: "file://" + dir + "/" + file + ".png" };
    }
    function grab(name, then) {
        stage.grabToImage(r => {
            r.saveToFile(dir + "/" + name + ".png");
            then();
        });
    }

    FloatingWindow {
        implicitWidth: 1200
        implicitHeight: 800
        visible: true

        Rectangle {
            id: stage
            width: 1200
            height: 800
            color: "blue"

            St.StageView {
                id: view
                width: columnWidth
                height: parent.height
                x: shell.edge === "right" ? parent.width - width : 0
                edge: shell.edge
                tilt: Number(Quickshell.env("STAGE_TILT"))
                maxWindows: 3
                screenWidth: 1200
                stacks: [
                    { id: 2, name: "2", windows: [shell.w("0x1", "front"), shell.w("0x2", "back")] },
                    { id: 3, name: "3", windows: [shell.w("0x3", "front")] }
                ]
                capture: false
                entered: true
                onClosed: shell.closed++
            }
        }
    }
    property int closed: 0

    // A close asked for before the column slid in closes at once; one
    // asked for while it is out closes when it has slid out.
    Timer {
        interval: 500
        running: true
        onTriggered: shell.grab("hidden", () => {
            view.hide();
            view.show();
            settle.start();
        })
    }
    Timer {
        id: out
        interval: 600
        onTriggered: {
            console.warn("RESULT closed " + shell.closed + " " + view.shown);
            Qt.quit();
        }
    }
    Timer {
        id: settle
        interval: 900
        onTriggered: {
            const stack = view.rail.children.filter(c => c.modelData !== undefined).sort((a, b) => a.y - b.y)[0];
            const plane = stack.children[0];
            const near = plane.mapToItem(stage, shell.edge === "right" ? plane.width : 0, 0);
            console.warn("RESULT column " + view.columnWidth);
            console.warn("RESULT near " + JSON.stringify([Math.round(near.x), Math.round(near.y)]));
            console.warn("RESULT plane " + JSON.stringify([plane.width, plane.height]));
            console.warn("RESULT early " + shell.closed);
            shell.grab("shown", () => {
                view.hide();
                out.start();
            });
        }
    }
}
QML
# red_run IMAGE X — the number of red pixels in column X of IMAGE.
red_run() {
    magick "$1" -crop "1x100000+$2+0" +repage -fx 'r > 0.8 && g < 0.3 && b < 0.3 ? 1 : 0' -format '%[fx:round(mean*h)]' info:
}
any_red() {
    magick "$1" -fx 'r > 0.8 && g < 0.3 && b < 0.3 ? 1 : 0' -format '%[fx:maxima]' info:
}
for edge in left right; do
    for scale in 1 1.25; do
        at=" ($edge edge, scale $scale)"
        rm -f "$SANDBOX/hidden.png" "$SANDBOX/shown.png"
        STAGE_EDGE=$edge STAGE_TILT=50 engine "$draw" "$scale"
        assert_status "the stage draws$at" 0 "$STATUS"
        assert_eq "the stage loads without a QML error$at" "" "$(grep -E 'plugins/haseen.stage/[A-Za-z]+\.qml:[0-9]+' <<<"$OUTPUT" || true)"
        [[ -s $SANDBOX/shown.png ]] || continue
        assert_eq "nothing is drawn before it slides in$at" "0" "$(any_red "$SANDBOX/hidden.png")"
        read -r nx _ < <(result near | jq -r '@tsv')
        read -r pw _ < <(result plane | jq -r '@tsv')
        column="$(result column)"
        # Pixels: logical coordinates times the scale. The near column is 4 px
        # in from the card's edge side; the far one 35 % of the plane in, inside the turned card.
        if [[ $edge == left ]]; then
            near_x=$(awk -v x="$nx" -v s="$scale" 'BEGIN { printf "%d", (x + 4) * s }')
            far_x=$(awk -v x="$nx" -v w="$pw" -v s="$scale" 'BEGIN { printf "%d", (x + w * 0.35) * s }')
            outside_x=$(awk -v c="$column" -v s="$scale" 'BEGIN { printf "%d", (c + 2) * s }')
        else
            near_x=$(awk -v x="$nx" -v s="$scale" 'BEGIN { printf "%d", (x - 4) * s }')
            far_x=$(awk -v x="$nx" -v w="$pw" -v s="$scale" 'BEGIN { printf "%d", (x - w * 0.35) * s }')
            outside_x=$(awk -v c="$column" -v s="$scale" 'BEGIN { printf "%d", (1200 - c - 2) * s }')
        fi
        near_run="$(red_run "$SANDBOX/shown.png" "$near_x")"
        far_run="$(red_run "$SANDBOX/shown.png" "$far_x")"
        assert_eq "the front card is drawn$at" "true" "$(awk -v n="$near_run" -v s="$scale" 'BEGIN { print (n > 60 * s) ? "true" : "false" }')"
        assert_eq "it turns towards the middle: its far side is shorter$at" "true" \
            "$(awk -v n="$near_run" -v f="$far_run" 'BEGIN { print (f > 0 && f < n * 0.95) ? "true" : "false" }')"
        assert_eq "nothing is drawn past the column$at" "0" "$(red_run "$SANDBOX/shown.png" "$outside_x")"
        assert_eq "a close before it slid in closes at once$at" "1" "$(result early)"
        assert_eq "a close while out slides out, then closes$at" "2 false" "$(result closed)"
    done
done
STAGE_EDGE=left STAGE_TILT=0 engine "$draw" 1
if [[ -s $SANDBOX/shown.png ]]; then
    read -r nx _ < <(result near | jq -r '@tsv')
    read -r pw _ < <(result plane | jq -r '@tsv')
    near_run="$(red_run "$SANDBOX/shown.png" "$((nx + 4))")"
    far_run="$(red_run "$SANDBOX/shown.png" "$(awk -v x="$nx" -v w="$pw" 'BEGIN { printf "%d", x + w * 0.6 }')")"
    assert_eq "tilt 0 draws a flat fan: both sides the same height" "$near_run" "$far_run"
else
    assert_eq "the flat stage draws" "drawn" "missing"
fi
