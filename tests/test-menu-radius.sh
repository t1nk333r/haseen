# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.menu rounds its card with the frame's radius, live (plan 046, audit
# finding F5): the menu Panel.qml under the real engine follows a frame.radius
# edit in ~/.config/haseen/shell.json at once, as the frame does, instead of
# waiting for the next `haseen theme set`.

QS_BIN=${QS_BIN:-/usr/bin/qs}
MENU_PANEL="$HASEEN_PATH/shell/plugins/haseen.menu/Panel.qml"

assert_not_contains "the menu keeps no radius of its own" "$(cat "$MENU_PANEL")" "windowRadius"

if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; the menu radius was not run" >&2
else
    sandbox menu-radius
    harness="$SANDBOX/shell"
    mkdir -p "$harness" "$SANDBOX/run" "$XDG_CONFIG_HOME/haseen"
    chmod 700 "$SANDBOX/run"
    stub qs 'exit 0'
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    CFG="$XDG_CONFIG_HOME/haseen/shell.json"
    printf '{"frame": {"radius": 20}}\n' >"$CFG"
    # Phase 0: the panel is made once Config has read frame.radius 20. Phase 1:
    # the probe rewrites shell.json to 5 and waits for Config to see it, with
    # no theme set in between. Each phase records the menu's radius.
    cat >"$harness/shell.qml" <<QML
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
ShellRoot {
    id: probe
    property var panel: null
    property int phase: 0
    property var result: ({})
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (probe.phase === 0 && Plugins.ready && Config.frameRadius === 20) {
                const c = Qt.createComponent(Plugins.entryUrl("haseen.menu", "panel"));
                if (c.status !== Component.Ready) {
                    console.log("RESULT " + JSON.stringify({ error: c.errorString() }));
                    Qt.quit();
                    return;
                }
                probe.panel = c.createObject(null, { pluginId: "haseen.menu", settings: Plugins.settingsFor("haseen.menu") });
                probe.result.frame20 = Config.frameRadius;
                probe.result.menu20 = probe.panel.cornerRadius;
                probe.phase = 1;
                writer.running = true;
            } else if (probe.phase === 1 && Config.frameRadius === 5) {
                probe.result.frame5 = Config.frameRadius;
                probe.result.menu5 = probe.panel.cornerRadius;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
    Process {
        id: writer
        command: ["sh", "-c", "printf '{\"frame\": {\"radius\": 5}}\\\\n' >'$CFG'"]
    }
    Timer {
        interval: 20000
        running: true
        onTriggered: {
            console.log("RESULT " + JSON.stringify(probe.result));
            Qt.quit();
        }
    }
}
QML
    capture env HASEEN_PATH="$HASEEN_PATH" XDG_RUNTIME_DIR="$SANDBOX/run" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' \
        QT_QUICK_BACKEND=software timeout 30 "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
    [[ -n $result ]] || _fail "the menu harness produced no result" "$OUTPUT"
    r() { jq -r "$1" <<<"$result"; }
    assert_eq "the harness made the menu panel" "null" "$(r .error)"
    assert_eq "the frame reads frame.radius 20" "20" "$(r .frame20)"
    assert_eq "the menu rounds at the frame's 20" "20" "$(r .menu20)"
    assert_eq "an edit to 5 reaches the frame" "5" "$(r .frame5)"
    assert_eq "and the menu, with no theme set" "5" "$(r .menu5)"
fi
