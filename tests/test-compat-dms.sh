# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The DMS compat APIs bar plugins use beyond the basics (architecture 5.4):
# popouts (PluginPopout, PopoutComponent), Proc.runCommand, the plugin state
# files, BatteryService without a battery, PopoutService's settings pages,
# DankListView and a plugin's own qmldir singleton. Fixture plugins drive
# them inside a real Quickshell. The sandbox's stub PATH stands in front of
# every state-changing command (pkexec, sudo, …), so a plugin's privileged
# call reaches a stub, never the system.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; DMS compat scenario not run" >&2
else
    sandbox compat-dms
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-dms.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    # A read-only probe answers like TLP; a recorder counts debounced runs.
    stub tlp-stat 'echo "Power source   = AC"'
    stub record-run "echo run >>'$SANDBOX/runs.log'"
    P="$XDG_CONFIG_HOME/haseen/plugins"
    STATE="$XDG_STATE_HOME/haseen/plugins"
    mkdir -p "$P/PopFixture" "$P/ClickFixture" "$STATE"
    printf '%s\n' '{"count":41,"kept":"yes"}' >"$STATE/popFixture_state.json"
    cat >"$P/PopFixture/plugin.json" <<'JSON'
{"id":"popFixture","name":"Pop","version":"1.0.0","type":"widget","component":"./Widget.qml","permissions":["process"]}
JSON
    # A singleton from the plugin's own qmldir, as plugins ship services.
    printf 'singleton FixtureState 1.0 FixtureState.qml\n' >"$P/PopFixture/qmldir"
    cat >"$P/PopFixture/FixtureState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { readonly property string value: "local" }
QML
    cat >"$P/PopFixture/Widget.qml" <<'QML'
import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
PluginComponent {
    id: root
    property var shown: null
    readonly property string localValue: FixtureState.value
    popoutWidth: 300
    horizontalBarPill: Component { StyledText { text: "pop" } }
    popoutContent: Component {
        PopoutComponent {
            id: pc
            headerText: "Fixture"
            Component.onCompleted: root.shown = pc
            Component.onDestruction: if (root.shown === pc) root.shown = null
            Item { width: parent.width; height: 100 }
        }
    }
    // What a plugin saves on its way out (shell reload or exit).
    Component.onDestruction: PluginService.savePluginState("popFixture", "bye", true)
}
QML
    cat >"$P/ClickFixture/plugin.json" <<'JSON'
{"id":"clickFixture","name":"Click","version":"1.0.0","type":"widget","component":"./Widget.qml"}
JSON
    cat >"$P/ClickFixture/Widget.qml" <<'QML'
import QtQuick
import qs.Widgets
import qs.Modules.Plugins
PluginComponent {
    id: root
    property int clicks: 0
    property string clickSection: ""
    property var shown: null
    horizontalBarPill: Component { StyledText { text: "click" } }
    pillClickAction: (x, y, width, section, screen) => { root.clicks++; root.clickSection = section; }
    popoutContent: Component { PopoutComponent { id: pc; Component.onCompleted: root.shown = pc } }
}
QML
    printf '%s\n' '{"bar":{"left":[],"center":[],"right":["dms.pop-fixture","dms.click-fixture"]},"plugins":{"dms.pop-fixture":{"enabled":true},"dms.click-fixture":{"enabled":true}},"services":[]}' >"$XDG_CONFIG_HOME/haseen/shell.json"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Common Services Widgets Modules; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import qs.Common
