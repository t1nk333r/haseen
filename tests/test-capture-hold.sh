# shellcheck shell=bash
# haseen:covers share/haseen/shell/Haseen/{Capture.js,Capture.qml,qmldir} share/haseen/shell/Haseen/Widgets/{CaptureFocusGrab.qml,qmldir}
# haseen:covers share/haseen/shell/{PanelPopup.qml,BarOverflowPanel.qml,shell.qml}
# haseen:covers share/haseen/shell/Compat/Dms/Modules/Plugins/PluginPopout.qml share/haseen/shell/Compat/Omarchy/Ui/PopupCard.qml
# haseen:covers share/haseen/shell/plugins/haseen.tray/TrayMenu.qml share/haseen/shell/plugins/haseen.capture/Service.qml
# haseen:covers share/haseen/shell/plugins/haseen.stage/{StageView.qml,StageWindow.qml} tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# A screenshot keeps what it captures on screen (plan 184): the capture
# tools' layers counted from Hyprland's events (Capture.js under Qt's own
# engine), the Capture singleton and CaptureFocusGrab in the real Quickshell
# engine (the toolbar and expect() hold, a capture's end gives the keyboard
# back and re-arms the grab, the toolbar's own panel is not held), and every
# focus grab, the stage and the toolbar wired to them.

SHELL_DIR="$HASEEN_PATH/shell"
QML=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

engine_skip() {
    echo "  skip: $1" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]] && assert_eq "$1: required engine prerequisite" available unavailable
    return 0
}

# --- every focus grab is the capture-aware one ---------------------------------
grabs="$(grep -rln 'HyprlandFocusGrab {' "$SHELL_DIR" | sed "s|^$SHELL_DIR/||" | sort | tr '\n' ' ')"
assert_eq "only CaptureFocusGrab uses Hyprland's grab directly" "Haseen/Widgets/CaptureFocusGrab.qml " "$grabs"
for f in PanelPopup.qml BarOverflowPanel.qml plugins/haseen.tray/TrayMenu.qml \
    Compat/Dms/Modules/Plugins/PluginPopout.qml Compat/Omarchy/Ui/PopupCard.qml; do
    assert_contains "$f: a screenshot holds its grab" "$(cat "$SHELL_DIR/$f")" "CaptureFocusGrab {"
done
assert_contains "Capture is a qs.Haseen singleton" "$(cat "$SHELL_DIR/Haseen/qmldir")" "singleton Capture 1.0 Capture.qml"
assert_contains "CaptureFocusGrab is a qs.Haseen.Widgets type" "$(cat "$SHELL_DIR/Haseen/Widgets/qmldir")" "CaptureFocusGrab 1.0 CaptureFocusGrab.qml"

popup="$(cat "$SHELL_DIR/PanelPopup.qml")"
assert_contains "a panel takes the keyboard again after a capture" "$popup" "onResumed: popup.focusPrimed = false"
assert_contains "the capture toolbar's own panel is not held" "$popup" "ignoresCapture: Plugins.roles.capture !== undefined && Plugins.roles.capture.id === popup.pluginId"
assert_contains "the overflow panel takes the keyboard again" "$(cat "$SHELL_DIR/BarOverflowPanel.qml")" "onResumed: panel.focusPrimed = false"

shellqml="$(cat "$SHELL_DIR/shell.qml")"
assert_contains "the capture toolbar opens over the open panel" "$shellqml" "openPanels = openPanels.concat([id]);"
assert_contains "only the capture role's panel does" "$shellqml" "capture && capture.id === id && openPanels.length > 0"

stage_view="$(cat "$SHELL_DIR/plugins/haseen.stage/StageView.qml")"
assert_contains "a capture is no leaving the stage" "$stage_view" "onTriggered: if (!view.inside && !Capture.active)"
assert_contains "the stage takes the keyboard again after a capture" "$(cat "$SHELL_DIR/plugins/haseen.stage/StageWindow.qml")" "win.focusPrimed = false;"

service="$(cat "$SHELL_DIR/plugins/haseen.capture/Service.qml")"
assert_contains "the toolbar and a waiting capture hold the rest" "$service" "value: root.panelOpen || root.pending"
expect_line=$(grep -n 'Capture.expect();' "$SHELL_DIR/plugins/haseen.capture/Service.qml" | cut -d: -f1)
pending_line=$(grep -n 'root.pending = false;' "$SHELL_DIR/plugins/haseen.capture/Service.qml" | tail -n1 | cut -d: -f1)
assert_eq "expect() comes before pending drops" "yes" "$([[ -n $expect_line && -n $pending_line ]] && ((expect_line < pending_line)) && echo yes || echo no)"

# --- Capture.js under Qt's own engine ---------------------------------------------
sandbox capture-hold-js
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$SHELL_DIR/Haseen/Capture.js" as C

