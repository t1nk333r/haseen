// Adapted from Panel.qml (the popup) of the owner's fork t1nk33r.vpn
// 1.4.1-t1nk33r.1 of jkoestinger/omarchy-vpn (MIT, Copyright (c) 2026 Justin
// Köstinger); see LICENSE and UPSTREAM.md beside this file.
// haseen (plan 096): a lazily loaded haseen panel on Theme tokens over the
// haseen.vpn service; widget settings through `haseen plugin settings`.
// The fork's five-section keyboard cursor is reduced to the target list.
import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "model/Shared.js" as Shared

// The panel renders whatever the active backend exposes and knows nothing of
// any one tool: the exit address (click to copy), the master switch, a chip
// per detected tool, the details of a tunnel that is up, the tool's own
// settings (folded), and the connectable targets, filterable where the tool
// supports it. Every connect goes through the service, which takes any other
// tunnel down first. The gear lists the detected tools to hide or show.
//
// Keys: j/k or arrows move, Enter connects (or copies a copy row), / filters,
// Tab switches tool, Space flips the master switch, r reads again, Escape
// closes.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var vpn: {
        const entry = Plugins.roles.vpn;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var backend: vpn ? vpn.active : null
    property bool providersOpen: false
    property bool settingsExpanded: false
    property int rowIndex: 0
    property bool cursorActive: false
    property string copiedText: ""

    readonly property var providerRows: !vpn ? [] : vpn.detectedBackends.map(entry => {
        const hidden = vpn.isHidden(entry.backendId);
        return {
            key: "provider:" + entry.backendId,
            backendId: entry.backendId,
            label: entry.label,
            detail: hidden ? "Hidden" : (entry.connected ? "Connected" : "Shown"),
            glyph: entry.glyph,
            hidden: hidden
        };
    })
    readonly property var rows: providersOpen ? providerRows : (backend ? backend.targets : [])
    readonly property var toggles: backend && backend.toggles ? backend.toggles : []
    readonly property string installHint: {
        if (!vpn)
            return "";
        const names = [];
        for (const b of vpn.backends)
            for (const n of (b.installNames || []))
                names.push(n);
        const list = Shared.sentenceList(names);
        return list === "" ? "" : "Install " + list + " to use this panel.";
    }
    readonly property bool statusIsError: vpn !== null && (vpn.notice !== "" || (backend !== null && backend.lastError !== "" && backend.actionStatus === ""))
    readonly property string statusLine: {
        if (!vpn)
            return "The VPN service is not running: add haseen.vpn to shell.json services (haseen plugin enable haseen.vpn).";
        if (providersOpen)
            return "Tools this panel shows. Hidden ones are not read.";
        if (vpn.notice !== "")
            return vpn.notice;
        if (!backend)
            return vpn.detectedBackends.length > 0 ? "Every VPN tool is hidden. Show one again with the gear." : (vpn.setupHint !== "" ? vpn.setupHint : installHint);
        return backend.actionStatus !== "" ? backend.actionStatus : backend.lastError;
    }

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    // Applied at once and written to shell.json by the CLI; detached, so a
    // close on the same key cannot lose it.
    function setSetting(key: string, value: var): void {
        Config.setRuntime(["plugins", root.pluginId, "settings", key], value);
        const body = {};
        body[key] = value;
        Quickshell.execDetached(["sh", "-c", "printf '%s' \"$2\" | \"$1\" \"$3\" --yes >/dev/null", "sh", vpn.bin + "/haseen-plugin-settings", JSON.stringify({
                    settings: body
                }), root.pluginId]);
    }

    function move(delta: int): void {
        cursorActive = true;
        rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + delta));
    }

    function activate(row: var): void {
        if (!row || !vpn)
            return;
        if (providersOpen) {
            setSetting("hiddenBackends", Shared.joinBackendIds(Shared.toggleBackendId(vpn.hiddenBackendIds, row.backendId)));
            return;
        }
        // A row that hands over a command (NordVPN's permission fix) goes to
        // the clipboard; nothing is torn down for it.
        if (row.copy !== undefined) {
            if (vpn.copyText(row.copy)) {
                copiedText = String(row.copy);
                copiedTimer.restart();
            }
            return;
        }
        if (backend)
            vpn.connectVia(backend, row);
    }

    function stepBackend(delta: int): void {
        if (!vpn || vpn.availableBackends.length < 2 || !backend)
            return;
        const list = vpn.availableBackends;
        const i = list.indexOf(backend);
        vpn.selectBackend(list[(i + delta + list.length) % list.length].backendId);
        rowIndex = 0;
    }

    onRowsChanged: if (rowIndex >= rows.length)
        rowIndex = Math.max(0, rows.length - 1)

    width: Theme.fontSize * 28
    spacing: Theme.gap

    // Opening re-probes for tools installed since the shell started (the
    // background read does not) and asks for the exit address once if none is
    // known yet; it is otherwise fetched on connection changes only.
    Component.onCompleted: {
        if (vpn) {
            vpn.refreshAll(true);
            if (vpn.publicIp === "")
                vpn.refreshPublicIp();
        }
        keys.forceActiveFocus();
    }
    Component.onDestruction: if (backend)
        backend.filter = ""

    // haseen:ui-timeout
    Timer {
        id: copiedTimer

        interval: 1600
        onTriggered: root.copiedText = ""
    }

    Item {
        id: keys

        width: parent.width
        height: Theme.fontSize * 2.2
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            event.accepted = true;
            if (k === Qt.Key_Escape) {
                if (root.providersOpen)
                    root.providersOpen = false;
                else
                    root.close();
            } else if (k === Qt.Key_Down || t === "j") {
                root.move(1);
            } else if (k === Qt.Key_Up || t === "k") {
                root.move(-1);
            } else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                if (root.cursorActive)
                    root.activate(root.rows[root.rowIndex]);
                else
                    root.cursorActive = root.rows.length > 0;
            } else if (k === Qt.Key_Tab) {
                root.stepBackend(1);
            } else if (k === Qt.Key_Backtab) {
                root.stepBackend(-1);
            } else if (k === Qt.Key_Space && root.vpn) {
                root.vpn.toggleActive();
            } else if (t === "/" && filterBox.visible) {
                filterField.forceActiveFocus();
            } else if (t === "r" && root.vpn) {
                root.vpn.refreshAll(true);
                root.vpn.refreshPublicIp();
            } else {
                event.accepted = false;
            }
        }

        Glyph {
            id: heroGlyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: root.backend ? root.backend.glyph : Shared.GLYPH_VPN
            color: root.vpn && root.vpn.anyConnected ? Theme.accent : Theme.muted
        }

        Column {
            anchors.left: heroGlyph.right
            anchors.leftMargin: Theme.gap
            anchors.right: headerButtons.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: root.providersOpen ? "VPN tools" : root.backend ? root.backend.label : "VPN"
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.accent
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                width: parent.width
                visible: !root.providersOpen && root.vpn !== null
                text: !root.vpn ? "" : (root.backend ? root.backend.summary : "") + (root.vpn.publicIp !== "" ? "  ·  " + root.vpn.publicIp : root.vpn.ipFetching ? "  ·  …" : "")
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1

                MouseArea {
                    anchors.fill: parent
                    enabled: root.vpn !== null && root.vpn.publicIp !== ""
                    onClicked: {
                        if (root.vpn.copyText(root.vpn.publicIp)) {
                            root.copiedText = root.vpn.publicIp;
                            copiedTimer.restart();
                        }
                    }
                }
            }
        }

        Row {
            id: headerButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            height: parent.height
            spacing: 2

            BarButton {
                height: parent.height
                glyph: Shared.GLYPH_COG
                highlighted: root.providersOpen
                color: Theme.foreground
                visible: root.vpn !== null && root.vpn.detectedBackends.length > 0
                onClicked: {
                    root.providersOpen = !root.providersOpen;
                    root.rowIndex = 0;
                }
            }

            BarButton {
                height: parent.height
                visible: root.backend !== null && !root.providersOpen
                text: root.backend && root.backend.connected ? "Disconnect" : "Connect"
                highlighted: root.backend !== null && root.backend.connected
                color: root.backend && root.backend.connected ? Theme.accent : Theme.foreground
                onClicked: root.vpn.toggleActive()
            }
        }
    }

    // One chip per shown tool, when there is a choice.
    Flow {
        width: parent.width
        spacing: Theme.gap
        visible: !root.providersOpen && root.vpn !== null && root.vpn.availableBackends.length > 1

        Repeater {
            model: root.vpn ? root.vpn.availableBackends : []

            delegate: BarButton {
                required property var modelData

                height: Theme.fontSize * 2
                glyph: modelData.connected ? Shared.GLYPH_CHECK : ""
                text: modelData.label
                highlighted: modelData === root.backend
                color: Theme.foreground
                onClicked: {
                    root.vpn.selectBackend(modelData.backendId);
                    root.rowIndex = 0;
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        text: root.copiedText !== "" ? "Copied: " + root.copiedText : root.statusLine
        textFormat: Text.PlainText
        color: root.copiedText === "" && root.statusIsError ? Theme.warning : Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // The tunnel that is up.
    Repeater {
        model: !root.providersOpen && root.backend && root.backend.connected ? root.backend.details : []

        delegate: Item {
            required property var modelData

            width: root.width
            height: Theme.fontSize * 1.6

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.35
                text: parent.modelData.label
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * 0.62
                horizontalAlignment: Text.AlignRight
                text: String(parent.modelData.value)
                textFormat: Text.PlainText
                elide: Text.ElideLeft
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    // The tool's own settings, folded until asked for.
    BarButton {
        visible: !root.providersOpen && root.toggles.length > 0
        height: Theme.fontSize * 2
        glyph: root.settingsExpanded ? Shared.GLYPH_CHEVRON_UP : Shared.GLYPH_CHEVRON_DOWN
        text: (root.backend ? root.backend.label : "") + " settings"
        color: Theme.foreground
        onClicked: root.settingsExpanded = !root.settingsExpanded
    }

    Repeater {
        model: !root.providersOpen && root.settingsExpanded ? root.toggles : []

        delegate: Item {
            id: toggle

            required property var modelData

            width: root.width
            height: Theme.fontSize * 2.8

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: Theme.surfaceAlt
                visible: toggleMouse.containsMouse
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.right: toggleState.left
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: toggle.modelData.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: toggle.modelData.detail || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            Text {
                id: toggleState

                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                text: toggle.modelData.busy ? "…" : toggle.modelData.value ? "On" : "Off"
                color: toggle.modelData.value ? Theme.accent : Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            MouseArea {
                id: toggleMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: if (root.backend)
                    root.backend.setToggle(toggle.modelData.key, !toggle.modelData.value)
            }
        }
    }

    Rectangle {
        id: filterBox

        width: parent.width
        height: Theme.fontSize * 2.2
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: filterField.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth
        visible: !root.providersOpen && root.backend !== null && root.backend.supportsFilter

        TextInput {
            id: filterField

            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            clip: true
            onTextChanged: if (root.backend)
                root.backend.filter = text
            Keys.onUpPressed: root.move(-1)
            Keys.onDownPressed: root.move(1)
            Keys.onReturnPressed: {
                keys.forceActiveFocus();
                root.cursorActive = true;
                root.activate(root.rows[root.rowIndex]);
            }
            Keys.onEscapePressed: {
                text = "";
                keys.forceActiveFocus();
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: filterField.text === ""
                text: root.backend && root.backend.filterPlaceholder ? root.backend.filterPlaceholder : "Filter"
                color: Theme.muted
                font: filterField.font
            }
        }
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(contentHeight, Theme.fontSize * 22)
        visible: root.rows.length > 0
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        currentIndex: root.cursorActive ? root.rowIndex : -1
        highlightMoveDuration: 0
        onCurrentIndexChanged: if (currentIndex >= 0)
            positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: row

            required property var modelData
            required property int index
            readonly property bool current: root.cursorActive && index === root.rowIndex
            readonly property bool here: !root.providersOpen && root.backend !== null && root.backend.currentKey !== "" && modelData.key === root.backend.currentKey

            width: list.width
            height: Math.round(Theme.fontSize * 2.8)

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: row.current ? Theme.selection : Theme.surfaceAlt
                visible: row.current || rowMouse.containsMouse
            }

            Glyph {
                id: rowGlyph

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                glyph: row.modelData.glyph || ""
                color: row.here ? Theme.accent : Theme.foreground
            }

            Column {
                anchors.left: rowGlyph.right
                anchors.leftMargin: Theme.gap
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.modelData.label
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: row.here ? Theme.accent : Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: row.modelData.detail || ""
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    color: Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 1
                }
            }

            MouseArea {
                id: rowMouse

                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.rowIndex = row.index;
                    root.activate(row.modelData);
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: !root.providersOpen && root.backend !== null && root.rows.length === 0 && root.backend.emptyText !== undefined
        wrapMode: Text.WordWrap
        text: root.backend ? String(root.backend.emptyText || "") : ""
        textFormat: Text.PlainText
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        width: parent.width
        text: "j/k move · ⏎ connect · tab tool · space switch · r read again · esc close"
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
