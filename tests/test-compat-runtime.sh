# shellcheck shell=bash
# Actual Quickshell engine, no windows or compositor. A legacy widget's
# companion service must start once, keep its instance when settings change,
# stop when disabled, and start fresh on re-enable. A native no-role service
# must remain available to dependency lookups throughout.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; service lifecycle scenario not run" >&2
else
    sandbox compat-runtime
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-runtime.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    mkdir -p "$HOME/.config/haseen" "$HOME/.config/omarchy/plugins/me.gauge" "$HOME/.config/haseen/plugins/me.independent"
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS

    legacy="$HOME/.config/omarchy/plugins/me.gauge"
    cat >"$legacy/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.gauge","name":"Gauge","version":"1.0.0","kinds":["bar-widget","service","overlay"],"entryPoints":{"barWidget":"Widget.qml","service":"Service.qml","overlay":"Overlay.qml"},"barWidget":{"defaults":{"mode":"default","resourceFolder":"assets","sampleBase":2}}}
JSON
    mkdir -p "$legacy/assets"
    printf '{"factor":3}\n' >"$legacy/assets/sample.json"
    printf 'import QtQuick\nItem { property var bar; property var settings; property string moduleName; implicitWidth: 12 }\n' >"$legacy/Widget.qml"
    cat >"$legacy/Service.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
Scope {
    id: backend
    property var shell
    property var settings
    property var manifest
    property real helperResult: 0
    FileView { id: helper; blockLoading: true }
    Component.onCompleted: {
        helper.path = manifest.__sourceDir + "/" + settings.resourceFolder + "/sample.json";
        helperResult = JSON.parse(helper.text()).factor * settings.sampleBase;
        console.log("LEGACY_STARTED");
    }
    Component.onDestruction: console.log("LEGACY_STOPPED")
}
QML
    cat >"$legacy/Overlay.qml" <<'QML'
import QtQuick
import Quickshell
Scope {
    property var shell
    property var settings
    property var manifest
    property bool opened: false
    property string view: ""
    function open(payload) { view = JSON.parse(payload).view; opened = true; }
    function close() { opened = false; }
    Component.onCompleted: console.log("OVERLAY_STARTED")
    Component.onDestruction: console.log("OVERLAY_STOPPED")
}
QML
    native="$HOME/.config/haseen/plugins/me.independent"
    cat >"$native/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.independent","name":"Independent","version":"1.0.0","kinds":["service"],"entry":{"service":"Service.qml"}}
JSON
    cat >"$native/Service.qml" <<'QML'