QtObject {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + ": expected " + e + ", got " + a);
        }
    }

    Component.onCompleted: {
        eq("the capture tools' layers", [true, true, true, true], ["omasnap", "selection", "hyprpicker", "wayfreeze"].map(C.isCaptureLayer));
        eq("not the shell's, nor Omasnap's pin window", [false, false, false, false], ["haseen-overlay", "haseen-panel", "omasnap-pin", ""].map(C.isCaptureLayer));
        eq("an open counts", 1, C.nextCount(0, "openlayer", "omasnap"));
        eq("one per monitor", 2, C.nextCount(1, "openlayer", "omasnap"));
        eq("a close uncounts", 1, C.nextCount(2, "closelayer", "omasnap"));
        eq("a close never goes below zero", 0, C.nextCount(0, "closelayer", "selection"));
        eq("another layer changes nothing", 1, C.nextCount(1, "openlayer", "haseen-overlay"));
        eq("another event changes nothing", 1, C.nextCount(1, "activewindow", "omasnap"));
        Qt.exit(failures === 0 ? 0 : 1);
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
    assert_eq "js unit count" "8" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    engine_skip "qml runner missing: $QML"
fi

# --- the singleton and the grab in the real engine ----------------------------------
have_engine() { [[ -x $QS_BIN ]] && command -v dbus-run-session >/dev/null; }
if ! have_engine; then
    engine_skip "quickshell engine missing: Capture and CaptureFocusGrab were not exercised"
    return 0
fi

sandbox capture-hold-engine
dir="$SANDBOX/shell"
mkdir -p "$dir"
for module in Haseen Compat Ui Commons; do ln -s "$SHELL_DIR/$module" "$dir/$module"; done
ln -s "$SHELL_DIR/plugins" "$dir/plugins"
cat >"$dir/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

ShellRoot {
    id: root

    property int resumes: 0
    property int clears: 0
    property int toolbarClears: 0

    function note(name, value): void {
        console.warn("RESULT " + name + " " + JSON.stringify(value));
    }

    CaptureFocusGrab {
        id: grab
        active: true
        settle: 50
        rearm: 50
        onResumed: root.resumes++
        onCleared: root.clears++
    }
    CaptureFocusGrab {
        id: toolbarGrab
        active: true
        settle: 50
        ignoresCapture: true
        onCleared: root.toolbarClears++
    }

    // One step every 150 ms, three times the grabs' timers, so each step
    // reads what the last one's timers settled. Steps 5 to 19 only wait for
    // expect() to lapse (2 s).
    property int step: 0
    Timer {
        interval: 150
        repeat: true
        running: true
        onTriggered: {
            switch (root.step++) {
            case 0:
                root.note("rest", [Capture.active, grab.capturing, grab.held]);
                grab.grabCleared();
                break;
            case 1:
                root.note("a clear with no capture closes after the settle", [root.clears, grab.held]);
                Capture.toolbar = true;
                root.note("toolbar", [Capture.active, grab.capturing, toolbarGrab.capturing]);
                grab.grabCleared();
                toolbarGrab.grabCleared();
                root.note("a clear during a capture holds at once", [grab.held, root.clears]);
                Capture.toolbar = false;
                root.note("ended, not yet re-armed", [Capture.active, grab.held, root.resumes]);
                break;
            case 2:
                root.note("re-armed", [grab.held, root.resumes]);
                root.note("the toolbar's own panel still closes", root.toolbarClears);
                grab.grabCleared();
                Capture.toolbar = true;
                break;
            case 3:
                root.note("a capture reported after the clear still holds", [grab.held, root.clears]);
                Capture.toolbar = false;
                break;
            case 4:
                root.note("re-armed again", [grab.held, root.resumes]);
                Capture.expect();
                root.note("expecting", Capture.active);
                grab.hold();
                grab.active = false;
                root.note("inactive drops the hold", grab.held);
                break;
            case 20:
                root.note("expect lapses", Capture.active);
                root.note("no resume for an inactive grab", root.resumes);
                Qt.quit();
                break;
            }
        }
    }
}
QML
run="$(mktemp -d "${TMPDIR:-/tmp}/caphold.XXXXXX")"
chmod 700 "$run"
set +e
setsid env XDG_RUNTIME_DIR="$run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
    QT_NO_XDG_DESKTOP_PORTAL=1 \
    timeout -k 5 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$dir" \
    >"$SANDBOX/engine.out" 2>&1
STATUS=$?
set -e
rm -rf "$run"
OUTPUT="$(cat "$SANDBOX/engine.out")"
result() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT" | head -n1; }

assert_status "the engine run exits 0" 0 "$STATUS"
assert_eq "at rest: no capture, nothing held" "[false,false,false]" "$(result rest)"
assert_eq "a clear with no capture closes, after the settle" "[1,false]" "$(result 'a clear with no capture closes after the settle')"
assert_eq "the toolbar is a capture, except to its own panel" "[true,true,false]" "$(result toolbar)"
assert_eq "a clear during a capture holds at once" "[true,1]" "$(result 'a clear during a capture holds at once')"
assert_eq "the capture's end gives the keyboard back first, the grab later" "[false,true,1]" "$(result 'ended, not yet re-armed')"
assert_eq "then the grab starts again" "[false,1]" "$(result re-armed)"
assert_eq "the toolbar's own panel closes on a clear" "1" "$(result "the toolbar's own panel still closes")"
assert_eq "a capture reported just after the clear still holds" "[true,1]" "$(result 'a capture reported after the clear still holds')"
assert_eq "and gives the keyboard back again" "[false,2]" "$(result 're-armed again')"
assert_eq "a started capture command counts at once" "true" "$(result expecting)"
assert_eq "a grab that ends drops its hold" "false" "$(result 'inactive drops the hold')"
assert_eq "expect() lapses without a layer" "false" "$(result 'expect lapses')"
assert_eq "an inactive grab is not resumed" "2" "$(result 'no resume for an inactive grab')"
assert_eq "no QML error in the new files" "" "$(grep -E 'Haseen/(Capture|Widgets/CaptureFocusGrab)\.qml:[0-9]+' <<<"$OUTPUT" || true)"