import qs.Services
import qs.Widgets
ShellRoot {
    id: probe
    property var r: ({})
    property int step: 0
    property double mark: 0
    property int stateSignals: 0
    property var hosts: loader.item
    function since() { return Date.now() - mark; }
    function next() { step++; mark = Date.now(); }
    function win(item) { return item && item.QsWindow ? item.QsWindow.window : null; }
    function finish() { console.log("RESULT " + JSON.stringify(r)); loader.active = false; Qt.quit(); }

    // The shell root, as far as Runtime and PopoutService use it.
    QtObject {
        id: fakeShell
        property var openPanels: []
        function togglePanel(id) { openPanels = openPanels.indexOf(id) >= 0 ? [] : [id]; }
        function closePanel(id) { openPanels = openPanels.filter(p => p !== id); }
        function focusedScreen() { return null; }
    }
    Connections {
        target: PluginService
        function onPluginStateChanged(id) { if (id === "popFixture") probe.stateSignals++; }
    }
    DankListView { id: list; model: 3; delegate: Item { height: 10 } }

    FloatingWindow {
        visible: true
        implicitWidth: 600
        implicitHeight: 30
        Loader {
            id: loader
            active: Plugins.ready
            sourceComponent: Row {
                property alias a: a
                property alias b: b
                property alias c: c
                height: 30
                Compat.DmsHost { id: a; pluginId: "dms.pop-fixture"; height: 30 }
                Compat.DmsHost { id: b; pluginId: "dms.pop-fixture"; height: 30 }
                Compat.DmsHost { id: c; pluginId: "dms.click-fixture"; height: 30 }
            }
        }
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            const h = probe.hosts, r = probe.r;
            if (!h || !h.a.widget || !h.b.widget || !h.c.widget) return;
            const A = h.a.widget, B = h.b.widget, C = h.c.widget;
            switch (probe.step) {
            case 0:
                Compat.Runtime.nativeShell = fakeShell;
                r.pill = A.implicitWidth > 0;
                r.localSingleton = A.localValue;
                fakeShell.openPanels = ["haseen.calendar"];
                A.triggerPopout();
                probe.next(); break;
            case 1:
                if (probe.since() < 300) break;
                r.opened = A.shown !== null;
                r.panelClosedByPopout = fakeShell.openPanels.length === 0;
                r.injectedClose = A.shown ? typeof A.shown.closePopout : "none";
                r.popoutWidth = probe.win(A.shown) ? probe.win(A.shown).implicitWidth : -1;
                r.popoutHeight = probe.win(A.shown) ? probe.win(A.shown).implicitHeight : -1;
                r.contentHeight = A.shown ? A.shown.implicitHeight : -1;
                B.triggerPopout();
                probe.next(); break;
            case 2:
                if (probe.since() < 300) break;
                r.switchClosesFirst = A.shown === null;
                r.switchOpensSecond = B.shown !== null;
                B.shown.closePopout();
                probe.next(); break;
            case 3:
                if (probe.since() < 300) break;
                r.closedByContent = B.shown === null;
                A.triggerPopout();
                probe.next(); break;
            case 4:
                if (probe.since() < 300) break;
                r.reopened = A.shown !== null;
                A.triggerPopout();
                probe.next(); break;
            case 5:
                if (probe.since() < 300) break;
                r.toggledShut = A.shown === null;
                A.triggerPopout();
                probe.next(); break;
            case 6:
                if (probe.since() < 300) break;
                fakeShell.openPanels = ["haseen.calendar"];
                r.panelClosesPopout = A.shown === null;
                fakeShell.openPanels = [];
                C.triggerPopout();
                probe.next(); break;
            case 7:
                if (probe.since() < 300) break;
                r.clickActionRan = C.clicks;
                r.clickSection = C.clickSection;
                r.clickActionWins = C.shown === null;
                PopoutService.openSettingsWithTab("network_wifi");
                r.settingsPage = fakeShell.openPanels.join(",");
                PopoutService.openSettingsWithTab("keybinds");
                r.unmappedPage = fakeShell.openPanels.join(",");
                // Proc.runCommand
                Proc.runCommand("t.out", ["tlp-stat", "-s"], (out, code) => { r.procOut = out.trim(); r.procCode = code; }, 0, 2000);
                Proc.runCommand("t.guard", ["pkexec", "tlp", "bat"], (out, code) => { r.guardCode = code; }, 0, 2000);
                Proc.runCommand("t.deb", ["record-run"], () => { r.debFirst = true; }, 100, 2000);
                Proc.runCommand("t.deb", ["record-run"], (out, code) => { r.debLast = code; }, 100, 2000);
                Proc.runCommand("t.slow", ["sleep", "5"], (out, code) => { r.slowCode = code; }, 0, 200);
                Proc.runCommand("t.missing", ["haseen-no-such-command"], (out, code) => { r.missingCode = code; }, 0, 3000);
                const owner = Qt.createQmlObject("import QtQuick; QtObject {}", probe);
                Proc.runCommand("t.owner", ["true"], () => { r.deadOwnerCalled = true; }, 100, 2000, owner);
                owner.destroy();
                // Plugin state
                r.stateLoaded = PluginService.loadPluginState("popFixture", "count", 0);
                r.stateDefault = PluginService.loadPluginState("popFixture", "absent", "dflt");
                PluginService.savePluginState("popFixture", "count", 42);
                PluginService.removePluginStateKey("popFixture", "kept");
                r.badId = PluginService.loadPluginState("../escape", "count", "refused");
                PluginService.savePluginState("../escape", "count", 1);
                // BatteryService with no UPower
                r.battery = [BatteryService.batteryAvailable, BatteryService.getBatteryIcon(), BatteryService.batteryStatus, BatteryService.formatTimeRemaining(), BatteryService.batteryHealth];
                r.errorHover = Math.round(Theme.errorHover.a * 100);
                r.list = [list.count, list.boundsBehavior === Flickable.StopAtBounds];
                probe.next(); break;
            case 8:
                if (probe.since() < 1500) break;
                r.stateSignals = probe.stateSignals;
                probe.finish();
            }
        }
    }
}
QML
    # No system bus: BatteryService sees no UPower, as on a desktop without one.
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SANDBOX/no-system-bus" \
        timeout 40 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        get() { jq -c "$1" <<<"$result"; }
        assert_eq "the fixture widget draws its pill" true "$(get .pill)"
        assert_eq "a singleton from the plugin's own qmldir resolves" '"local"' "$(get .localSingleton)"
        assert_eq "a pill click opens the popout content" true "$(get .opened)"
        assert_eq "opening a popout closes the open native panel" true "$(get .panelClosedByPopout)"
        assert_eq "the content gets closePopout()" '"function"' "$(get .injectedClose)"
        assert_eq "the popout is popoutWidth wide" 300 "$(get .popoutWidth)"
        assert_eq "the content is the header plus the plugin's items" 140 "$(get .contentHeight)"
        assert_eq "the popout is the content plus DMS's padding" 172 "$(get .popoutHeight)"
        assert_eq "a second popout closes the first" true "$(get .switchClosesFirst)"
        assert_eq "and opens itself" true "$(get .switchOpensSecond)"
        assert_eq "closePopout() from the content closes and frees it" true "$(get .closedByContent)"
        assert_eq "the pill opens it again" true "$(get .reopened)"
        assert_eq "a second click on the pill closes it" true "$(get .toggledShut)"
        assert_eq "a native panel opening closes the popout" true "$(get .panelClosesPopout)"
        assert_eq "pillClickAction runs on a click" 1 "$(get .clickActionRan)"
        assert_eq "with the widget's bar section" '"right"' "$(get .clickSection)"
        assert_eq "pillClickAction wins over the popout, as in DMS" true "$(get .clickActionWins)"
        assert_eq "a DMS network settings page opens haseen's network panel" '"haseen.network"' "$(get .settingsPage)"
        assert_eq "a page without a haseen panel opens nothing" '"haseen.network"' "$(get .unmappedPage)"
        assert_eq "Proc.runCommand hands over stdout" '"Power source   = AC"' "$(get .procOut)"
        assert_eq "and the exit code" 0 "$(get .procCode)"
        assert_eq "a plugin's pkexec reaches the stub, not the system" 97 "$(get .guardCode)"
        assert_eq "runs with one id inside the debounce collapse into one" 1 "$(grep -c run "$SANDBOX/runs.log" 2>/dev/null || echo 0)"
        assert_eq "only the last callback of a collapsed run is called" 0 "$(get .debLast)"
        assert_eq "the earlier callback is dropped" null "$(get .debFirst)"
        assert_eq "a run over its timeout reports 124" 124 "$(get .slowCode)"
        assert_eq "a command that cannot start reports 127 at once" 127 "$(get .missingCode)"
        assert_eq "no callback for a destroyed owner" null "$(get .deadOwnerCalled)"
        assert_eq "plugin state is read from its file" 41 "$(get .stateLoaded)"
        assert_eq "a missing key gives the default" '"dflt"' "$(get .stateDefault)"
        assert_eq "every state change is signalled" 2 "$(get .stateSignals)"
        assert_eq "a non-DMS id gets no state" '"refused"' "$(get .badId)"
        assert_eq "BatteryService without a battery" '[false,"power","No battery","Unknown","N/A"]' "$(get .battery)"
        assert_eq "Theme.errorHover is error at 12 %" 12 "$(get .errorHover)"
        assert_eq "DankListView lists its model and stops at its bounds" '[3,true]' "$(get .list)"
        state="$(jq -c . "$STATE/popFixture_state.json" 2>/dev/null || true)"
        assert_eq "saved state is written; a removed key is gone" 42 "$(jq -r .count <<<"$state")"
        assert_eq "removed key" null "$(jq -r .kept <<<"$state")"
        assert_eq "state saved while the widget is destroyed reaches the file" true "$(jq -r .bye <<<"$state")"
        assert_eq "no file outside the state directory" "" "$(find "$XDG_STATE_HOME" -name '*escape*')"
        assert_not_contains "no QML errors" "$OUTPUT" "TypeError"
    else
        _fail "DMS compat result not produced" "$OUTPUT"
    fi
fi
