# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Reuse the established hermetic Qt module/transport fixtures and its existing
# behavioural baseline. No live Quickshell session or installed tool is started.
source "$REPO/tests/test-vapt-security-ui.sh"
if [[ $VAPT_QML_READY != true ]]; then
    echo '  skip: Security adversarial identity/stop/certificate engine scenarios not run; baseline engine prerequisites unavailable' >&2
    return 0
fi
cat >"$H/Adversarial.qml" <<EOF
import QtQuick
import qs.Haseen
import "file://$SEC" as SecurityUI
import "file://$SEC/Model.js" as M
import "file://$MENU/MenuModel.js" as Menu
Window {
    id: win
    width: 720; height: 640; visible: true
    property int failures: 0
    property int step: 0
    SecurityUI.Panel { id: panel; anchors.fill: parent; pluginId: "haseen.security" }
    function eq(name, expected, actual) {
        if (JSON.stringify(expected) === JSON.stringify(actual)) console.warn("ATTACK-PASS " + name);
        else { failures++; console.warn("ATTACK-FAIL " + name + " expected " + JSON.stringify(expected) + " got " + JSON.stringify(actual)); }
    }
    function find(item, predicate) {
        if (predicate(item)) return item;
        if (item.children) for (const child of item.children) { const found = find(child, predicate); if (found) return found; }
        return null;
    }
    Timer { id: advance; interval: 1; onTriggered: win.run() }
    function next() { step++; advance.start(); }
    Component.onCompleted: advance.start()
    function run() {
        if (panel.refreshing || FixtureState.pending > 0) { advance.start(); return; }
        try { execute(); } catch(e) { console.warn("ATTACK-FAIL exception " + e); Qt.exit(1); }
    }
    function execute() {
        const cli = "/fixture/bin/haseen";
        if (step === 0) {
            eq("opening malicious metadata starts no action", [], Apps.launches);
            for (const bad of ["--yes", "-h", "nmap;id", "nmap\\n--yes", "nmap\\u0000", "\$(not-executed)"]) {
                const data = FixtureState.listing(); data.tools = [JSON.parse(JSON.stringify(FixtureState.tool))]; data.tools[0].id = bad;
                eq("untrusted name refused at JSON consumer " + JSON.stringify(bad), null, M.parse("tools", JSON.stringify(data)));
            }
            const t = JSON.parse(JSON.stringify(FixtureState.tool));
            t.reason = "--yes ; touch /tmp/untrusted";
            t.packages[0].version = "--yes ; touch /tmp/untrusted";
            t.desktopEntries = [{path:"/tmp/evil.desktop",name:"\$(not-executed)",terminal:false}];
            const paths = ["/usr/bin/--yes", "/usr/bin/a ; touch forbidden", "/usr/bin/a'" + String.fromCharCode(34) + "; echo forbidden", "/usr/bin/\$(not-executed)"];
            for (const path of paths) {
                t.entrypoints[0].id = path; t.entrypoints[0].path = path;
                const argv = M.toolArgv(cli,t,path,"tool-help");
                eq("hostile path is one explicit entry operand " + path,[cli,"vapt","tool-help","nmap","--entry",path],argv);
                eq("metadata never enters command/option words " + path,false,argv.some(a => a === t.reason || a === t.packages[0].version));
            }
            for (const bad of ["run", "exec", "enable", "tool-help;id", "service-start", "--yes", "constructor"]) {
                eq("tool leaf whitelist " + bad,[],M.toolArgv(cli,t,t.entrypoints[0].id,bad));
                if (bad !== "service-start") eq("service leaf whitelist " + bad,[],M.serviceArgv(cli,FixtureState.service,bad));
            }
            const draft={address:"127.0.0.1",port:"8080",path:"/tmp/a ; \$(not-executed)"};
            for (let i=0;i<FixtureState.capabilities.length;i++) {
                const c=Object.assign({},FixtureState.capabilities[i],{command:"net-remmina --yes"});
                eq("local metadata cannot select verb "+c.id,[],M.localArgv(cli,c,draft,"trust"));
            }
            for (const address of ["localhost", "example.invalid", "http://127.0.0.1", "127.0.0.1 --yes"]) eq("UI DNS/options refusal "+address,[],M.localArgv(cli,FixtureState.capabilities[0],{address:address,port:"8080"},""));
            for (const port of ["80","1023","65536","8080 --yes","-1"]) eq("UI privileged/options port refusal "+port,[],M.localArgv(cli,FixtureState.capabilities[0],{address:"127.0.0.1",port:port},""));
            const menuData=FixtureState.listing();menuData.tools[0].reason="; touch forbidden";
            const rows=Menu.securityRows("tools","setup.security.vapt.tools",M.parse("tools",JSON.stringify(menuData)));
            eq("menu metadata produces only fixed display route",Menu.SECURITY_ACTION,rows[0].action);
            const swapped=Menu.swapProviderRows({},[],"setup.security.vapt.tools",rows);
            eq("menu valid internal route resolves",{page:"tools",itemId:"nmap"},Menu.securityRoute(swapped.items[rows[0].id]));
            for (const mutation of [{action:"haseen vapt service-start ssh"},{parent:"setup.security.vapt.services"},{securityItemId:"--yes"},{securityPage:"exec"},{providerMenu:"root"}]) eq("menu forged routing refuses "+JSON.stringify(mutation),null,Menu.securityRoute(Object.assign({},swapped.items[rows[0].id],mutation)));
            panel.choosePage(2);panel.inspect("ssh");next();return;
        }
        if (step === 1) {
            const detail=find(panel,item => typeof item.requested === "function" && item.service !== undefined);
            eq("real service control rendered",true,!!detail);
            if (!detail) { Qt.exit(1);return; }
            detail.requested("service-stop",false);
            eq("stop consumer presents terminal with displayed expectations",["/fixture/bin/haseen","config","terminal","--","/fixture/bin/haseen","vapt","service-stop","ssh","--expect-unit","owned-login.service","--expect-fragment","/usr/lib/systemd/system/owned-login.service"],Apps.launches[0]);
            eq("stop skips Review and returns to service detail","service",panel.view);
            eq("launch never claims completed service operation",true,panel.notice.indexOf("completion has not been checked")>=0);
            eq("launch never auto-confirms exposure",false,Apps.launches[0].indexOf("--yes")>=0);
            panel.prepare(M.serviceArgv(cli,FixtureState.service,"service-start"),"service",false);
            const changed=JSON.parse(JSON.stringify(FixtureState.service));changed.unit="changed.service";changed.fragmentPath="/usr/lib/systemd/system/changed.service";
            panel.apply("services",panel.generation,{schemaVersion:1,services:[changed]},"");
            panel.launch();
            eq("changed displayed unit cancels outstanding launch intent",1,Apps.launches.length);
            eq("changed displayed unit clears intent",[],panel.intentArgv);
            panel.choosePage(3);panel.inspect("proxy-ca");next();return;
        }
        if (step === 2) {
            panel.draft={path:"/tmp/private.pem"};panel.inspection={schemaVersion:1,state:"refused",reason:"private key",certificate:null};
            panel.certificate("trust",false);panel.launch();
            eq("refused certificate cannot request trust",1,Apps.launches.length);
            panel.inspection={state:"valid",certificate:{isCa:true,containsPrivateKey:false,sha256:"A".repeat(64)}};
            const form=find(panel,item=>typeof item.pathChangedByUser === "function");
            eq("certificate form rendered",true,!!form);
            form.pathChangedByUser("/tmp/different.pem");
            eq("changing certificate selection invalidates inspection",null,panel.inspection);
            panel.certificate("trust",false);panel.launch();
            eq("changed certificate cannot reuse prior fingerprint",1,Apps.launches.length);
            panel.refresh();next();return;
        }
        eq("refresh reads never start actions",true,FixtureState.reads.every(a=>["menu","status","doctor","tool-list","service-list","repo-status","net-proxy-ca"].indexOf(a[2])>=0));
        eq("refresh never adds launches",1,Apps.launches.length);
        Qt.exit(failures ? 1 : 0);
    }
}
EOF
capture env QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH="$H/imports" QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML_BIN" "$H/Adversarial.qml"
rc=$STATUS
while IFS= read -r line; do
    case "$line" in *ATTACK-PASS*) _pass ;; *ATTACK-FAIL*) _fail "${line#*ATTACK-FAIL }" ;; esac
done <<<"$OUTPUT"
assert_contains 'adversarial real Qt cases execute' "$OUTPUT" 'ATTACK-PASS'
if [[ $rc != 0 && $OUTPUT != *ATTACK-FAIL* ]]; then _fail 'adversarial QML runner did not complete' "$OUTPUT"; fi
