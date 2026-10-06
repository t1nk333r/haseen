# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Actual Quickshell engine, no windows or compositor (plan 027). Three
# consumer-visible lifetimes:
#   - a native overlay-only plugin must be reachable through summon/toggle,
#     which route overlay-kind records through the overlays map;
#   - repeated entry reloads must not accumulate QML components on the host;
#   - two instances of one plugin writing different keys from their own
#     snapshots must both survive (the second write must not revert the first).
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; compat lifetime scenario not run" >&2
else
    sandbox compat-lifetime
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-lifetime.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS

    plugin="$HOME/.config/haseen/plugins/me.veil"
    mkdir -p "$plugin"
    cat >"$plugin/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.veil","name":"Veil","version":"1.0.0","kinds":["overlay"],"entry":{"overlay":"Overlay.qml"}}
JSON
    cat >"$plugin/Overlay.qml" <<'QML'
import QtQuick
Item {
    property string pluginId: ""
    property var settings: ({})
    property string view: ""
    property bool opened: false
    function open() { opened = true; return true; }
    function close() { opened = false; }
}
QML
    cat >"$HOME/.config/haseen/shell.json" <<'JSON'
{"bar":{"left":[],"center":[],"right":[]},"services":["me.veil"],"plugins":{"me.veil":{"settings":{"a":1,"b":1}}}}
JSON
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    ln -s "$HASEEN_PATH/shell/ServiceHost.qml" "$harness/ServiceHost.qml"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import "Compat/Host.js" as Host
ShellRoot {
    id: probe
    property int phase: 0
    property int cycles: 0
    property var result: ({})
    property QtObject apiA: Compat.ShellApi { pluginId: "me.veil" }
    property QtObject apiB: Compat.ShellApi { pluginId: "me.veil" }
    function live() { return Plugins.settingsFor("me.veil"); }
    Instantiator {
        model: ScriptModel { values: Plugins.serviceKeys }
        delegate: ServiceHost {}
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            const overlay = Compat.Runtime.overlayFor("me.veil");
            if (probe.phase === 0 && Plugins.ready && overlay) {
                probe.result.summoned = Compat.Runtime.summon("me.veil", JSON.stringify({view: "details"}));
                probe.result.openedAfterSummon = overlay.opened;
                probe.result.payloadView = overlay.view;
                probe.result.toggleClosed = Compat.Runtime.toggle("me.veil", "") && !overlay.opened;
                probe.result.toggleOpened = Compat.Runtime.toggle("me.veil", JSON.stringify({view: "grid"})) && overlay.opened;
                probe.result.componentsLoaded = Host.liveComponents();
                Config.setRuntime(["plugins", "me.veil", "enabled"], false);
                probe.phase = 1;
            } else if (probe.phase === 1 && !overlay) {
                Config.setRuntime(["plugins", "me.veil", "enabled"], true);
                probe.phase = 2;
            } else if (probe.phase === 2 && overlay) {
                probe.cycles++;
                if (probe.cycles < 3) {
                    Config.setRuntime(["plugins", "me.veil", "enabled"], false);
                    probe.phase = 1;
                } else {
                    probe.result.reloads = probe.cycles;
                    probe.result.componentsAfterReloads = Host.liveComponents();
                    probe.apiA.updateEntryInline("me.veil", {a: 2, b: 1});
                    probe.phase = 3;
                }
            } else if (probe.phase === 3 && probe.live().a === 2) {
                // The second instance still tracks the shell: it copies what it
                // was delivered and changes its own key.
                probe.apiB.updateEntryInline("me.veil", {a: probe.live().a, b: 2});
                probe.phase = 4;
            } else if (probe.phase === 4 && probe.live().b === 2) {
                // The first instance assigned its own settings when it wrote,
                // so its copy never saw b: 2. It changes only a.
                probe.apiA.updateEntryInline("me.veil", {a: 3, b: 1});
                probe.phase = 5;
            } else if (probe.phase === 5 && probe.live().a === 3) {
                probe.result.finalA = probe.live().a;
                probe.result.finalB = probe.live().b;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "compat lifetime scenario completes in the real engine" 0 "$STATUS"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "native overlay-only plugin answers summon" true "$(jq -r .summoned <<<"$result")"
        assert_eq "summon opens the native overlay provider" true "$(jq -r .openedAfterSummon <<<"$result")"
        assert_eq "native overlay receives the summon payload" details "$(jq -r .payloadView <<<"$result")"
        assert_eq "toggle closes the open native overlay" true "$(jq -r .toggleClosed <<<"$result")"
        assert_eq "toggle reopens the native overlay" true "$(jq -r .toggleOpened <<<"$result")"
        assert_eq "one component per loaded entry" 1 "$(jq -r .componentsLoaded <<<"$result")"
        assert_eq "three reload cycles ran" 3 "$(jq -r .reloads <<<"$result")"
        assert_eq "reloads release the previous entry component" 1 "$(jq -r .componentsAfterReloads <<<"$result")"
        assert_eq "the writing instance's own key is stored" 3 "$(jq -r .finalA <<<"$result")"
        assert_eq "a stale instance write keeps the other instance's key" 2 "$(jq -r .finalB <<<"$result")"
    else
        _fail "compat lifetime result not produced" "$OUTPUT"
    fi
fi