import QtQuick
import Quickshell
Scope {
    property string pluginId
    property var settings
    property var screen
    readonly property string identity: "independent"
    Component.onCompleted: console.log("NATIVE_STARTED")
    Component.onDestruction: console.log("NATIVE_STOPPED")
}
QML
    cat >"$HOME/.config/haseen/shell.json" <<'JSON'
{"bar":{"left":["me.gauge"],"center":["me.gauge"],"right":[]},"services":["me.independent"],"plugins":{"me.gauge":{"settings":{"mode":"initial"}}}}
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
ShellRoot {
    id: probe
    property int phase: 0
    property var originalService: null
    property var nativeService: null
    property var result: ({})
    Instantiator {
        model: ScriptModel { values: Plugins.serviceKeys }
        delegate: ServiceHost {}
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            const service = Compat.Runtime.serviceFor("me.gauge");
            const independent = Compat.Runtime.serviceFor("me.independent");
            const overlay = Compat.Runtime.overlayFor("me.gauge");
            if (probe.phase === 0 && Plugins.ready && service && independent && overlay) {
                probe.originalService = service;
                probe.nativeService = independent;
                probe.result.companionIds = Plugins.serviceIds.filter(id => id === "me.gauge").length;
                probe.result.helperResult = service.helperResult;
                Compat.Runtime.summon("me.gauge", JSON.stringify({view: "details"}));
                probe.result.overlayPayloadView = overlay.view;
                probe.result.overlayOpened = overlay.opened;
                probe.result.surfaceCount = Plugins.serviceKeys.filter(key => key.endsWith(":me.gauge")).length;
                Config.setRuntime(["plugins", "me.gauge", "settings", "mode"], "updated");
                Config.setRuntime(["plugins", "me.gauge", "settings", "sampleBase"], 4);
                probe.phase = 1;
            } else if (probe.phase === 1 && service && service.settings.mode === "updated" && service.settings.sampleBase === 4) {
                probe.result.sameInstanceOnSettingsChange = service === probe.originalService;
                Config.setRuntime(["plugins", "me.gauge", "enabled"], false);
                probe.phase = 2;
            } else if (probe.phase === 2 && !service && !overlay) {
                probe.result.disabledServiceRemoved = Plugins.serviceIds.indexOf("me.gauge") < 0;
                probe.result.independentPreserved = independent === probe.nativeService;
                Config.setRuntime(["plugins", "me.gauge", "enabled"], true);
                probe.phase = 3;
            } else if (probe.phase === 3 && service && overlay) {
                probe.result.reenabledResult = service.helperResult;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "service lifecycle completes in the real engine" 0 "$STATUS"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "one companion service shared by both bar sections" 1 "$(jq -r .companionIds <<<"$result")"
        assert_eq "service and overlay occupy separate lifecycle keys" 2 "$(jq -r .surfaceCount <<<"$result")"
        assert_eq "summon opens the actual overlay provider" true "$(jq -r .overlayOpened <<<"$result")"
        assert_eq "overlay receives structured summon payload" details "$(jq -r .overlayPayloadView <<<"$result")"
        assert_eq "initial settings and manifest locate the plugin's actual resource" 6 "$(jq -r .helperResult <<<"$result")"
        assert_eq "settings update keeps the live service instance" true "$(jq -r .sameInstanceOnSettingsChange <<<"$result")"
        assert_eq "disabled service no longer participates in dependency lookup" true "$(jq -r .disabledServiceRemoved <<<"$result")"
        assert_eq "unrelated native service survives disable" true "$(jq -r .independentPreserved <<<"$result")"
        assert_eq "re-enable consumes the current resource-backed configuration" 12 "$(jq -r .reenabledResult <<<"$result")"
        assert_eq "one start per lifecycle, not one per construction callback" 2 "$(grep -c 'LEGACY_STARTED' <<<"$OUTPUT")"
        assert_eq "independent native service starts once" 1 "$(grep -c 'NATIVE_STARTED' <<<"$OUTPUT")"
    else
        _fail "service lifecycle result not produced" "$OUTPUT"
    fi

    # --- standalone legacy panels ---------------------------------------------
    # A legacy `panel` entry is a loader contract, not a surface: it is built
    # with its companion service, its manifest and the registries it declares,
    # stays hidden until open(payloadJson), and brings its own window.
    sandbox compat-panel
    windowed="$HOME/.config/omarchy/plugins/me.windowed"
    inline="$HOME/.config/omarchy/plugins/me.inline"
    mkdir -p "$HOME/.config/haseen" "$windowed" "$inline" "$HOME/.config/haseen/plugins/me.native"
    cat >"$windowed/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.windowed","name":"Windowed","version":"2.1.0","kinds":["service","panel"],"entryPoints":{"service":"Service.qml","panel":"Panel.qml"}}
JSON
    cat >"$windowed/Service.qml" <<'QML'
import QtQuick
import Quickshell
Scope {
    property var shell
    property var settings
    readonly property string identity: "windowed-companion"
    Component.onCompleted: console.log("COMPANION_STARTED")
}
QML
    cat >"$windowed/Panel.qml" <<'QML'
import QtQuick
import Quickshell
Item {
    id: root
    // Injected by the panel loader before construction.
    property var shell: null
    property var manifest: null
    property var service: null
    property var pluginRegistry: null
    property bool opened: false
    property string openedWith: ""
    property string sawService: ""
    property string sawManifest: ""
    property bool sawRegistry: false
    property bool sawShell: false
    property bool visibleAtStart: true
    function open(payloadJson) { openedWith = String(payloadJson); opened = true; own.visible = true; }
    function close() { opened = false; own.visible = false; }
    // A real panel entry shell-quotes before it declares its window; the quote
    // inside this regex must not hide what follows from the host.
    function shquote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    FloatingWindow {
        id: own
        visible: false
        implicitWidth: 80
        implicitHeight: 40
    }
    Component.onCompleted: {
        sawService = service ? String(service.identity) : "";
        sawManifest = manifest ? String(manifest.version) + "|" + String(manifest.__sourceDir) : "";
        sawRegistry = !!pluginRegistry && typeof pluginRegistry.isEnabled === "function";
        sawShell = !!shell && typeof shell.serviceFor === "function";
        visibleAtStart = own.visible;
        console.log("PANEL_STARTED");
    }
    Component.onDestruction: console.log("PANEL_STOPPED")
}
QML
    cat >"$inline/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.inline","name":"Inline","version":"1.0.0","kinds":["panel"],"entryPoints":{"panel":"Panel.qml"}}
JSON
    printf 'import QtQuick\n// A body the host sizes, not a window: "PanelWindow {" in prose stays prose.\nItem { property var shell: null; implicitWidth: 24; implicitHeight: 24 }\n' >"$inline/Panel.qml"
    cat >"$HOME/.config/haseen/plugins/me.native/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.native","name":"Native","version":"1.0.0","kinds":["panel"],"entry":{"panel":"Panel.qml"}}
