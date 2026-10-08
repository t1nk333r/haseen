# shellcheck shell=bash
# Reuse the fixture boundary, but send real Qt keyboard events to production controls.
source "$REPO/tests/test-vapt-security-ui.sh"
# Render only into fixture directories; no theme activation, hooks or session access.
(
    source "$HASEEN_PATH/lib/common.sh"
    source "$HASEEN_PATH/layers/theme/theme-lib.sh"
    for palette in flexoki-light everforest; do
        mkdir -p "$H/palettes/$palette"
        cp "$HASEEN_PATH/themes/$palette/colors.toml" "$H/palettes/$palette/colors.toml"
        theme_render_templates "$H/palettes/$palette"
    done
)
PALETTES="$(jq -sc . "$H/palettes/flexoki-light/shell.json" "$H/palettes/everforest/shell.json")"
cat >"$H/Conformance.qml" <<EOF
import QtQuick
import QtTest
import qs.Haseen
import "file://$SEC" as UI
import "file://$SEC/Model.js" as M
import "file://$MENU/MenuModel.js" as Menu
import "file://$HASEEN_PATH/shell/Haseen/Ink.js" as Ink
Item {
    id: win
    width: 720; height: 640; visible: true
    readonly property var activeFocusItem: Window.window ? Window.window.activeFocusItem : null
    UI.Panel { id: panel; anchors.fill: parent; pluginId: "haseen.security" }
    function find(item, predicate) {
        if (predicate(item)) return item;
        if (item.children) for (const child of item.children) { const found = find(child, predicate); if (found) return found; }
        return null;
    }
    TestCase {
        name: "PanelConformance"
        when: windowShown
        readonly property var palettes: $PALETTES
        function applyPalette(p) {
            for (const key of ["background","surface","surfaceAlt","foreground","border","accent","selection","fontFamily","fontMono"]) Theme[key] = p[key];
        }
        function exerciseList(list, name) {
            const original = list.rows;
            list.rows = Array.from({length:12}, (_, i) => Object.assign({}, original[0], {id:name + "-" + i, label:"Wrapped choice identity " + i, reason:"Refusal reason " + i}));
            wait(0); waitForRendering(panel); list.focusIndex(0);
            keyClick(Qt.Key_Up); compare(list.current, 0);
            keyClick(Qt.Key_End); compare(list.current, 11);
            keyClick(Qt.Key_J); compare(list.current, 11);
            keyClick(Qt.Key_Home); compare(list.current, 0);
            keyClick(Qt.Key_PageDown); verify(list.current > 0 && list.current < 11, name + " page-down current=" + list.current + " viewport=" + list.viewportHeight);
            const down = list.current; keyClick(Qt.Key_PageUp); verify(list.current < down, name + " page-up");
            keyClick(Qt.Key_End); wait(0);
            const focused = win.activeFocusItem;
            const flick = find(panel, i => i.contentY !== undefined && i.contentHeight !== undefined);
            const top = focused.mapToItem(flick.contentItem,0,0).y;
            if (focused.height > flick.height) verify(Math.abs(top - flick.contentY) < 2, name + " oversized row beginning revealed");
            else verify(top >= flick.contentY - 2 && top + focused.height <= flick.contentY + flick.height + 2, name + " focused row fully revealed");
            verify(Ink.ratio(Theme.foreground, focused.background.color) >= 4.5, name + " text contrast");
            verify(Ink.ratio(focused.background.border.color, focused.background.color) >= 3, name + " focus contrast");
            compare(focused.background.border.width, 2);
            list.rows = original; wait(0);
        }
        function test_all_list_surfaces() {
            tryCompare(panel, "refreshing", false);
            win.width = 720; win.height = 640; Theme.fontSize = 11;
            for (const p of palettes) for (const size of [[360,480],[560,640],[720,640]]) for (const fontSize of [11,17]) {
                win.width = size[0]; win.height = size[1]; Theme.fontSize = fontSize;
                applyPalette(p);
                panel.choosePage(1); wait(0);
                exerciseList(find(panel, i => typeof i.focusIndex === "function"), "Tools");
                panel.choosePage(2); wait(0);
                exerciseList(find(panel, i => typeof i.focusIndex === "function"), "Services");
                panel.choosePage(1); panel.inspect("nmap"); wait(0);
                exerciseList(find(panel, i => typeof i.focusIndex === "function"), "EntryPicker");
                panel.choosePage(3); wait(0);
                exerciseList(find(panel, i => typeof i.focusIndex === "function"), "QuickActions");
                panel.inspect("enumeration-host"); wait(0);
                const form = find(panel, i => typeof i.cancelChoices === "function");
                form.addresses = [{address:"fe80::1%wlan0",interface:"wlan0",family:"ipv6",scope:"link"}];
                form.showAddresses = true; wait(0);
                exerciseList(find(form, i => i.rows && i.rows.length && i.rows[0].address === "fe80::1%wlan0"), "AddressChoices");
                form.files = ["/fixture/owned"]; form.showFiles = true; wait(0);
                exerciseList(find(form, i => i.rows && i.rows.length && i.rows[0].id === "/fixture/owned"), "FileChoices");
            }
            Theme.fontSize = 11;
        }
        function test_anchor_and_certificate_submission() {
            tryCompare(panel, "refreshing", false);
            panel.choosePage(3); panel.inspect("proxy-ca"); wait(0);
            const form = find(panel, i => typeof i.inspectPath === "function");
            panel.anchor = {schemaVersion:1,state:"owned",reason:"unchanged fixture anchor",anchor:{sha256:"B".repeat(64),unchanged:true}};
            panel.inspection = {state:"valid",reason:"fixture certificate",certificate:{sha256:"A".repeat(64),subject:"fixture",issuer:"fixture",notBefore:"fixture",notAfter:"fixture"}};
            wait(0);
            const oldFingerprint = find(form, i => i.readOnly === true && i.text === M.fingerprint("B".repeat(64)));
            const inspectedFingerprint = find(form, i => i.readOnly === true && i.text === M.fingerprint("A".repeat(64)));
            verify(!!oldFingerprint && !!inspectedFingerprint && oldFingerprint !== inspectedFingerprint);
            oldFingerprint.forceActiveFocus(); compare(oldFingerprint.background.border.width, 2);
            verify(Ink.ratio(oldFingerprint.background.border.color, oldFingerprint.background.color) >= 3);
            const launches = Apps.launches.length;
            panel.draft = {path:"/fixture/certificate.pem"};
            const file = find(form, i => i.label === "Absolute certificate path");
            file.focusInput(); keyClick(Qt.Key_Return); wait(0);
            compare(Apps.launches.length, launches);
            compare(panel.inspection.state, "refused");
            const read = FixtureState.reads[FixtureState.reads.length - 1];
            compare(read.slice(2,5), ["net-proxy-ca","inspect","/fixture/certificate.pem"]);
            verify(!!find(form, i => i.readOnly === true && i.text.indexOf("private key input refused") >= 0));
            form.requested("remove",false); wait(0);
            compare(panel.view, "review"); compare(win.activeFocusItem.text, "Cancel");
            verify(panel.intentCopy.indexOf(M.fingerprint("B".repeat(64))) >= 0);
            verify(panel.intentCopy.indexOf("Machine-wide") >= 0);
            compare(Apps.launches.length, launches);
            panel.back();
        }
        function test_contracts() {
            tryCompare(panel, "refreshing", false);
            for (const address of ["127.0.0.1", "::", "::1", "2001:db8::1", "::ffff:192.0.2.1", "fe80::1%enp3s0", "fe80::1%wlan0", "fe80::1%a_.-9"]) {
                compare(M.addressError(address), "", address);
                compare(M.localArgv("/fixture/bin/haseen", FixtureState.capabilities[0], {address:address,port:"8080"}, "")[4], address);
            }
            for (const address of ["fe80::1", "fe80::1%wlan0%lo", "fe80::1%", "fe80::1%a b", "fe80::1%" + "a".repeat(65), "999.1.1.1", "01.2.3.4", "1:2:3", "1:::2", "::g", "1:2:3:4:5:6:7:8:9", "localhost"]) verify(M.addressError(address) !== "", address);
            for (const provider of ["security-tools", "security-services", "security-local"]) {
                for (const disabled of [false, null, undefined, "true", 1]) compare(Menu.providerAllowed(provider, disabled), false);
                compare(Menu.providerAllowed(provider, true), true);
            }
            compare(Menu.providerAllowed("fonts", false), true);
            const before = panel.snapshots.tools;
            panel.apply("sources", panel.generation, null, "repo-status: fixture read refused");
            compare(panel.snapshots.tools, before);
            verify(!!find(panel, i => i.text && i.text.indexOf("repo-status: fixture read refused") >= 0));
            panel.errors = {};
        }
        function test_keyboard_and_wrapping() {
            tryCompare(panel, "refreshing", false);
            panel.choosePage(3); panel.inspect("listener"); wait(0);
            const form = find(panel, i => typeof i.cancelChoices === "function");
            verify(form !== null);
            compare(win.activeFocusItem.text, "TCP listener");
            keyClick(Qt.Key_Tab); compare(win.activeFocusItem.text, "127.0.0.1");
            keyClick(Qt.Key_Home); keyClick(Qt.Key_Right); keyClick(Qt.Key_End);
            compare(panel.view, "endpoint"); // native editing never navigates back
            keyClick(Qt.Key_Return); compare(panel.view, "endpoint");
            compare(win.activeFocusItem.text, ""); // first invalid field is blank port
            verify(!!find(form, i => i.error && i.error.indexOf("Enter a port") >= 0));
            panel.addresses = [{address:"fe80::1%wlan0",interface:"wlan0",family:"ipv6",scope:"link"}];
            form.showAddresses = true;
            const chooser = find(form, i => i.rows && i.rows.length && i.rows[0].address === "fe80::1%wlan0");
            chooser.focusIndex(0); wait(0);
            keyClick(Qt.Key_Escape); compare(form.showAddresses, false); compare(panel.view, "endpoint");
            form.showAddresses = true; wait(0); chooser.focusIndex(0); keyClick(Qt.Key_Return);
            compare(panel.draft.address, "fe80::1%wlan0"); compare(form.showAddresses, false);
            panel.choosePage(1); panel.inspect("nmap"); wait(0);
            compare(win.activeFocusItem.text, "Choose exactly one owned entrypoint");
            compare(panel.entryId, ""); keyClick(Qt.Key_Tab);
            const picker = find(panel, i => i.rows && i.rows.length === 2);
            compare(picker.current, 0); keyClick(Qt.Key_Up); compare(picker.current, 0);
            keyClick(Qt.Key_End); compare(picker.current, 1); keyClick(Qt.Key_J); compare(picker.current, 1);
            keyClick(Qt.Key_Home); compare(picker.current, 0); keyClick(Qt.Key_PageDown); compare(picker.current, 1);
            keyClick(Qt.Key_PageUp); compare(picker.current, 0); compare(panel.entryId, "");
            const retained = picker.currentId;
            picker.rows = [picker.rows[1], picker.rows[0]]; wait(0);
            compare(picker.currentId, retained); compare(picker.current, 1);
            picker.rows = [picker.rows[0]]; wait(0); compare(picker.current, 0);
            picker.rows = []; wait(0); compare(win.activeFocusItem.text, "Choose exactly one owned entrypoint");
            panel.choosePage(3); wait(0);
            const local = find(panel, i => i.rows && i.rows.length === 5);
            local.focusIndex(0); keyClick(Qt.Key_End); compare(local.current, 4);
            keyClick(Qt.Key_Down); compare(local.current, 4); keyClick(Qt.Key_Home); compare(local.current, 0);
            const nav = find(panel, i => typeof i.focusSelected === "function");
            nav.focusSelected(); keyClick(Qt.Key_Home); compare(panel.page, 0); keyClick(Qt.Key_End); compare(panel.page, 3);
            for (const size of [[360,480],[560,640],[720,640]]) {
                for (const p of palettes) {
                    applyPalette(p);
                for (const fontSize of [11,17]) {
                    win.width = size[0]; win.height = size[1]; Theme.fontSize = fontSize;
                    panel.choosePage(3); wait(0);
                    const list = find(panel, i => typeof i.focusIndex === "function");
                    list.rows = Array.from({length:12}, (_, i) => ({id:"long-"+i,label:("Long wrapped identity and refusal reason ".repeat(i === 11 ? 200 : 5))}));
                    wait(0); list.focusIndex(11); wait(0);
                    const focused = win.activeFocusItem;
                    verify(focused.height >= focused.contentItem.implicitHeight + 24 * focused.scale);
                    const flick = find(panel, i => i.contentY !== undefined && i.contentHeight !== undefined);
                    verify(!!flick);
                    const top = focused.mapToItem(flick.contentItem,0,0).y;
                    verify(Math.abs(flick.contentY - top) < 2, "oversized row reveals beginning: y=" + flick.contentY + " top=" + top + " row=" + focused.height + " viewport=" + flick.height);
                    list.focusIndex(0); wait(0);
                    const first = win.activeFocusItem;
                    const firstTop = first.mapToItem(flick.contentItem,0,0).y;
                    verify(Math.abs(flick.contentY - firstTop) < 2);
                    waitForRendering(panel);
                    const image = grabImage(panel);
                    verify(image.width > 0 && image.height > 0);
                    image.save("$H/panel-" + p.mode + "-" + size[0] + "-" + fontSize + ".png");
                    }
                }
            }
            Theme.fontSize = 11;
        }
    }
}
EOF
capture env QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=Basic QML_IMPORT_PATH="$H/imports" QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 /usr/lib/qt6/bin/qmltestrunner -input "$H/Conformance.qml"
assert_status 'real Qt keyboard and conformance runner exits' 0 "$STATUS"
assert_contains 'keyboard conformance exercised' "$OUTPUT" 'Totals: 6 passed, 0 failed'
assert_eq 'conformance has no runtime errors or unsupported accessibility attachments' '' "$(grep -E 'TypeError:|ReferenceError:|Binding loop|Accessible attached property' <<<"$OUTPUT" || true)"
