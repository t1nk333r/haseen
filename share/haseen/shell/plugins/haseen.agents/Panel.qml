import QtQuick
import Quickshell
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
//                      start as it (`haseen agent account use`), its pencil
//                      renames it (`haseen agent account rename`), and an add
//                      row runs `haseen agent account add` in the floating
//                      terminal (plan 146): the panel's only changes of state;
//   settings.usage     the usage records omarchy-agent-usage-update keeps in
//                      haseen's state, read as files, one line per Claude
//                      account when there are several (plan 146); the panel
//                      never runs the collectors, which ask the providers
//                      (haseen-agent-usage.timer does).
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
    // The account row being renamed, "provider:id", or "".
    property string renaming: ""
    // I18n's translators for Agents.js, which stays English on its own.
    readonly property var tx: ({
            tr: (text, ...args) => I18n.tr(text, ...args),
            tn: (singular, plural, count, ...args) => I18n.tn(singular, plural, count, ...args)
        })

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

    // An add row: the CLI's add in the floating terminal, where its name
    // prompt and browser hand-off run; the panel closes, as the launcher does.
    function addAccount(provider): void {
        Apps.launch(Agents.addCommand(root.cli, provider));
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function renameAccount(row, name): void {
        root.renaming = "";
        root.forceActiveFocus();
        const argv = Agents.renameCommand(root.cli, row, name);
        if (argv.length === 0 || renameProc.running)
            return;
        renameProc.command = argv;
        renameProc.running = true;
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

    // A name typed into an account's row; then list again.
    Process {
        id: renameProc

        stdout: StdioCollector {}
        stderr: StdioCollector {}
        onExited: root.refresh()
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        Text {
            id: title

            text: I18n.tr("Agents")
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.title
            font.bold: true
        }

        Text {
            anchors.baseline: title.baseline
            width: parent.width - title.width - Theme.gap
            text: I18n.tr("%1 · r refreshes", Agents.summary(root.rows, root.tx))
            color: Theme.muted
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    Text {
        width: parent.width
        text: root.scanned ? I18n.tr("No coding agent is running.") : I18n.tr("Looking…")
        color: Theme.muted
        visible: root.rows.length === 0
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
    }

    Repeater {
        model: root.rows

        delegate: CursorSurface {
            required property var modelData

            width: root.width
            height: root.rowHeight
            hasCursor: hover.containsMouse

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
                text: Agents.duration(modelData.seconds, root.tx)
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.body
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
                font.pixelSize: Theme.font.body
                font.bold: true
            }

            Text {
                anchors.left: mark.right
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Theme.gap / 2
                text: modelData.where !== "" ? I18n.tr("%1  pid %2", modelData.where, modelData.pid) : I18n.tr("pid %1", modelData.pid)
                color: Theme.muted
                elide: Text.ElideLeft
                textFormat: Text.PlainText
                visible: root.showPaths
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.caption
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
        text: root.accounts.length > 0 ? I18n.tr("Accounts · click one to start new sessions as it") : I18n.tr("Accounts · none signed in")
        color: Theme.muted
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }

    Repeater {
        model: root.showAccounts ? Agents.section(root.accounts) : []

        delegate: CursorSurface {
            id: accountRow

            required property var modelData
            readonly property bool isAdd: modelData.kind === "add"
            readonly property bool editing: !isAdd && root.renaming === modelData.provider + ":" + modelData.id

            width: root.width
            height: Theme.fontSize * 2.2
            hasCursor: accountHover.containsMouse && !editing && (isAdd || !modelData.active)

            MouseArea {
                id: accountHover

                anchors.fill: parent
                hoverEnabled: true
                enabled: !accountRow.editing
                onClicked: accountRow.isAdd ? root.addAccount(accountRow.modelData.provider) : root.useAccount(accountRow.modelData)
            }

            Text {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.right: pencil.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                visible: !accountRow.editing
                text: accountRow.isAdd ? "+ " + I18n.tr("Add a %1 account…", accountRow.modelData.name) : (accountRow.modelData.active ? "● " : "○ ") + accountRow.modelData.name + " · " + accountRow.modelData.label + (accountRow.modelData.plan !== "" ? " · " + accountRow.modelData.plan : "") + (accountRow.modelData.signedIn ? "" : " · " + I18n.tr("signed out"))
                color: accountRow.isAdd ? Theme.muted : (accountRow.modelData.active ? Theme.accent : Theme.foreground)
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            // Rename: the pencil shows while the row is hovered, and turns
            // the label into a field. Enter renames; Escape or leaving the
            // field keeps the old name.
            Glyph {
                id: pencil

                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 1.6
                glyph: "\uf040"
                color: pencilHover.containsMouse ? Theme.accent : Theme.muted
                visible: !accountRow.isAdd && !accountRow.editing && (accountHover.containsMouse || pencilHover.containsMouse)

                MouseArea {
                    id: pencilHover

                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.renaming = accountRow.modelData.provider + ":" + accountRow.modelData.id
                }
            }

            TextInput {
                id: nameField

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                visible: accountRow.editing
                text: accountRow.modelData.label || ""
                color: Theme.foreground
                selectionColor: Theme.selection
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
                clip: true
                onVisibleChanged: if (visible) {
                    selectAll();
                    forceActiveFocus();
                }
                onAccepted: root.renameAccount(accountRow.modelData, text)
                onActiveFocusChanged: if (!activeFocus && accountRow.editing)
                    root.renaming = ""
                // Escape cancels the rename here instead of closing the panel.
                Keys.onShortcutOverride: event => event.accepted = event.key === Qt.Key_Escape
                Keys.onEscapePressed: {
                    root.renaming = "";
                    root.forceActiveFocus();
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.showUsage
        text: I18n.tr("Usage · as last collected")
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
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
                onLoaded: usageRow.line = Agents.usage(text(), root.tx, Date.now())
            }

            Text {
                width: parent.width
                text: usageRow.line ? usageRow.line.name : ""
                color: Theme.foreground
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
                font.bold: true
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: usageRow.line ? usageRow.line.detail : ""
                color: Theme.muted
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.caption
            }

            // Several accounts: one line each, the one in use first.
            Repeater {
                model: usageRow.line ? usageRow.line.accounts : []

                delegate: Text {
                    required property var modelData

                    width: usageRow.width
                    text: (modelData.active ? "● " : "○ ") + modelData.label + " · " + modelData.detail
                    color: modelData.active ? Theme.foreground : Theme.muted
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.font.caption
                }
            }
        }
    }
}
