# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Native panel placement: a panel opened by a click on a bar widget sits
# centred under (or beside) that widget, clamped to the bar; one opened by a
# key, the CLI or the menu stays centred on the bar edge. The pure math in
# PanelPlacement.js runs under the real Qt JS engine; the wiring was proven in
# a nested Hyprland (plan 049), not by reading QML source here.

SHELL_DIR="$HASEEN_PATH/shell"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}

sandbox panel-placement
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/PanelPlacement.js" as P

Item {
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

    // Only the anchored edges, with their margins: the shape a test reads.
    function shape(r) {
        const out = {};
        for (const e of ["top", "bottom", "left", "right"])
            if (r[e])
                out[e] = r["margin" + e[0].toUpperCase() + e.slice(1)];
        return out;
    }

    function press(position, centre, extent, time) {
        return { screen: null, position: position, centre: centre, extent: extent, time: time };
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
        // placement "center": nothing anchored, the compositor centres it,
        // even when a bar press opened it.
        eq("center placement anchors nothing", {}, shape(P.place("top", press("top", 100, 1280, 0), 300, 200, 8, "center")));
        eq("bar placement keeps the bar edge", {top: 8}, shape(P.place("top", null, 300, 200, 8, "bar")));
        // Centre and clamp along a 1280 px bar, 8 px margin, 300 px popup.
        eq("offset centred on the widget", 490, P.offset(640, 300, 1280, 8));
        eq("offset rounds", 491, P.offset(640.6, 300, 1280, 8));
        eq("offset clamped at the start", 8, P.offset(20, 300, 1280, 8));
        eq("offset clamped at the end", 972, P.offset(1250, 300, 1280, 8));
        eq("popup wider than the bar starts at the margin", 8, P.offset(640, 1300, 1280, 8));

        // A click on a widget: the bar edge plus the start of the bar.
        const now = 100000;
        eq("top bar, right widget", { top: 8, left: 972 }, shape(P.place("top", press("top", 1250, 1280, now), 300, 400, 8)));
        eq("top bar, left widget", { top: 8, left: 8 }, shape(P.place("top", press("top", 30, 1280, now), 300, 400, 8)));
        eq("top bar, middle widget", { top: 8, left: 490 }, shape(P.place("top", press("top", 640, 1280, now), 300, 400, 8)));
        eq("bottom bar", { bottom: 8, left: 90 }, shape(P.place("bottom", press("bottom", 240, 1280, now), 300, 400, 8)));
        eq("left bar uses the height", { top: 200, left: 8 }, shape(P.place("left", press("left", 400, 800, now), 300, 400, 8)));
        eq("right bar, low widget", { top: 392, right: 8 }, shape(P.place("right", press("right", 780, 800, now), 300, 400, 8)));
        eq("right bar, high widget", { top: 8, right: 8 }, shape(P.place("right", press("right", 10, 800, now), 300, 400, 8)));

        // A key, the CLI or the menu: only the bar edge, so Hyprland centres
        // the popup along it.
        for (const pos of ["top", "bottom", "left", "right"]) {
            const want = {};
            want[pos] = 8;
            eq("no opener centres on the " + pos + " edge", want, shape(P.place(pos, null, 300, 400, 8)));
        }
        eq("unknown position falls back to top", { top: 8 }, shape(P.place("middle", null, 300, 400, 8)));
        eq("a press from another bar position centres", { left: 8 }, shape(P.place("left", press("top", 640, 1280, now), 300, 400, 8)));
        eq("a press without an extent centres", { top: 8 }, shape(P.place("top", press("top", 640, 0, now), 300, 400, 8)));

        // Pairing a toggle with the press that caused it.
        const p = press("top", 640, 1280, now);
        eq("toggle right after the click uses it", true, P.opener(p, now + 200) === p);
        eq("toggle just inside the window uses it", true, P.opener(p, now + P.OPENER_MS - 1) === p);
        eq("a key after the window centres", null, P.opener(p, now + P.OPENER_MS));
        eq("a key long after the click centres", null, P.opener(p, now + 60000));
        eq("no press centres", null, P.opener(null, now));
        eq("a press from the future is ignored", null, P.opener(p, now - 10));
    }
}
EOF
if [[ -x $QML_BIN ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "placement unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "placement unit count" "27" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML_BIN"
fi
