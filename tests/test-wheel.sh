# shellcheck shell=bash
# haseen:covers share/haseen/shell/Haseen/Widgets/{BarButton,TrackBar}.qml
# haseen:covers share/haseen/shell/plugins/haseen.audio/VolumeRow.qml
# haseen:covers share/haseen/shell/plugins/haseen.calendar/Panel.qml
# haseen:covers share/haseen/shell/plugins/haseen.prayers/PrayerSlider.qml
# haseen:covers share/haseen/shell/plugins/haseen.workspaces/Widget.qml
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The wheel on haseen's own sliders and steppers (plan 197): one step per
# notch of 120 angleDelta, as BarButton has done since plan 091. Touchpads and
# hi-res wheels send fractions of a notch, which add up; a sideways or zero
# delta moves nothing. TrackBar (the media panel's seek and volume) and the
# audio panel's VolumeRow take real wheel events (QtTest's TestEvent) in the
# real Quickshell engine, offscreen; every other handler that reads
# angleDelta.y is checked for the same accumulator.

SHELL_DIR="$HASEEN_PATH/shell"

# --- every wheel handler accumulates -----------------------------------------
# The tray forwards the raw delta to the item (StatusNotifierItem.scroll) and
# Compat hosts Omarchy's and DMS's own widgets: neither steps by itself.
handlers="$(cd "$SHELL_DIR" && grep -rlE 'on[Ww]heel' --include='*.qml' . | grep -v '^\./Compat/' | sort)"
for f in $handlers; do
    grep -q 'angleDelta\.y' "$SHELL_DIR/$f" || continue
    [[ $f == ./plugins/haseen.tray/TrayItem.qml ]] && continue
    assert_contains "${f#./}: the wheel adds deltas up before it steps" "$(cat "$SHELL_DIR/$f")" "heelDelta += event.angleDelta.y"
done
assert_eq "no wheel handler steps on the sign of one event" "" \
    "$(cd "$SHELL_DIR" && grep -rnE 'angleDelta\.y *> *0 *\?|Math\.round\(event\.angleDelta\.y' --include='*.qml' . | grep -v '^\./Compat/' || true)"

# --- TrackBar and VolumeRow in the real engine ---------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: qs missing; wheel events not sent" >&2
else
    sandbox wheel
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$SHELL_DIR/$module" "$harness/$module"
    done
    ln -s "$SHELL_DIR/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import QtTest
import qs.Haseen
import qs.Haseen.Widgets
import "plugins/haseen.audio" as Audio

ShellRoot {
    id: probe

    property var out: ({})

    // The MouseArea that owns the wheel: the track's, the one that keeps a
    // drag from being stolen.
    function wheelArea(item: var): var {
        if (item.preventStealing === true)
            return item;
        for (const child of item.children) {
            const hit = wheelArea(child);
            if (hit)
                return hit;
        }
        return null;
    }

    // Each phase from 0.5: a sideways notch, a zero delta, eight eighths of
    // a notch up, one notch down, two notches up in one event.
    function phases(target: var, read: var, reset: var): var {
        const area = wheelArea(target);
        if (!area)
            return "no wheel area";
        const x = area.width / 2, y = area.height / 2;
        const seen = [];
        reset();
        events.mouseWheel(area, x, y, 0, 0, 120, 0, -1);
        seen.push(read());
        events.mouseWheel(area, x, y, 0, 0, 0, 0, -1);
        seen.push(read());
        for (let i = 0; i < 8; i++)
            events.mouseWheel(area, x, y, 0, 0, 0, 15, -1);
        seen.push(read());
        events.mouseWheel(area, x, y, 0, 0, 0, -120, -1);
        seen.push(read());
        events.mouseWheel(area, x, y, 0, 0, 0, 240, -1);
        seen.push(read());
        return seen.map(v => Math.round(v * 100));
    }

    QtObject {
        id: node

        property real volume: 0.5
        property bool muted: false
    }

    FloatingWindow {
        implicitWidth: 320
        implicitHeight: 120
        visible: true

        Column {
            width: 300

            TrackBar {
                id: bar

                width: 300
                onMoved: v => value = v
            }

            Audio.VolumeRow {
                id: row

                width: 300
                audio: node
                glyph: "x"
                label: "Speakers"
            }
        }

        Item {
            TestEvent {
                id: events
            }
        }
    }

    Timer {
        interval: 800
        running: true
        onTriggered: {
            probe.out = {
                trackbar: probe.phases(bar, () => bar.value, () => bar.value = 0.5),
                volume: probe.phases(row, () => node.volume, () => node.volume = 0.5)
            };
            console.warn("RESULT " + JSON.stringify(probe.out));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 "$QS_BIN" -p "$harness"
    assert_status "the wheel harness runs in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    # 50 % each: sideways 50, zero 50, eight eighths 55, a notch down 50,
    # two notches up 60.
    assert_eq "TrackBar: sideways and zero deltas move nothing; fractions add up to one step a notch" \
        "[50,50,55,50,60]" "$(jq -c .trackbar <<<"${RESULT:-null}")"
    assert_eq "VolumeRow: sideways and zero deltas move nothing; fractions add up to 5 % a notch" \
        "[50,50,55,50,60]" "$(jq -c .volume <<<"${RESULT:-null}")"
fi
