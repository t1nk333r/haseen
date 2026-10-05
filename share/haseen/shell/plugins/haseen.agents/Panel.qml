import QtQuick
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Agents.js" as Agents

// haseen.agents: the coding agents running right now — one line each with the
// directory it works in and how long it has been up. Read-only: it starts
// nothing, stops nothing and changes no state. `r` takes a fresh snapshot,
// Escape closes (the panel host handles it). Open with
// `haseen shell ipc panel toggle haseen.agents`.
//
// Adapted from Omarchy shell/plugins/agents (MIT, Copyright (c) David
// Heinemeier Hansson): one panel for every coding agent on the machine.
// Upstream draws rate limits and token counts out of the usage records
// `omarchy-agent-usage-update` collects per subscription; haseen ships no
// collectors and asks no provider for anything, so this panel reads /proc
// (agents-list.sh) and shows what is actually running.
//
// Nothing runs until the panel opens, and nothing polls: one scan when it
// opens, one more per `r`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string script: Qt.resolvedUrl("agents-list.sh").toString().replace("file://", "")
    readonly property var commands: Array.isArray(settings.commands) ? settings.commands.map(c => String(c)) : []
    readonly property bool showPaths: settings.paths !== false
    readonly property int rowHeight: Theme.fontSize * (showPaths ? 3.2 : 2.2)

    property var rows: []
    property bool scanned: false

    function refresh(): void {
        if (!scanProc.running)
            scanProc.running = true;
    }

    width: Theme.fontSize * 26
    spacing: Theme.gap
    focus: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_R) {
            root.refresh();
            event.accepted = true;
        }
    }

    Component.onCompleted: {
        scanProc.running = true;
        forceActiveFocus();
    }

    // Test hook (settings.debugIpc): read the open panel over IPC, so a smoke
    // test never injects keys into the session.
    IpcHandler {
        target: "haseen.agents"
        enabled: root.settings.debugIpc === true

        function refresh(): void {
            root.refresh();
        }

        function state(): string {
            return JSON.stringify({
                scanned: root.scanned,
                count: root.rows.length,
                agents: root.rows.map(r => r.name + ":" + r.pid + ":" + r.project)
            });
        }
    }

    // One snapshot of /proc. The script is read-only and prints TSV; a
    // failure leaves the list empty rather than guessing.
    Process {
        id: scanProc

        command: [root.script].concat(root.commands)
        stdout: StdioCollector {
            id: scanOut
        }
        stderr: StdioCollector {}
        onExited: code => {
            root.rows = code === 0 ? Agents.parse(scanOut.text, Paths.home) : [];
            root.scanned = true;
        }
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: "Agents"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: Agents.summary(root.rows) + " · r refreshes"
            color: Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: parent.width
        text: root.scanned ? "No coding agent is running." : "Looking…"
        color: Theme.muted
        visible: root.rows.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: root.rows

        delegate: Rectangle {
            required property var modelData

            width: root.width
            height: root.rowHeight
            radius: Theme.radius
            color: hover.containsMouse ? Theme.surfaceAlt : "transparent"

            Glyph {
                id: mark

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap / 2
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 2
                glyph: "\uf120"
                color: Theme.accent
            }

            Text {
                id: age

                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.top: parent.top
                anchors.topMargin: Theme.gap / 2
                text: Agents.duration(modelData.seconds)
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.left: mark.right
                anchors.right: age.left
                anchors.rightMargin: Theme.gap
                anchors.top: parent.top
                anchors.topMargin: Theme.gap / 2
                text: modelData.project !== "" ? modelData.name + " · " + modelData.project : modelData.name
                color: Theme.foreground
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.left: mark.right
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.gap / 2
                text: modelData.where !== "" ? modelData.where + "  pid " + modelData.pid : "pid " + modelData.pid
                color: Theme.muted
                elide: Text.ElideLeft
                textFormat: Text.PlainText
                visible: root.showPaths
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 2
            }

            MouseArea {
                id: hover

                anchors.fill: parent
                hoverEnabled: true
            }
        }
    }
}
