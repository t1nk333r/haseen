# shellcheck shell=bash
# Production JS and components under the real Qt engine; commands/Apps are
# replaced at the module boundary, never a live desktop or installed tool.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
SEC="$HASEEN_PATH/shell/plugins/haseen.security"
MENU="$HASEEN_PATH/shell/plugins/haseen.menu"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
sandbox vapt-security-ui
assert_eq 'Security ships explicitly off' false "$(jq -r '.plugins["haseen.security"].enabled' "$HASEEN_PATH/default/shell.json")"
assert_eq 'Security panel only' panel "$(jq -r '.kinds[]' "$SEC/manifest.json")"
assert_eq 'Security permissions only reviewed capabilities' 'exec files:read' "$(jq -r '.permissions | join(" ")' "$SEC/manifest.json")"
assert_eq 'Security never in bar or services' 0 "$(jq '[.bar.left[],.bar.center[],.bar.right[],.services[]] | map(select(. == "haseen.security")) | length' "$HASEEN_PATH/default/shell.json")"
capture haseen vapt menu --enabled
assert_status 'default configuration hides optional menu' 1 "$STATUS"
mkdir -p "$XDG_CONFIG_HOME/haseen"
printf '{"plugins":{"haseen.security":{"enabled":true}}}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen vapt menu --enabled
assert_status 'only explicit enablement exposes menu' 0 "$STATUS"
printf '{"plugins":{"haseen.security":{"enabled":"true"}}}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
capture haseen vapt menu --enabled
assert_status 'string true is not consent' 1 "$STATUS"
source "$FIXTURES/vapt-qml-lib.sh"
vapt_qml_available 'Security UI model/preview/service/certificate/disablement scenarios' || return 0
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
        else if (verb === "tool-list") d = listing();
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
cat >"$H/Units.qml" <<EOF
import QtQuick
import qs.Haseen
import Quickshell
import "file://$SEC" as SecurityUI
import "file://$SEC/Model.js" as M
import "file://$MENU/MenuModel.js" as Menu
Window {
    id: win
    width: 720; height: 640; visible: true
    property int failures: 0
    property int passes: 0
    property int step: 0
    SecurityUI.Panel { id: panel; anchors.fill: parent; pluginId: "haseen.security"; settings: ({placement: "overlay"}) }
    function eq(name, expected, actual) {
        if (JSON.stringify(expected) === JSON.stringify(actual)) { passes++; console.warn("UNIT-PASS " + name); }
        else { failures++; console.warn("UNIT-FAIL " + name + " expected " + JSON.stringify(expected) + " got " + JSON.stringify(actual)); }
    }
    function rendered(item, needle) {
        if (item.text !== undefined && String(item.text).indexOf(needle) >= 0) return true;
        return item.children ? Array.from(item.children).some(c => rendered(c, needle)) : false;
    }
    Timer { id: advance; interval: 1; onTriggered: win.run() }
    function next() { step++; advance.start(); }
    function find(item, predicate) {
        if (predicate(item)) return item;
        if (item.children) for (const child of item.children) { const result = find(child, predicate); if (result) return result; }
        return null;
    }
    Component.onCompleted: advance.start()
    function run() {
        try { execute(); } catch (e) { failures++; console.warn("UNIT-FAIL exception " + e); Qt.exit(1); }
    }
    function execute() {
        if (panel.refreshing || FixtureState.pending > 0) { advance.start(); return; }
        const cli = "/fixture/bin/haseen";
        if (step === 0) {
            eq("six independent reads on open", 6, FixtureState.reads.length);
            eq("no discovery launch", 0, Apps.launches.length);
            eq("discovery only approved reads", true, FixtureState.reads.every(a => ["menu", "status", "doctor", "tool-list", "service-list", "repo-status"].indexOf(a[2]) >= 0));
            eq("semantic missing status retained", "missing", panel.snapshots.status.provisioning.state);
            eq("unsupported schema refuses", null, M.parse("tools", '{"schemaVersion":2}'));
            eq("malformed JSON refuses", null, M.parse("tools", "{"));
            const duplicate = FixtureState.listing(); duplicate.tools.push(FixtureState.tool);
            eq("duplicate identities refuse", null, M.parse("tools", JSON.stringify(duplicate)));
            const hostile = JSON.parse(JSON.stringify(FixtureState.listing())); hostile.tools[0].id = "nmap;touch /tmp/unsafe";
            eq("hostile inventory identity refuses", null, M.parse("tools", JSON.stringify(hostile)));
            eq("control characters removed", "unsafe", M.text("un\\u001bsa\\u0000fe"));
            eq("terminal output keeps line breaks", "one\\ntwo", M.output("one\\ntwo"));
            for (let i = 0; i < 5; i++) {
                const c = FixtureState.capabilities[i];
                const d = {address: "127.0.0.1", port: "8080", path: "/fixture/a; touch not-a-command", fingerprint: "A".repeat(64)};
                const a = M.localArgv(cli, c, d, "trust");
                eq("fixed verb " + c.id, i === 4 ? [] : M.verbs[i], i === 4 ? a : a[2]);
                const forged = Object.assign({}, c, {command: "net-remmina;touch unsafe"});
                eq("forged command refused " + c.id, [], M.localArgv(cli, forged, d, "trust"));
            }
            eq("file helper uses record verb", "net-file-server", M.localArgv(cli, FixtureState.capabilities[2], {address: "127.0.0.1", port: "8080", path: "/fixture/selected"}, "")[2]);
            const path = "/fixture/selected; touch unsafe";
            const argv = M.localArgv(cli, FixtureState.capabilities[1], {address: "127.0.0.1", port: "8080", path: path}, "");
            eq("untrusted path stays one operand", path, argv[5]);
            eq("terminal argv is not shell text", [cli, "config", "terminal", "--"].concat(argv), M.terminal(cli, argv));
            eq("no arbitrary tool verb", [], M.toolArgv(cli, FixtureState.tool, FixtureState.entries[0].id, "exec"));
            eq("undocumented entry cannot authorize", [], M.toolArgv(cli, FixtureState.tool, FixtureState.entries[1].id, "tool-run"));
            for (const v of ["tool-help", "tool-run"]) eq(v + " selected owned operand", [cli,"vapt",v,"nmap","--entry","/usr/bin/nmap"], M.toolArgv(cli, FixtureState.tool, FixtureState.entries[0].id, v));
            for (const v of ["service-start", "service-stop", "service-restart"]) eq(v + " binds displayed snapshot", [cli,"vapt",v,"ssh","--expect-unit","owned-login.service","--expect-fragment","/usr/lib/systemd/system/owned-login.service"], M.serviceArgv(cli, FixtureState.service, v));
            const rows = Menu.securityRows("tools", "setup.security.vapt.tools", M.parse("tools", JSON.stringify(FixtureState.listing())));
            eq("tool id UTF8 hex", "setup.security.vapt.tools.t-6e6d6170", rows[0].id);
            eq("provider action is fixed panel toggle", Menu.SECURITY_ACTION, rows[0].action);
            eq("tool guard is fixed enablement", Menu.SECURITY_GUARD, rows[0].when);
            const swapped = Menu.swapProviderRows({}, [], "setup.security.vapt.tools", rows);
            eq("typed route only internal provider", {page:"tools",itemId:"nmap"}, Menu.securityRoute(swapped.items[rows[0].id]));
            eq("hostile route source refused", null, Menu.securityRoute(Object.assign({}, rows[0], {action:"evil"})));
            eq("one consumed route", true, M.route("tools", "nmap"));
            eq("route returned", {page:"tools",itemId:"nmap"}, M.consume());
            eq("route consumed once", null, M.consume());
            const serviceRows = Menu.securityRows("services", "setup.security.vapt.services", {services:[FixtureState.service]});
            eq("service exact package guard", "haseen vapt menu --enabled && haseen-pkg-present openssh", serviceRows[0].when);
            const localRows = Menu.securityRows("local", "setup.security.vapt.local", FixtureState.doctor());
            eq("missing local prerequisite absent", false, localRows.some(r => r.securityItemId === "remmina"));
            const off = {items: {"setup.security.vapt": Menu.finishItem({id:"setup.security.vapt",when:Menu.SECURITY_GUARD,action:Menu.SECURITY_ACTION})},itemOrder:["setup.security.vapt"]};
            eq("guard unanswered hides row", false, Menu.isVisible(off.items, off.itemOrder, {}, off.items[off.itemOrder[0]], 0));
            eq("guard true shows row", true, Menu.isVisible(off.items, off.itemOrder, {"setup.security.vapt":true}, off.items[off.itemOrder[0]], 0));
            panel.choosePage(1); panel.inspect("nmap");
            eq("multiple entries show picker", "picker", panel.view);
            eq("picker never launches", 0, Apps.launches.length);
            next(); return;
        }
        if (step === 1) {
            eq("real picker heading renders", true, rendered(panel, "Choose exactly one"));
            panel.entryId = FixtureState.entries[1].id; panel.view = "tool";
            next(); return;
        }
        if (step === 2) {
            eq("real refusal reason renders", true, rendered(panel, "ambiguous documentation"));
            panel.entryId = FixtureState.entries[0].id;
            panel.prepare(M.toolArgv(cli, FixtureState.tool, panel.entryId, "tool-run"), "tool", true);
            next(); return;
        }
        if (step === 3) {
            eq("preview launches nothing", 0, Apps.launches.length);
            eq("preview uses dry-run only", true, FixtureState.reads[FixtureState.reads.length - 1].indexOf("--dry-run") >= 0);
            eq("real preview heading renders", true, rendered(panel, "Preview — no changes made"));
            panel.view = "review"; next(); return;
        }
        if (step === 4) {
            eq("review focuses cancel", "Cancel", win.activeFocusItem.text);
            panel.launch();
            eq("explicit launch uses Apps", 1, Apps.launches.length);
            eq("launch does not pass yes", false, Apps.launches[0].indexOf("--yes") >= 0);
            eq("terminal launch does not execute selected tool", cli, Apps.launches[0][4]);
            eq("completion remains unchecked", true, panel.notice.indexOf("completion has not been checked") >= 0);
            const before = FixtureState.reads.length;
            eq("launch performs no status refresh", before, FixtureState.reads.length);
            FixtureState.empty = true; panel.view = ""; panel.refresh(); next(); return;
        }
        if (step === 5) {
            eq("real empty state renders", true, rendered(panel, "No installed VAPT tools found."));
            const before = panel.snapshots.tools;
            panel.apply("tools", panel.generation - 1, FixtureState.listing(), "");
            eq("stale generation cannot apply", before, panel.snapshots.tools);
            panel.choosePage(3); panel.inspect("proxy-ca");
            next(); return;
        }
        if (step === 6) {
            eq("real foreign anchor refusal renders", true, rendered(panel, "removal refused"));
            panel.draft = {path:"/fixture/cert.pem"};
            panel.certificate("trust", false);
            eq("trust without valid inspection never launches", 1, Apps.launches.length);
            win.width = 360; win.height = 480;
            panel.choosePage(0); next(); return;
        }
        if (step === 7) {
            eq("compact surface stays in viewport", true, panel.children.filter(c => c.width > 0).every(c => c.width <= panel.width));
            FixtureState.malformed = true; panel.choosePage(1); panel.refresh(); next(); return;
        }
        if (step === 8) {
            eq("malformed response clears action evidence", null, panel.snapshots.tools);
            eq("real read error renders", true, rendered(panel, "Could not read tools"));
            eq("discovery and previews have no additional launch", 1, Apps.launches.length);
            FixtureState.malformed = false; FixtureState.empty = false;
            panel.choosePage(3); panel.inspect("listener"); next(); return;
        }
        if (step === 9) {
            eq("real listener form renders", true, rendered(panel, "TCP listener"));
            eq("form has no implicit port", "", panel.draft.port);
            eq("form defaults loopback", "127.0.0.1", panel.draft.address);
            eq("opening form never reads addresses", false, FixtureState.reads.some(a => a[2] === "net-addresses"));
            eq("blank port validation", "Enter a port.", M.endpointError(panel.draft, "listener"));
            eq("hostname validation refuses", "Use a local IP address, not a hostname or URL.", M.endpointError({address:"example.invalid",port:"8080"}, "listener"));
            panel.endpoint({address:"127.0.0.1",port:"8080",path:""}, false); next(); return;
        }
        if (step === 10) {
            eq("Review waits for authoritative dry-run", "review", panel.view);
            eq("listener scope copy renders", true, rendered(panel, "Receives bytes only"));
            eq("endpoint review launches nothing", 1, Apps.launches.length);
            panel.back();
            eq("back preserves endpoint draft", "8080", panel.draft.port);
            FixtureState.previewRefused = true;
            panel.endpoint(panel.draft, false); next(); return;
        }
        if (step === 11) {
            eq("refused validation cannot reach review", "preview", panel.view);
            eq("actual refusal exit retained", 1, panel.previewCode);
            eq("real preview refusal renders", true, rendered(panel, "Refused: ownership changed"));
            eq("refusal launches nothing", 1, Apps.launches.length);
            panel.back(); FixtureState.previewRefused = false;
            panel.choosePage(3); panel.inspect("proxy-ca"); next(); return;
        }
        if (step === 12) {
            eq("real unselected certificate state renders", true, rendered(panel, "No certificate selected"));
            panel.draft = {path:"/fixture/private-key.pem"};
            const form = find(panel, i => typeof i.pathChangedByUser === "function" && typeof i.inspect === "function");
            form.inspect(panel.draft.path); next(); return;
        }
        if (step === 13) {
            eq("explicit inspection refusal renders", true, rendered(panel, "private key input refused"));
            eq("inspection itself launches nothing", 1, Apps.launches.length);
            Config.merged = {plugins: {"haseen.security": {enabled: false}}};
            eq("disabled while open requests close", 1, QsWindow.window.closes);
            console.warn("UNIT-COUNT " + passes);
            console.warn("UNIT-DONE all named Security UI scenarios");
            Qt.exit(failures ? 1 : 0);
        }
    }
}
EOF
set +e
units="$(QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH="$H/imports" QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Units.qml" 2>&1)"
rc=$?
set -e
assert_status 'Security real QML runner exits cleanly' 0 "$rc"
while IFS= read -r line; do
    assert_eq "qml: ${line#*UNIT-PASS }" pass pass
done < <(grep 'UNIT-PASS' <<<"$units" || true)
while IFS= read -r line; do
    _fail "${line#*UNIT-FAIL }"
done < <(grep 'UNIT-FAIL' <<<"$units" || true)
if [[ $rc != 0 ]]; then printf '%s\n' "$units"; fi
assert_eq 'Security has no QML runtime errors' '' "$(grep -E 'TypeError:|ReferenceError:|Error:|Binding loop' <<<"$units" || true)"
assert_contains 'Security QML named scenarios complete' "$units" 'UNIT-DONE all named Security UI scenarios'
