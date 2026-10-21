# shellcheck shell=bash
# haseen:covers bin/haseen-vapt-menu share/haseen/default/shell.json
# haseen:covers share/haseen/layers/vapt/workflow.sh share/haseen/layers/vapt/workflow_menu.py
# haseen:covers share/haseen/shell/Haseen/** share/haseen/shell/plugins/haseen.menu/**
# haseen:covers share/haseen/shell/plugins/haseen.security/** tests/fixtures/vapt-qml-lib.sh
# Production JS and components under the real Qt engine; commands/Apps are
# replaced at the module boundary, never a live desktop or installed tool.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
SEC="$HASEEN_PATH/shell/plugins/haseen.security"
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
vapt_qml_fixture
cat >"$H/Units.qml" <<EOF
import QtQuick
import qs.Haseen
import Quickshell
import "file://$SEC" as SecurityUI
import "file://$SEC/Model.js" as M
import "file://$MENU/MenuModel.js" as Menu
import "file://$HASEEN_PATH/shell/Haseen/SecurityEvidence.js" as E
Window {
    id: win
    width: 720; height: 640; visible: true
    property int failures: 0
    property int passes: 0
    property int step: 0
    property int launchReads: 0
    property var routed: null
    SecurityUI.Panel { id: panel; anchors.fill: parent; pluginId: "haseen.security"; settings: ({placement: "overlay"}) }
    Component { id: routedPanel; SecurityUI.Panel { pluginId: "haseen.security" } }
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
            eq("signal snapshot keeps plain JSON package arrays", true, panel.snapshots.doctor.workflow.capabilities.every(c => Array.isArray(c.prerequisitePackages)));
            eq("unsupported schema refuses", null, M.parse("tools", '{"schemaVersion":2}'));
            eq("malformed JSON refuses", null, M.parse("tools", "{"));
            const duplicate = FixtureState.listing(); duplicate.tools.push(FixtureState.tool);
            eq("duplicate identities refuse", null, M.parse("tools", JSON.stringify(duplicate)));
            const hostile = JSON.parse(JSON.stringify(FixtureState.listing())); hostile.tools[0].id = "nmap;touch /tmp/unsafe";
            eq("hostile inventory identity refuses", null, M.parse("tools", JSON.stringify(hostile)));
            eq("control characters removed", "unsafe", M.text("un\\u001bsa\\u0000fe"));
            const inspected = {state:"valid",certificate:{sha256:"A".repeat(64)}};
            const pendingAnchor = {schemaVersion:1,state:"unknown",reason:"pending fixture",anchor:{sha256:"A".repeat(64),unchanged:true,transaction:"pending"}};
            const removingAnchor = {schemaVersion:1,state:"unknown",reason:"removing fixture",anchor:{sha256:"A".repeat(64),unchanged:false,transaction:"removing"}};
            eq("pending anchor schema admitted", true, !!M.parse("anchor",JSON.stringify(pendingAnchor)));
            eq("pending owned transaction permits matching trust retry", true, M.anchorTrust(pendingAnchor,inspected));
            eq("pending owned transaction permits removal", true, M.anchorRemoval(pendingAnchor));
            eq("pending trust retry refuses different fingerprint", false, M.anchorTrust(pendingAnchor,{state:"valid",certificate:{sha256:"B".repeat(64)}}));
            eq("removing absent anchor permits removal retry", true, M.anchorRemoval(removingAnchor));
            eq("removing transaction cannot trust", false, M.anchorTrust(removingAnchor,inspected));
            for (const state of ["foreign","modified","refused"]) {
                const changed = Object.assign({},pendingAnchor,{state:state});
                eq(state + " anchor refuses retry trust",false,M.anchorTrust(changed,inspected));
                eq(state + " anchor refuses removal",false,M.anchorRemoval(changed));
            }
            const malformedAnchor = JSON.parse(JSON.stringify(pendingAnchor));malformedAnchor.anchor.transaction="other";
            eq("unknown anchor transaction refuses schema",null,M.parse("anchor",JSON.stringify(malformedAnchor)));
            eq("terminal output keeps line breaks", "one\\ntwo", M.output("one\\ntwo"));
            for (let i = 0; i < 5; i++) {
                const c = FixtureState.capabilities[i];
                const d = {address: "127.0.0.1", port: "8080", path: "/fixture/a; touch not-a-command", fingerprint: "A".repeat(64)};
                const a = M.localArgv(cli, c, d, "trust");
                eq("fixed verb " + c.id, i === 4 ? [] : E.verbs[i], i === 4 ? a : a[2]);
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
            eq("hand-off refuses an unknown page", false, SecurityRoute.request("exec", "nmap"));
            eq("hand-off refuses a hostile item", false, SecurityRoute.request("tools", "--yes"));
            eq("one hand-off", true, SecurityRoute.request("tools", "nmap"));
            eq("hand-off taken", {page:"tools",itemId:"nmap"}, SecurityRoute.take());
            eq("hand-off taken once", null, SecurityRoute.take());
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
            // A read started by launch would be pending now and recorded by
            // the time the next step runs.
            eq("launch starts no read", 0, FixtureState.pending);
            launchReads = FixtureState.reads.length;
            next(); return;
        }
        if (step === 5) {
            eq("launch performs no status refresh", launchReads, FixtureState.reads.length);
            FixtureState.empty = true; panel.view = ""; panel.refresh(); next(); return;
        }
        if (step === 6) {
            eq("real empty state renders", true, rendered(panel, "No installed VAPT tools found."));
            const stale = FixtureState.listing(); stale.tools = [FixtureState.tool];
            panel.apply("tools", panel.generation - 1, stale, "");
            eq("stale generation cannot apply", 0, panel.snapshots.tools.tools.length);
            panel.choosePage(3); panel.inspect("proxy-ca");
            next(); return;
        }
        if (step === 7) {
            eq("real foreign anchor refusal renders", true, rendered(panel, "removal refused"));
            // No anchor yet, so only the inspection decides whether trust may
            // be prepared.
            panel.anchor = {schemaVersion: 1, state: "none", reason: "no anchor", anchor: null};
            panel.draft = {path: "/fixture/cert.pem"};
            const certificate = {sha256: "A".repeat(64), subject: "fixture", issuer: "fixture", notBefore: "fixture", notAfter: "fixture", isCa: true, containsPrivateKey: false};
            panel.inspection = null;
            panel.certificate("trust", false);
            eq("trust needs an inspection", [], panel.intentArgv);
            panel.inspection = {state: "invalid", reason: "expired", certificate: certificate};
            panel.certificate("trust", false);
            eq("trust needs a valid inspection", [], panel.intentArgv);
            panel.inspection = {state: "valid", reason: "fixture", certificate: certificate};
            panel.certificate("trust", false);
            eq("a valid inspection prepares trust for review", ["trust", "/fixture/cert.pem", "review"], [panel.intentArgv[3], panel.intentArgv[4], panel.view]);
            panel.back();
            eq("preparing trust launches nothing", 1, Apps.launches.length);
            win.width = 360; win.height = 480;
            panel.choosePage(0); next(); return;
        }
        if (step === 8) {
            eq("compact surface stays in viewport", true, panel.children.filter(c => c.width > 0).every(c => c.width <= panel.width));
            FixtureState.malformed = true; panel.choosePage(1); panel.refresh(); next(); return;
        }
        if (step === 9) {
            eq("malformed response clears action evidence", null, panel.snapshots.tools);
            eq("real read error renders", true, rendered(panel, "Could not read tools"));
            eq("discovery and previews have no additional launch", 1, Apps.launches.length);
            FixtureState.malformed = false; FixtureState.empty = false;
            panel.choosePage(3); panel.inspect("listener"); next(); return;
        }
        if (step === 10) {
            eq("real listener form renders", true, rendered(panel, "TCP listener"));
            eq("form has no implicit port", "", panel.draft.port);
            eq("form defaults loopback", "127.0.0.1", panel.draft.address);
            eq("opening form never reads addresses", false, FixtureState.reads.some(a => a[2] === "net-addresses"));
            eq("blank port validation", "Enter a port.", M.endpointError(panel.draft, "listener"));
            eq("hostname validation refuses", "Use a local IP address, not a hostname or URL.", M.endpointError({address:"example.invalid",port:"8080"}, "listener"));
            panel.endpoint({address:"127.0.0.1",port:"8080",path:""}, false); next(); return;
        }
        if (step === 11) {
            eq("Review waits for authoritative dry-run", "review", panel.view);
            eq("listener scope copy renders", true, rendered(panel, "Receives bytes only"));
            eq("endpoint review launches nothing", 1, Apps.launches.length);
            panel.back();
            eq("back preserves endpoint draft", "8080", panel.draft.port);
            FixtureState.previewRefused = true;
            panel.endpoint(panel.draft, false); next(); return;
        }
        if (step === 12) {
            eq("refused validation cannot reach review", "preview", panel.view);
            eq("actual refusal exit retained", 1, panel.previewCode);
            eq("real preview refusal renders", true, rendered(panel, "Refused: ownership changed"));
            eq("refusal launches nothing", 1, Apps.launches.length);
            panel.back(); FixtureState.previewRefused = false;
            panel.choosePage(3); panel.inspect("proxy-ca"); next(); return;
        }
        if (step === 13) {
            eq("real unselected certificate state renders", true, rendered(panel, "No certificate selected"));
            panel.draft = {path:"/fixture/private-key.pem"};
            const form = find(panel, i => typeof i.pathChangedByUser === "function" && typeof i.inspect === "function");
            form.inspect(panel.draft.path); next(); return;
        }
        if (step === 14) {
            eq("explicit inspection refusal renders", true, rendered(panel, "private key input refused"));
            eq("inspection itself launches nothing", 1, Apps.launches.length);
            panel.choosePage(1); panel.refresh(); next(); return;
        }
        if (step === 15) {
            panel.inspect("nmap");
            panel.entryId = FixtureState.entries[0].id; panel.view = "tool";
            panel.back();
            eq("Back to the list leaves nothing selected", ["", ""], [panel.view, panel.selectedId]);
            panel.notice = "";
            const missing = find(panel, i => i.text === "Include missing" && typeof i.toggle === "function");
            missing.click();
            eq("Include missing reads with --all", true, panel.includeMissing && FixtureState.reads.length > 0);
            next(); return;
        }
        if (step === 16) {
            eq("--all listing read", true, FixtureState.reads[FixtureState.reads.length - 1].indexOf("--all") >= 0);
            eq("records reshaped by --all are not a changed selection", "", panel.notice);
            // A tool may share the remote desktop client's id; how it launches
            // follows what was prepared, not the id.
            const data = FixtureState.listing();
            const clash = JSON.parse(JSON.stringify(FixtureState.tool));
            clash.id = "remmina"; clash.entrypoints = [FixtureState.entries[0]];
            data.tools.push(clash);
            panel.apply("tools", panel.generation, data, "");
            panel.inspect("remmina");
            eq("a tool named remmina opens its tool view", "tool", panel.view);
            next(); return;
        }
        if (step === 17) {
            const detail = find(panel, i => typeof i.requested === "function" && i.tool !== undefined);
            const before = Apps.launches.length;
            detail.requested("tool-help", false);
            eq("its documentation opens in a terminal", [cli, "config", "terminal", "--", cli, "vapt", "tool-help", "remmina"], Apps.launches[before].slice(0, 8));
            SecurityRoute.request("services", "ssh");
            routed = routedPanel.createObject(win, {width: 720, height: 640});
            next(); return;
        }
        if (step === 18) {
            eq("an opened panel takes the menu's hand-off", [2, "service", "ssh"], [routed.page, routed.view, routed.selectedId]);
            eq("the hand-off is taken once", null, SecurityRoute.pending);
            routed.destroy();
            next(); return;
        }
        if (step === 19) {
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

cat >"$H/OptIn.qml" <<EOF
import QtQuick
import qs.Haseen
import Quickshell
import "file://$SEC" as SecurityUI
Window {
    id: win
    width: 720; height: 640; visible: true
    property int index: 0
    property int failures: 0
    property var panel: null
    property var entries: [{enabled: false}, {enabled: "true"}, {enabled: null}, null, {}]
    Component { id: factory; SecurityUI.Panel { pluginId: "haseen.security"; width: win.width; height: win.height } }
    function begin() {
        Config.merged = {plugins: {"haseen.security": entries[index]}};
        FixtureState.reads = []; QsWindow.window.closes = 0;
        panel = factory.createObject(win);
        settle.start();
    }
    Timer {
        id: settle; interval: 30
        onTriggered: {
            const clean = FixtureState.pending === 0 && FixtureState.reads.length === 0 && QsWindow.window.closes === 1;
            if (clean) console.warn("OPTIN-PASS rejected entry " + JSON.stringify(win.entries[win.index]));
            else { win.failures++; console.warn("OPTIN-FAIL rejected entry " + JSON.stringify(win.entries[win.index]) + " reads " + FixtureState.reads.length + " pending " + FixtureState.pending + " closes " + QsWindow.window.closes); }
            win.panel.destroy(); win.panel = null;
            win.index++;
            if (win.index < win.entries.length) Qt.callLater(win.begin);
            else { console.warn("OPTIN-DONE no discovery without literal consent"); Qt.exit(win.failures ? 1 : 0); }
        }
    }
    Component.onCompleted: begin()
}
EOF
set +e
optin="$(QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH="$H/imports" QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 15 "$QML_BIN" "$H/OptIn.qml" 2>&1)"
rc=$?
set -e
assert_status 'Security refuses construction without literal opt-in' 0 "$rc"
assert_eq 'every disabled or malformed entry starts zero discovery' 5 "$(grep -c 'OPTIN-PASS' <<<"$optin" || true)"
assert_eq 'opt-in guard has no QML runtime errors' '' "$(grep -E 'TypeError:|ReferenceError:|Error:|Binding loop' <<<"$optin" || true)"
assert_contains 'opt-in construction scenarios complete' "$optin" 'OPTIN-DONE no discovery without literal consent'
if [[ $rc != 0 ]]; then printf '%s\n' "$optin"; fi