JSON
    printf 'import QtQuick\nItem { property string pluginId; property var settings; property var screen; implicitWidth: 10; implicitHeight: 10 }\n' \
        >"$HOME/.config/haseen/plugins/me.native/Panel.qml"
    cat >"$HOME/.config/haseen/shell.json" <<'JSON'
{"bar":{"left":[],"center":[],"right":[]},"services":["me.windowed"]}
JSON
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    for file in ServiceHost.qml PluginSlot.qml; do
        ln -s "$HASEEN_PATH/shell/$file" "$harness/$file"
    done
    # The native popup cannot exist here (layer shell needs a compositor), so
    # this probe hosts the panels the shell loads bare and reads the host's
    # own split of the two kinds.
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
ShellRoot {
    id: probe
    property var openPanels: []
    property var panelScreen: null
    property int phase: 0
    property var result: ({})
    function focusedScreen() { return null }
    function togglePanel(id) { openPanels = openPanels.indexOf(id) >= 0 ? [] : [id]; }
    function closePanel(id) { openPanels = openPanels.filter(p => p !== id); }
    Binding {
        target: Compat.Runtime
        property: "nativeShell"
        value: probe
        restoreMode: Binding.RestoreBindingOrValue
    }
    Instantiator {
        model: ScriptModel { values: Plugins.serviceKeys }
        delegate: ServiceHost {}
    }
    Instantiator {
        model: ScriptModel { values: Plugins.panelIds.filter(id => Compat.Runtime.panelSelfWindowed(id)) }
        delegate: LazyLoader {
            id: windowedPanel
            required property string modelData
            active: probe.openPanels.indexOf(modelData) >= 0
            PluginSlot {
                pluginId: windowedPanel.modelData
                kind: "panel"
                screen: probe.panelScreen
            }
        }
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            const panel = Compat.Runtime.moduleWidgets("me.windowed")[0] || null;
            if (probe.phase === 0 && Plugins.ready && Compat.Runtime.serviceFor("me.windowed")) {
                const wrapped = Plugins.panelIds.filter(id => !Compat.Runtime.panelSelfWindowed(id));
                probe.result.loadedBeforeToggle = panel !== null;
                probe.result.windowedIsSelfWindowed = Compat.Runtime.panelSelfWindowed("me.windowed");
                probe.result.inlineIsSelfWindowed = Compat.Runtime.panelSelfWindowed("me.inline");
                probe.result.nativeIsSelfWindowed = Compat.Runtime.panelSelfWindowed("me.native");
                probe.result.windowedWrapped = wrapped.indexOf("me.windowed") >= 0;
                probe.result.inlineWrapped = wrapped.indexOf("me.inline") >= 0;
                probe.result.nativeWrapped = wrapped.indexOf("me.native") >= 0;
                Compat.Runtime.toggle("me.windowed", JSON.stringify({ view: "report" }));
                probe.phase = 1;
            } else if (probe.phase === 1 && panel) {
                probe.result.sawService = panel.sawService;
                probe.result.sawManifest = panel.sawManifest;
                probe.result.sawRegistry = panel.sawRegistry;
                probe.result.sawShell = panel.sawShell;
                probe.result.visibleAtStart = panel.visibleAtStart;
                probe.result.openedWith = panel.openedWith;
                probe.result.opened = panel.opened;
                probe.result.survivesPopoutClose = Compat.Runtime.closePopout() && panel.opened;
                Compat.Runtime.toggle("me.windowed", "");
                probe.phase = 2;
            } else if (probe.phase === 2 && !panel) {
                probe.result.closedByToggle = probe.openPanels.length === 0;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "standalone panel lifecycle completes in the real engine" 0 "$STATUS"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        assert_eq "a panel is built only once it is summoned" false "$(jq -r .loadedBeforeToggle <<<"$result")"
        assert_eq "the companion service is readable at construction" windowed-companion "$(jq -r .sawService <<<"$result")"
        assert_eq "the manifest as written is readable at construction" "2.1.0|$windowed" "$(jq -r .sawManifest <<<"$result")"
        assert_eq "a panel that asks for the plugin registry gets it" true "$(jq -r .sawRegistry <<<"$result")"
        assert_eq "the shell facade is injected too" true "$(jq -r .sawShell <<<"$result")"
        assert_eq "the panel shows nothing until it is opened" false "$(jq -r .visibleAtStart <<<"$result")"
        assert_eq "the toggle payload reaches open()" '{"view":"report"}' "$(jq -r .openedWith <<<"$result")"
        assert_eq "the panel reports itself open afterwards" true "$(jq -r .opened <<<"$result")"
        assert_eq "an entry with its own window outlives the popout close path" true "$(jq -r .survivesPopoutClose <<<"$result")"
        assert_eq "an entry with its own window is not placed in the native popup" true "$(jq -r .windowedIsSelfWindowed <<<"$result")"
        assert_eq "it is absent from the popup-hosted panels" false "$(jq -r .windowedWrapped <<<"$result")"
        assert_eq "a legacy body with an implicit size keeps the native popup" false "$(jq -r .inlineIsSelfWindowed <<<"$result")"
        assert_eq "that body stays among the popup-hosted panels" true "$(jq -r .inlineWrapped <<<"$result")"
        assert_eq "a native panel keeps the native popup" false "$(jq -r .nativeIsSelfWindowed <<<"$result")"
        assert_eq "the native panel stays among the popup-hosted panels" true "$(jq -r .nativeWrapped <<<"$result")"
        assert_eq "toggling again closes and frees the panel" true "$(jq -r .closedByToggle <<<"$result")"
        assert_eq "the entry is built once per summon" 1 "$(grep -c 'PANEL_STARTED' <<<"$OUTPUT")"
        assert_eq "closing frees it again" 1 "$(grep -c 'PANEL_STOPPED' <<<"$OUTPUT")"
    else
        _fail "standalone panel result not produced" "$OUTPUT"
    fi
    # `panel toggle` on a legacy record goes through the compat lifecycle, so
    # the entry receives open(payload); instantiating it would show nothing.
    toggle_fn="$(sed -n '/function toggle(id: string): void {/,/^        }$/p' "$HASEEN_PATH/shell/shell.qml")"
    assert_contains "panel toggle opens legacy entries through the compat lifecycle" "$toggle_fn" "Compat.Runtime.toggle(key"
    assert_not_contains "legacy panel entries are not excluded from it" "$toggle_fn" 'kinds.indexOf("panel")'
fi
