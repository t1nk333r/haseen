# shellcheck shell=bash
# Shared by the Security UI suites: whether Qt can run them offscreen, and the
# fixture modules they run against.

vapt_qml_skip() {
    printf '  skip: %s not run; %s\n' "$1" "$2" >&2
    if [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]]; then
        assert_eq "$1: required engine prerequisite" available unavailable
    fi
}
# vapt_qml_available LABEL [RUNNER] [qml|qs] — probe only framework imports,
# never production components: a production failure must fail the suite, not
# skip it.
vapt_qml_available() {
    local label=$1 runner=${2:-} engine=${3:-qml} probe imports='' diagnostic opening='' closing='' quit='Qt.quit()'
    local -a command=()
    local -a missing=()
    QS_BIN=${QS_BIN:-/usr/bin/qs}
    QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
    if [[ $engine == qs ]]; then
        [[ -x $QS_BIN ]] || missing+=("qs ($QS_BIN)")
        command -v dbus-run-session >/dev/null || missing+=(dbus-run-session)
        command=(dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p)
        imports='import Quickshell'
        opening='ShellRoot {'
        closing='}'
        quit='Qt.callLater(Qt.quit)'
    else
        [[ -x $QML_BIN ]] || missing+=("qml ($QML_BIN)")
        command=("$QML_BIN")
    fi
    if [[ -n $runner ]]; then
        [[ -x $runner ]] || missing+=("qmltestrunner ($runner)")
        imports='import QtTest'
    fi
    if ((${#missing[@]})); then
        vapt_qml_skip "$label" "missing ${missing[*]}"
        return 1
    fi
    probe="$SANDBOX/vapt-framework-probe.qml"
    cat >"$probe" <<EOF
import QtQuick
import QtQuick.Controls
$imports
$opening
Window {
    visible: true; width: 64; height: 64
    Button { text: "Framework probe" }
    Component.onCompleted: { console.warn("VAPT-QML-READY"); $quit; }
}
$closing
EOF
    if ! diagnostic=$(QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 10 "${command[@]}" "$probe" 2>&1) || [[ $diagnostic != *VAPT-QML-READY* ]]; then
        vapt_qml_skip "$label" "QtQuick/Controls${runner:+/QtTest} offscreen prerequisite unavailable"
        printf '%s\n' "$diagnostic" >&2
        return 1
    fi
    printf '  engine: %s executing\n' "$label"
}

# vapt_qml_fixture — the modules production Security QML imports, as fixtures
# in $H/imports: Theme/Config/Paths/Apps stand-ins, the real SecurityRoute
# hand-off, and a Process that answers from FixtureState after an event-loop
# turn instead of running anything. Sets H, SEC and MENU.
# shellcheck disable=SC2034 # SEC and MENU are read by the calling suite
vapt_qml_fixture() {
    SEC="$HASEEN_PATH/shell/plugins/haseen.security"
    MENU="$HASEEN_PATH/shell/plugins/haseen.menu"
    H="$SANDBOX/qml"
    mkdir -p "$H/imports/qs/Haseen/Widgets" "$H/imports/Quickshell/Io"
    printf 'module qs.Haseen.Widgets\nGlyph 1.0 Glyph.qml\n' >"$H/imports/qs/Haseen/Widgets/qmldir"
    cp "$HASEEN_PATH/shell/Haseen/Widgets/Glyph.qml" "$H/imports/qs/Haseen/Widgets/Glyph.qml"
    cat >"$H/imports/qs/Haseen/qmldir" <<'EOF'
module qs.Haseen
singleton Theme 1.0 Theme.qml
singleton Config 1.0 Config.qml
singleton Paths 1.0 Paths.qml
singleton Apps 1.0 Apps.qml
singleton FixtureState 1.0 State.qml
singleton SecurityRoute 1.0 SecurityRoute.qml
singleton I18n 1.0 I18n.qml
EOF
    cp "$HASEEN_PATH/shell/Haseen/SecurityRoute.qml" "$HASEEN_PATH/shell/Haseen/SecurityEvidence.js" "$HASEEN_PATH/shell/Haseen/I18nPlural.js" "$H/imports/qs/Haseen/"
    # English, as the real I18n.qml is with no catalog: the key is the
    # English, filled by the real I18nPlural.js (plan 109).
    cat >"$H/imports/qs/Haseen/I18n.qml" <<'EOF'
pragma Singleton
import QtQuick
import "I18nPlural.js" as Plural
QtObject {
    property string language: "en"
    property bool rightToLeft: false
    function tr(text, ...args) { return text === undefined || text === null ? "" : Plural.fill(String(text), args); }
    function tn(singular, plural, count, ...args) { return Plural.fill(Plural.category("en", count) === "one" ? String(singular) : String(plural), [String(count)].concat(args)); }
    function mark(text) { return text; }
    function formatNumber(value, decimals) { return Plural.formatNumber(value, decimals, ".", "0"); }
    function formatDate(date, format) { return date ? date.toLocaleString(Qt.locale("en_US"), format) : ""; }
    function menuEntry(id) { return ({}); }
}
EOF
    cat >"$H/imports/qs/Haseen/Theme.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property color background: "#151515"
    property color surface: "#202020"
    property color surfaceAlt: "#303030"
    property color foreground: "#ffffff"
    property color border: "#777777"
    property color accent: "#aaddff"
    property color selection: "#454545"
    property int gap: 6
    property int radius: 6
    property int borderWidth: 1
    property int fontSize: 11
    property string fontFamily: "sans-serif"
    property string fontMono: "monospace"
    // The real Theme's type scale (Theme.qml), from fontSize: the tests
    // change fontSize and expect the panel to reflow.
    readonly property real fontScale: Math.max(1 / 12, fontSize / 12)
    function px(mult) { return Math.max(1, Math.round(fontSize * mult)); }
    readonly property QtObject font: QtObject {
        readonly property int caption: px(0.833)
        readonly property int bodySmall: px(0.917)
        readonly property int body: px(1.0)
        readonly property int subtitle: px(1.083)
        readonly property int title: px(1.167)
        readonly property int heading: px(1.333)
        readonly property int display: px(2.0)
        readonly property int displayLarge: px(2.333)
        readonly property int iconSmall: bodySmall
        readonly property int icon: title
        readonly property int iconLarge: px(1.5)
    }
}
EOF
    cat >"$H/imports/qs/Haseen/Config.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property var merged: ({plugins: {"haseen.security": {enabled: true}}})
    property bool frameEnabled: false
    property int frameThickness: 0
    property bool barVertical: false
    property string barPosition: "top"
    property int barThickness: 0
    function pluginEntry(id) { return merged.plugins[id] || {}; }
}
EOF
    cat >"$H/imports/qs/Haseen/Paths.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject { property string haseenPath: "/fixture/share/haseen" }
EOF
    cat >"$H/imports/qs/Haseen/Apps.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property var launches: []
    function launch(argv, options) { launches = launches.concat([argv]); }
}
EOF
    cat >"$H/imports/Quickshell/qmldir" <<'EOF'
module Quickshell
singleton QsWindow 1.0 QsWindow.qml
EOF
    cat >"$H/imports/Quickshell/QsWindow.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject { property QtObject window: QtObject { property int closes: 0; function closeRequested() { closes++; } } }
EOF
    cat >"$H/imports/Quickshell/Io/qmldir" <<'EOF'
module Quickshell.Io
Process 1.0 Process.qml
StdioCollector 1.0 StdioCollector.qml
EOF
    cat >"$H/imports/Quickshell/Io/StdioCollector.qml" <<'EOF'
import QtQuick
QtObject { property string text: "" }
EOF
    cat >"$H/imports/Quickshell/Io/Process.qml" <<'EOF'
import QtQuick
import qs.Haseen
QtObject {
    id: root
    property bool running: false
    property var command: []
    property QtObject stdout
    property QtObject stderr
    signal exited(int code, int status)
    // Deliberately cross an event-loop boundary: tests must await responses,
    // not assume one callLater or one layout pass completes every read.
    property Timer reply: Timer { interval: 7; onTriggered: root.completeRead() }
    onRunningChanged: if (running) {
        FixtureState.pending++;
        reply.start();
    }
    function completeRead() {
        const r = FixtureState.read(root.command);
        if (root.stdout) root.stdout.text = r.text;
        if (root.stderr) root.stderr.text = r.error || "";
        root.running = false;
        root.exited(r.code || 0, 0);
        FixtureState.pending--;
    }
}
EOF
    cat >"$H/imports/qs/Haseen/State.qml" <<'EOF'
pragma Singleton
import QtQuick
QtObject {
    property var reads: []
    property int pending: 0
    property bool empty: false
    property bool malformed: false
    property bool previewRefused: false
    property var entries: [
        {id: "/usr/bin/nmap", path: "/usr/bin/nmap", kind: "executable", documentation: [{path: "/usr/share/man/man1/nmap.1", kind: "man"}], usage: {state: "ready", kind: "man", reason: "owned documentation"}},
        {id: "/usr/bin/ncat", path: "/usr/bin/ncat", kind: "executable", documentation: [], usage: {state: "unavailable", kind: null, reason: "ambiguous documentation"}}
    ]
    property var tool: ({id: "nmap", groups: ["core", "network"], state: "installed", reason: "owned installed evidence", dataOnly: false, packages: [{name: "nmap", version: "1", source: ["extra"], provenance: "verified", files: ["/usr/bin/nmap"]}], entrypoints: entries, desktopEntries: [], native: null})
    property var service: ({id: "ssh", installed: true, package: "openssh", ownership: "verified", unit: "owned-login.service", fragmentPath: "/usr/lib/systemd/system/owned-login.service", state: "running", activeState: "active", subState: "running", exposure: "unknown", reason: "owned unit"})
    property var capabilities: [
        {id: "listener", command: "net-listener", installed: true, available: true, state: "available", prerequisitePackages: ["openbsd-netcat"], reason: "owned adapter"},
        {id: "http-server", command: "net-http-server", installed: true, available: true, state: "available", prerequisitePackages: ["python"], reason: "owned adapter"},
        {id: "enumeration-host", command: "net-file-server", installed: true, available: false, state: "selection-required", prerequisitePackages: ["python"], reason: "choose an owned file"},
        {id: "proxy-ca", command: "net-proxy-ca", installed: true, available: false, state: "selection-required", prerequisitePackages: ["openssl"], reason: "choose certificate"},
        {id: "remmina", command: "net-remmina", installed: false, available: false, state: "missing", prerequisitePackages: ["remmina"], reason: "missing client"}
    ]
    function listing() { return {schemaVersion: 1, tools: empty ? [] : [tool], sources: [{name: "extra", state: "safe", cachedPackages: 1}], privateSource: {name: "oniomarchy", state: "unverified", reason: "source signature unavailable"}}; }
    function doctor() {
        const d = listing();
        d.provisioning = {state: "missing", exitCode: 1, diagnostics: ["Missing provisioning state"]};
        d.workflow = {settings: {schemaVersion: 1, bindAddress: "127.0.0.1", enumerationScript: null, showLocalAddresses: false}, menu: {schemaVersion: 1, plugin: "haseen.security", enabled: true}, entrypoints: 2, documentationReady: 1, capabilities: capabilities};
        return d;
    }
    function read(argv) {
        reads = reads.concat([argv]);
        if (argv.indexOf("--dry-run") >= 0) return {text: previewRefused ? "Refused: ownership changed" : "DRYRUN: selected intent only", code: previewRefused ? 1 : 0};
        const verb = argv[2];
        if (malformed && verb === "tool-list") return {text: "not JSON", code: 1};
        let d;
        if (verb === "menu") d = {schemaVersion: 1, plugin: "haseen.security", enabled: true};
        else if (verb === "tool-list") {
            // As the CLI does, --all adds a recorded resolution to every tool.
            d = listing();
            if (argv.indexOf("--all") >= 0) d.tools.forEach(t => t.resolution = {state: "resolved", source: "extra", target: t.id, reason: "recorded"});
        }
        else if (verb === "status" || verb === "doctor") return {text: JSON.stringify(doctor()), code: 1};
        else if (verb === "service-list") d = {schemaVersion: 1, services: empty ? [] : [service]};
        else if (verb === "repo-status") d = {schemaVersion: 1, repositories: [{name: "oniomarchy", state: "unverified", reason: "Source unverified", databaseSignatureState: "missing", keyringAuthorityState: "unknown"}]};
        else if (verb === "net-addresses") d = {schemaVersion: 1, addresses: []};
        else if (verb === "net-proxy-ca" && argv[3] === "status") d = {schemaVersion: 1, state: "foreign", reason: "not owned", anchor: null};
        else if (verb === "net-proxy-ca" && argv[3] === "inspect") d = {schemaVersion: 1, state: "refused", reason: "private key input refused", certificate: null};
        else return {text: "", error: "ACTION ATTEMPTED DURING DISCOVERY", code: 1};
        return {text: JSON.stringify(d), code: 0};
    }
}
EOF
}
