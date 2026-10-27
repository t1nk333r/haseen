import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// The haseen.todoist panel's Settings: the API token (saved to the plugin's
// private settings file through the service, never shown again), the custom
// filter, what the bar counts, and the panel's size. Every change is saved at
// once.
//
// Adapted from the settings view of Panel.qml in omarchy-todoist (MIT,
// Copyright (c) 2026 aryan-techie), as the owner's fork t1nk33r.todoist
// 1.14.0; see LICENSE and UPSTREAM.md beside this file. haseen changes: its
// own file on Theme tokens and Pill buttons; no keyboard-shortcut section
// (bind `haseen shell ipc panel toggle haseen.todoist` in your own Hyprland
// binds instead).
Column {
    id: root

    property var service: null

    signal showKeys
    signal done

    readonly property bool hasToken: !!service && service.hasToken

    spacing: Theme.gap

    function saveToken(): void {
        if (tokenField.text.trim() === "")
            return;
        root.service.saveToken(tokenField.text);
        tokenField.text = "";
        root.done();
    }

    TodoistSection {
        text: I18n.tr("ACCOUNT")
    }

    Text {
        width: parent.width
        textFormat: Text.PlainText
        // Set rather than implicit: a right-to-left panel then aligns
        // Latin text and numbers to the right too (plan 109).
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("Paste your Todoist API token: Todoist › Settings › Integrations › Developer. It is kept in a private file under ~/.local/state, never in shell.json.")
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }

    TodoistField {
        id: tokenField

        width: parent.width
        password: true
        placeholderText: root.hasToken ? I18n.tr("Token saved; paste a new one to replace it") : I18n.tr("API token")
        onAccepted: root.saveToken()
    }

    // Rows span the width, so a right-to-left panel starts them at the right
    // (a Column does not mirror x).
    Row {
        width: parent.width
        spacing: Theme.gap

        Pill {
            text: I18n.tr("Save token")
            enabled: tokenField.text.trim() !== ""
            onClicked: root.saveToken()
        }

        Pill {
            text: I18n.tr("Remove token")
            visible: root.hasToken
            onClicked: root.service.clearToken()
        }
    }

    TodoistSection {
        text: I18n.tr("CUSTOM FILTER")
    }

    Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("Todoist filter syntax (\"today | overdue\", \"#Work & !subtask\"), shown as the custom view.")
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }

    Row {
        width: parent.width
        spacing: Theme.gap

        TodoistField {
            id: filterField

            width: parent.width - applyButton.width - parent.spacing
            anchors.verticalCenter: parent.verticalCenter
            text: root.service ? root.service.filterQuery : ""
            onAccepted: root.service.applyFilter(text)
        }

        Pill {
            id: applyButton

            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Apply")
            enabled: root.hasToken
            onClicked: {
                root.service.applyFilter(filterField.text);
                root.done();
            }
        }
    }

    TodoistSection {
        text: I18n.tr("BAR COUNT")
    }

    Text {
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("A count beside the bar mark, whichever tab the panel shows.")
        wrapMode: Text.Wrap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
    }

    Row {
        width: parent.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: [
                { value: "hide", label: I18n.mark("Hide") },
                { value: "today", label: I18n.mark("Today") },
                { value: "inbox", label: I18n.mark("Inbox") },
                { value: "all", label: I18n.mark("All") }
            ]

            Pill {
                required property var modelData

                text: I18n.tr(modelData.label)
                active: !!root.service && root.service.barCountMode === modelData.value
                onClicked: root.service.setBarCountMode(modelData.value)
            }
        }
    }

    TodoistSection {
        text: I18n.tr("GENERAL")
    }

    Row {
        width: parent.width
        spacing: Math.round(Theme.gap / 2)

        Pill {
            text: root.service && root.service.loading ? I18n.tr("Refreshing…") : I18n.tr("Refresh now")
            enabled: root.hasToken
            onClicked: {
                root.service.refresh();
                root.service.refreshBarCount();
            }
        }

        Pill {
            text: I18n.tr("Open Todoist")
            onClicked: root.service.openTodoist()
        }

        Pill {
            text: I18n.tr("Keys")
            onClicked: root.showKeys()
        }
    }

    TodoistSection {
        text: I18n.tr("PANEL SIZE")
    }

    Repeater {
        model: [
            { label: I18n.mark("Width  %1 px"), key: "w" },
            { label: I18n.mark("Height  %1 px"), key: "h" }
        ]

        Row {
            id: sizeRow

            required property var modelData
            readonly property int value: !root.service ? 0 : modelData.key === "w" ? root.service.panelWidth : root.service.panelHeight

            width: root.width
            spacing: Theme.gap

            function step(delta: int): void {
                if (modelData.key === "w")
                    root.service.setPanelSize(root.service.panelWidth + delta, root.service.panelHeight);
                else
                    root.service.setPanelSize(root.service.panelWidth, root.service.panelHeight + delta);
            }

            Text {
                width: Theme.fontSize * 8
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                text: I18n.tr(sizeRow.modelData.label, sizeRow.value)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            Pill {
                text: "−"
                onClicked: sizeRow.step(-20)
            }

            Pill {
                text: "+"
                onClicked: sizeRow.step(20)
            }
        }
    }
}
