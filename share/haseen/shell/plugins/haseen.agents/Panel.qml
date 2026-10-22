import QtQuick
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Agents.js" as Agents

// haseen.agents: the coding agents running right now — one line each with the
// directory it works in and how long it has been up. The process list is
// read-only: it starts nothing, stops nothing and changes no state. `r` takes
// a fresh snapshot, Escape closes (the panel host handles it). Open with
// `haseen shell ipc panel toggle haseen.agents`.
//
// Adapted from Omarchy shell/plugins/agents (MIT, Copyright (c) David
// Heinemeier Hansson): one panel for every coding agent on the machine.
// The panel itself asks no provider for anything: it reads /proc
// (agents-list.sh) and shows what is actually running. Two sections, both off
// by default (plan 108), follow Omarchy 4.5's panel (c05d90196, f41da937b):
//   settings.accounts  the Claude, Codex and Grok accounts (`haseen agent
//                      account list --json`); clicking one makes new sessions
//                      start as it (`haseen agent account use`), the panel's
//                      only change of state;
//   settings.usage     the usage records omarchy-agent-usage-update keeps in
//                      haseen's state, read as files; the panel never runs
//                      the collectors, which ask the providers.
//
// Nothing runs until the panel opens, and nothing polls: one scan (and one
// account list) when it opens, one more per `r`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string script: Qt.resolvedUrl("agents-list.sh").toString().replace("file://", "")
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property bool showAccounts: settings.accounts === true
    readonly property bool showUsage: settings.usage === true
    readonly property string usageDir: Paths.userState + "/agents/usage/"
    readonly property var commands: Array.isArray(settings.commands) ? settings.commands.map(c => String(c)) : []
    readonly property bool showPaths: settings.paths !== false
    readonly property int rowHeight: Theme.fontSize * (showPaths ? 3.2 : 2.2)

    property var rows: []
    property bool scanned: false
    property var accounts: []

    function refresh(): void {
        if (!scanProc.running)
            scanProc.running = true;
        if (showAccounts && !accountsProc.running)
            accountsProc.running = true;
    }

    function useAccount(row): void {
        if (useProc.running || row.active)
            return;
        useProc.command = [root.cli, "agent", "account", "use", row.provider, row.id];
        useProc.running = true;
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
        if (showAccounts)
            accountsProc.running = true;
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
                agents: root.rows.map(r => r.name + ":" + r.pid + ":" + r.project),
                accounts: root.accounts.map(a => a.provider + ":" + a.id + (a.active ? ":active" : ""))
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
        // A scanner that cannot start never exits; stop saying "Looking…".
        onRunningChanged: {
            if (!running)
                root.scanned = true;
        }
    }

    // The accounts as the CLI lists them: display fields only.
    Process {
        id: accountsProc

        command: [root.cli, "agent", "account", "list", "--json"]
        stdout: StdioCollector {
            id: accountsOut
        }
        stderr: StdioCollector {}
        onExited: code => root.accounts = code === 0 ? Agents.accounts(accountsOut.text) : []
    }

    // A click on an account: new sessions start as it; then list again.
    Process {
        id: useProc

        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: root.refresh()
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
    Text {
        width: parent.width
        visible: root.showAccounts
        text: root.accounts.length > 0 ? "Accounts · click one to start new sessions as it" : "Accounts · none signed in (haseen agent account add)"
        color: Theme.muted
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    Repeater {
        model: root.showAccounts ? root.accounts : []

        delegate: Rectangle {
            required property var modelData

            width: root.width
            height: Theme.fontSize * 2.2
            radius: Theme.radius
            color: accountHover.containsMouse && !modelData.active ? Theme.surfaceAlt : "transparent"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                text: (modelData.active ? "● " : "○ ") + modelData.name + " · " + modelData.label + (modelData.plan !== "" ? " · " + modelData.plan : "") + (modelData.signedIn ? "" : " · signed out")
                color: modelData.active ? Theme.accent : Theme.foreground
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            MouseArea {
                id: accountHover

                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.useAccount(modelData)
            }
        }
    }

    Text {
        width: parent.width
        visible: root.showUsage
        text: "Usage · as last collected"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    // One record per collector, read once when the panel opens. A record
    // that is missing or says nothing draws no line.
    Repeater {
        model: root.showUsage ? ["claude", "codex", "grok", "kimi", "fireworks"] : []

        delegate: Column {
            id: usageRow

            required property string modelData
            property var line: null

            width: root.width
            visible: line !== null

            FileView {
                path: root.usageDir + usageRow.modelData + ".json"
                printErrors: false
                onLoaded: usageRow.line = Agents.usage(text())
            }

            Text {
                width: parent.width
                text: usageRow.line ? usageRow.line.name : ""
                color: Theme.foreground
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                width: parent.width
                text: usageRow.line ? usageRow.line.detail : ""
                color: Theme.muted
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 2
            }
        }
    }
}
