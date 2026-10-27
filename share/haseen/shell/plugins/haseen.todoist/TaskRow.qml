import QtQuick
import qs.Haseen
import "Model.js" as Model

// One task in the haseen.todoist panel: a complete button, the content
// (struck through while it completes, an inline field while it is edited) and
// the due label, red when overdue. The colour of the content and the button
// is the task's priority as a Theme role (Model.priorityTone). A click on the
// row opens the task on todoist.com.
//
// Adapted from the TaskRow component of Panel.qml in omarchy-todoist (MIT,
// Copyright (c) 2026 aryan-techie), as the owner's fork t1nk33r.todoist
// 1.14.0; see LICENSE and UPSTREAM.md beside this file. haseen changes: its
// own file on Theme tokens; priority roles instead of Todoist's fixed hex
// colours.
Item {
    id: row

    required property var task
    required property int rowIndex
    property bool selected: false
    property bool completing: false
    property bool editing: false
    property string sectionTitle: ""

    signal hovered
    signal completeRequested
    signal openRequested
    signal editCommitted(string content)

    readonly property bool overdue: Model.taskIsOverdue(task)
    readonly property string dueLabel: Model.taskDueLabel(task)
    readonly property string tone: Model.priorityTone(task ? task.priority : 0)
    readonly property color textColor: tone === "urgent" ? Theme.urgent : tone === "warning" ? Theme.warning : tone === "accent" ? Theme.accent : Theme.foreground

    function focusEdit(): void {
        editField.text = row.task ? String(row.task.content || "") : "";
        editField.forceActiveFocus();
        editField.selectAll();
    }

    implicitHeight: header.height + body.height

    TodoistSection {
        id: header

        visible: row.sectionTitle !== ""
        height: visible ? implicitHeight + Theme.gap : 0
        verticalAlignment: Text.AlignBottom
        text: row.sectionTitle
    }

    Item {
        id: body

        anchors.top: header.bottom
        width: parent.width
        height: Math.max(check.height, textColumn.implicitHeight) + Theme.gap

        // Declared first, so the button and the edit field keep their own clicks.
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: {
                if (containsMouse)
                    row.hovered();
            }
            onClicked: row.openRequested()
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            visible: row.selected
            color: Theme.surfaceAlt
        }

        Text {
            id: check

            anchors.left: parent.left
            anchors.leftMargin: Math.round(Theme.gap / 2)
            anchors.top: parent.top
            anchors.topMargin: Math.round(Theme.gap / 2)
            textFormat: Text.PlainText
            // md-checkbox_blank_circle_outline / md-checkbox_marked_circle
            text: row.completing ? "\u{f0133}" : "\u{f0130}"
            color: checkMouse.containsMouse ? Theme.accent : row.textColor
            font.family: Theme.fontMono
            font.pixelSize: Theme.font.title

            MouseArea {
                id: checkMouse

                anchors.fill: parent
                anchors.margins: -Math.round(Theme.gap / 2)
                hoverEnabled: true
                enabled: !row.completing
                cursorShape: Qt.PointingHandCursor
                onClicked: row.completeRequested()
            }
        }

        Column {
            id: textColumn

            anchors.left: check.right
            anchors.leftMargin: Theme.gap
            anchors.right: parent.right
            anchors.rightMargin: Math.round(Theme.gap / 2)
            anchors.top: parent.top
            anchors.topMargin: Math.round(Theme.gap / 2)
            spacing: 2

            Text {
                visible: !row.editing
                width: parent.width
                textFormat: Text.PlainText
                // Set rather than implicit: a right-to-left panel then aligns
                // Latin text and numbers to the right too (plan 109).
                horizontalAlignment: Text.AlignLeft
                text: row.task ? String(row.task.content || "") : ""
                opacity: row.completing ? 0.5 : 1
                font.strikeout: row.completing
                color: row.textColor
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            TodoistField {
                id: editField

                visible: row.editing
                width: parent.width
                onAccepted: row.editCommitted(text)
            }

            Text {
                visible: row.dueLabel !== "" && !row.editing
                width: parent.width
                textFormat: Text.PlainText
                horizontalAlignment: Text.AlignLeft
                text: row.dueLabel
                color: row.overdue ? Theme.urgent : Theme.muted
                wrapMode: Text.Wrap
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.caption
            }
        }
    }
}
