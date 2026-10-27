import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The Todoist panel: the header with the counts, quick add, the Today / Inbox
// / All tabs, the task list (complete, edit, delete, open on todoist.com) and
// Settings (token, custom filter, bar count, panel size). State and requests
// are the haseen.todoist service's (role `todoist`); this item exists only
// while the panel is open. Open it with `haseen shell ipc panel toggle
// haseen.todoist` or a click on the bar mark.
//
// Keys (when no field has focus): j/k or arrows move, Space completes, Enter
// opens the task, e edits it, x deletes it (Enter or y confirms, n cancels),
// q goes to quick add, t/i/a or Tab/Shift+Tab pick the tab, r refreshes,
// p opens Settings, ? the key list. Escape closes the panel (the host's).
//
// Adapted from Panel.qml in omarchy-todoist (MIT, Copyright (c) 2026
// aryan-techie), as the owner's fork t1nk33r.todoist 1.14.0; see LICENSE and
// UPSTREAM.md beside this file. haseen changes: Theme tokens and Pill buttons
// instead of qs.Ui; state in the service; a fixed card the host places; the
// keyboard-shortcut recorder, the rotating header phrases and the Settings
// Tab focus chain are gone; Escape always closes (it backed out of an edit
// or Settings first).
FocusScope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.todoist;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property bool ready: service !== null
    readonly property var tasks: ready ? service.tasks : []
    readonly property bool hasToken: ready && service.hasToken

    property bool settingsView: false
    property bool helpOpen: false
    property int selectedIndex: -1
    property bool cursorActive: false
    property int editingIndex: -1
    property string pendingDeleteId: ""
    property string pendingDeleteContent: ""

    readonly property var viewOrder: ["today", "inbox", "all"]
    readonly property string viewLabel: !ready ? "" : service.quickView === "inbox" ? I18n.tr("INBOX") : service.quickView === "all" ? I18n.tr("ALL TASKS") : service.quickView === "custom" ? I18n.tr("CUSTOM FILTER") : I18n.tr("TODAY & OVERDUE")
    readonly property string emptyMessage: !ready ? "" : service.quickView === "inbox" ? I18n.tr("Inbox is empty.") : service.quickView === "all" ? I18n.tr("No tasks yet.") : service.quickView === "custom" ? I18n.tr("No tasks match this filter.") : I18n.tr("Nothing due. You're clear.")
    readonly property string headerMeta: !ready ? "" : !hasToken ? I18n.tr("NOT CONNECTED") : settingsView ? I18n.tr("SETTINGS") : service.tokenInvalid ? I18n.tr("TOKEN REJECTED") : service.loading && tasks.length === 0 ? I18n.tr("LOADING…") : viewLabel
    // The VIEW stat: the tab's short name, as the tabs below say it.
    readonly property string viewShort: !ready ? "" : service.quickView === "inbox" ? I18n.tr("INBOX") : service.quickView === "all" ? I18n.tr("ALL") : service.quickView === "custom" ? I18n.tr("CUSTOM") : I18n.tr("TODAY")

    implicitWidth: ready ? service.panelWidth : Theme.fontSize * 24
    implicitHeight: ready ? service.panelHeight : Theme.fontSize * 30

    onTasksChanged: {
        if (selectedIndex >= tasks.length)
            selectedIndex = tasks.length - 1;
    }
    onHasTokenChanged: {
        if (!hasToken)
            settingsView = true;
    }

    Component.onCompleted: {
        if (ready) {
            settingsView = !service.hasToken && service.settingsLoaded;
            service.setPanelOpen(true);
        }
        keys.forceActiveFocus();
    }
    Component.onDestruction: {
        if (ready)
            service.setPanelOpen(false);
    }

    Connections {
        target: root.service

        function onQuickAddDoneChanged(): void {
            quickAdd.text = "";
        }
        function onSettingsLoadedChanged(): void {
            if (root.service.settingsLoaded && !root.service.hasToken)
                root.settingsView = true;
        }
    }

    function closePanel(): void {
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    function selectView(view: string): void {
        root.selectedIndex = -1;
        root.cursorActive = false;
        root.service.selectQuickView(view);
    }

    function cycleView(direction: int): void {
        let i = viewOrder.indexOf(service.quickView);
        if (i < 0)
            i = 0;
        selectView(viewOrder[(i + direction + viewOrder.length) % viewOrder.length]);
    }

    function moveCursor(delta: int): void {
        if (tasks.length === 0)
            return;
        cursorActive = true;
        selectedIndex = Math.max(0, Math.min(tasks.length - 1, selectedIndex + delta));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function selectedTask(): var {
        return selectedIndex >= 0 && selectedIndex < tasks.length ? tasks[selectedIndex] : null;
    }

    function openTask(task: var): void {
        if (!task)
            return;
        service.openTask(task);
        closePanel();
    }

    function startEdit(): void {
        const task = selectedTask();
        if (!task || service.completingTaskIds.indexOf(task.id) !== -1)
            return;
        editingIndex = selectedIndex;
    }

    function finishEdit(content: string): void {
        const task = editingIndex >= 0 && editingIndex < tasks.length ? tasks[editingIndex] : null;
        editingIndex = -1;
        keys.forceActiveFocus();
        if (task)
            service.editTask(task.id, content);
    }

    function askDelete(): void {
        const task = selectedTask();
        if (!task)
            return;
        pendingDeleteId = String(task.id);
        pendingDeleteContent = String(task.content || "");
    }

    function answerDelete(yes: bool): void {
        const id = pendingDeleteId;
        pendingDeleteId = "";
        pendingDeleteContent = "";
        if (yes)
            service.deleteTask(id);
        keys.forceActiveFocus();
    }

    // The panel's keys, while no field has focus (a focused field takes them).
    Item {
        id: keys

        focus: true
        Keys.onPressed: event => {
            if (!root.ready)
                return;
            const t = event.text;
            if (root.pendingDeleteId !== "") {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || t === "y" || t === "Y")
                    root.answerDelete(true);
                else if (t === "n" || t === "N")
                    root.answerDelete(false);
                event.accepted = true;
                return;
            }
            if (t === "?") {
                root.helpOpen = !root.helpOpen;
            } else if (t === "r" || t === "R") {
                root.service.refresh();
                root.service.refreshBarCount();
            } else if (t === "p" || t === "P") {
                root.settingsView = !root.settingsView;
            } else if (root.settingsView) {
                return;
            } else if (event.key === Qt.Key_Tab) {
                root.cycleView(1);
            } else if (event.key === Qt.Key_Backtab) {
                root.cycleView(-1);
            } else if (event.key === Qt.Key_Down || t === "j") {
                root.moveCursor(1);
            } else if (event.key === Qt.Key_Up || t === "k") {
                root.moveCursor(-1);
            } else if (event.key === Qt.Key_Space) {
                const task = root.selectedTask();
                if (task)
                    root.service.requestComplete(String(task.id));
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                root.openTask(root.selectedTask());
            } else if (t === "e" || t === "E") {
                root.startEdit();
            } else if (t === "x" || t === "X" || event.key === Qt.Key_Delete) {
                root.askDelete();
            } else if (t === "q" || t === "Q") {
                quickAdd.forceActiveFocus();
            } else if (t === "t" || t === "T") {
                root.selectView("today");
            } else if (t === "i" || t === "I") {
                root.selectView("inbox");
            } else if (t === "a" || t === "A") {
                root.selectView("all");
            } else {
                return;
            }
            event.accepted = true;
        }
    }

    Column {
        id: content

        anchors.fill: parent
        spacing: Theme.gap

        // ---- Header: mark, title, state; the Settings toggle.
        Item {
            width: parent.width
            height: titleColumn.implicitHeight

            Text {
                id: mark

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: "\u{f0756}"
                color: Theme.foreground
                font.family: Theme.fontMono
                font.pixelSize: Theme.font.display
            }

            Column {
                id: titleColumn

                anchors.left: mark.right
                anchors.leftMargin: Theme.gap
                anchors.right: gear.left
                anchors.rightMargin: Theme.gap
                spacing: 2

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    // Set rather than implicit: a right-to-left panel then aligns
                    // Latin text and numbers to the right too (plan 109).
                    horizontalAlignment: Text.AlignLeft
                    text: "Todoist" // i18n-ignore: the product's name
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.title
                    font.bold: true
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                    text: root.headerMeta
                    elide: Text.ElideRight
                    color: root.ready && root.service.tokenInvalid ? Theme.urgent : Theme.muted
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.caption
                    font.bold: true
                    font.letterSpacing: 1.2
                }
            }

            Pill {
                id: gear

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.settingsView ? I18n.tr("Tasks") : I18n.tr("Settings")
                active: root.settingsView
                onClicked: root.settingsView = !root.settingsView
            }
        }

        // ---- Counts: what the list holds, from state already fetched.
        Row {
            id: stats

            readonly property real cell: (width - spacing * 3) / 4

            width: parent.width
            spacing: Theme.gap
            visible: root.hasToken && !root.settingsView && !(root.service.loading && root.tasks.length === 0)

            Repeater {
                model: !root.ready ? [] : [
                    { label: I18n.tr("TASKS"), value: String(root.service.taskCount) + (root.service.listTruncated ? "+" : ""), alert: false },
                    { label: I18n.tr("OVERDUE"), value: String(root.service.overdueCount), alert: root.service.overdueCount > 0 },
                    { label: I18n.tr("VIEW"), value: root.viewShort, alert: false },
                    { label: I18n.tr("SYNCED"), value: Model.formatRelativeTime(root.service.lastSyncedAt, I18n), alert: false }
                ]

                Column {
                    required property var modelData

                    width: stats.cell
                    spacing: 2

                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignLeft
                        text: modelData.label
                        elide: Text.ElideRight
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }

                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        horizontalAlignment: Text.AlignLeft
                        text: modelData.value
                        elide: Text.ElideRight
                        color: modelData.alert ? Theme.urgent : Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.bodySmall
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: Theme.borderWidth
            color: Theme.border
        }

        // ---- Settings.
        Flickable {
            width: parent.width
            height: content.height - y
            visible: root.settingsView && !root.helpOpen
            contentHeight: settingsColumn.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            TodoistSettings {
                id: settingsColumn

                width: parent.width
                service: root.service
                onShowKeys: root.helpOpen = true
                onDone: {
                    root.settingsView = false;
                    keys.forceActiveFocus();
                }
            }
        }

        // ---- Key list.
        Column {
            width: parent.width
            visible: root.helpOpen
            spacing: Math.round(Theme.gap / 2)

            TodoistSection {
                text: I18n.tr("KEYS")
            }

            Repeater {
                model: [
                    I18n.mark("j k / ↑ ↓ — move through the list"),
                    I18n.mark("Space — complete the task"),
                    I18n.mark("Enter — open it on todoist.com"),
                    I18n.mark("e — edit it, Enter saves"),
                    I18n.mark("x — delete it (Enter or y confirms, n cancels)"),
                    I18n.mark("q — quick add (p1–p4, #Project, @label, dates)"),
                    I18n.mark("t i a, Tab — Today, Inbox, All"),
                    I18n.mark("r — refresh"),
                    I18n.mark("p — settings"),
                    I18n.mark("? — this list"),
                    I18n.mark("Esc — close")
                ]

                Text {
                    required property string modelData

                    width: parent.width
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                    text: I18n.tr(modelData)
                    wrapMode: Text.Wrap
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                }
            }

            // A Column does not mirror x: the anchor puts it at the start edge.
            Pill {
                anchors.left: parent.left
                text: I18n.tr("Back")
                onClicked: {
                    root.helpOpen = false;
                    keys.forceActiveFocus();
                }
            }
        }

        // ---- Tasks.
        Row {
            width: parent.width
            spacing: Theme.gap
            visible: root.hasToken && !root.settingsView && !root.helpOpen

            TodoistField {
                id: quickAdd

                width: parent.width - addButton.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                placeholderText: I18n.tr("Add a task… (p1, #Project, tomorrow)")
                enabled: root.ready && !root.service.quickAddSubmitting
                onAccepted: root.service.submitQuickAdd(text)
            }

            Pill {
                id: addButton

                anchors.verticalCenter: parent.verticalCenter
                text: root.ready && root.service.quickAddSubmitting ? I18n.tr("Adding…") : I18n.tr("Add")
                busy: root.ready && root.service.quickAddSubmitting
                onClicked: root.service.submitQuickAdd(quickAdd.text)
            }
        }

        Row {
            width: parent.width
            spacing: Math.round(Theme.gap / 2)
            visible: root.hasToken && !root.settingsView && !root.helpOpen

            Repeater {
                model: [
                    { value: "today", label: I18n.mark("Today") },
                    { value: "inbox", label: I18n.mark("Inbox") },
                    { value: "all", label: I18n.mark("All") }
                ]

                Pill {
                    required property var modelData

                    text: I18n.tr(modelData.label)
                    active: root.ready && root.service.quickView === modelData.value
                    onClicked: root.selectView(modelData.value)
                }
            }
        }

        Text {
            width: parent.width
            visible: root.hasToken && !root.settingsView && !root.helpOpen && root.service.quickView !== "today"
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            text: root.viewLabel
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.caption
            font.bold: true
            font.letterSpacing: 1.1
        }

        // The delete question, in place of a dialog window (a second window
        // would break the panel's focus grab).
        Rectangle {
            width: parent.width
            height: visible ? confirmRow.implicitHeight + Theme.gap * 2 : 0
            visible: root.pendingDeleteId !== ""
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.width: Theme.borderWidth
            border.color: Theme.urgent

            Column {
                id: confirmRow

                anchors.fill: parent
                anchors.margins: Theme.gap
                spacing: Theme.gap

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
                    text: I18n.tr("Delete “%1”? This cannot be undone here.", root.pendingDeleteContent)
                    wrapMode: Text.Wrap
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.body
                }

                Row {
                    width: parent.width
                    spacing: Theme.gap

                    Pill {
                        text: I18n.tr("Delete")
                        active: true
                        onClicked: root.answerDelete(true)
                    }

                    Pill {
                        text: I18n.tr("Cancel")
                        onClicked: root.answerDelete(false)
                    }
                }
            }
        }

        ListView {
            id: list

            width: parent.width
            height: Math.max(0, content.height - y - (status.visible ? status.height + content.spacing : 0))
            visible: root.hasToken && !root.settingsView && !root.helpOpen
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.tasks
            spacing: 2

            delegate: TaskRow {
                required property var modelData
                required property int index

                width: ListView.view.width
                task: modelData
                rowIndex: index
                sectionTitle: Model.sectionTitle(root.tasks, index, root.service.quickView, I18n)
                selected: root.cursorActive && root.selectedIndex === index
                completing: root.service.completingTaskIds.indexOf(modelData.id) !== -1
                editing: root.editingIndex === index
                onEditingChanged: {
                    if (editing)
                        Qt.callLater(focusEdit);
                }
                onHovered: root.selectedIndex = index
                onCompleteRequested: root.service.requestComplete(String(modelData.id))
                onOpenRequested: root.openTask(modelData)
                onEditCommitted: text => root.finishEdit(text)
            }
        }

        Text {
            id: status

            width: parent.width
            visible: text !== "" && !root.helpOpen
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            text: {
                if (!root.ready)
                    return "";
                if (root.service.errorText !== "")
                    return root.service.errorText;
                if (root.settingsView || !root.hasToken)
                    return "";
                if (root.service.loading && root.tasks.length === 0)
                    return I18n.tr("Loading…");
                return root.tasks.length === 0 && !root.service.loading ? root.emptyMessage : "";
            }
            wrapMode: Text.Wrap
            color: root.ready && root.service.errorText !== "" ? Theme.urgent : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }
}
