// Adapted from Omarchy shell/plugins/panels/network/Panel.qml (NetworkRow).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: presentational only (the panel owns actions and NetworkManager
// signals), theme tokens, hover hint instead of tooltips.
import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// One Wi-Fi network. A single line normally; expands into a passphrase
// prompt (plus an identity field for WPA-Enterprise) when the panel opens
// one for it. The typed text lives in the panel, because a scan rebuilds the
// rows and would otherwise drop it.
Item {
    id: row

    required property var net
    property string statusText: ""
    property bool failed: false
    property bool busy: false
    property bool panelBusy: false
    property bool requiresCredentials: false
    property bool enterprise: false
    property bool canForget: false
    property bool passwordOpen: false
    property string identityText: ""
    property string passwordText: ""

    signal activated
    signal forgetRequested
    signal identityEdited(string text)
    signal passwordEdited(string text)
    signal submitted
    signal hint(string text)

    readonly property bool forgetVisible: canForget && (!requiresCredentials || rightMouse.containsMouse)
    readonly property color statusColor: failed ? Theme.urgent : busy || net.connected ? Theme.foreground : Theme.muted
    readonly property bool canSubmit: passwordText.length > 0 && (!enterprise || identityText.length > 0) && !panelBusy

    implicitHeight: body.height + (passwordOpen ? prompt.height + Theme.gap : 0)

    function submit(): void {
        if (canSubmit)
            row.submitted();
    }

    Rectangle {
        anchors.fill: body
        radius: Theme.radius
        // Not Theme.selection: themes may set it to the accent, which hides
        // the accent glyph and the text on top.
        color: Theme.surfaceAlt
        border.color: row.net.connected ? Theme.accent : "transparent"
        border.width: Theme.borderWidth
        visible: row.net.connected || rowMouse.containsMouse || row.passwordOpen
    }

    MouseArea {
        id: rowMouse

        anchors.fill: body
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        enabled: !row.panelBusy
        onClicked: row.activated()
    }

    Item {
        id: body

        width: parent.width
        height: Math.round(Theme.fontSize * 2.6)

        Glyph {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: Model.wifiIconFor(row.net.signal)
            color: row.net.connected ? Theme.accent : row.statusColor
        }

        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.gap
            anchors.right: right.visible ? right.left : parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: row.net.ssid
                color: Theme.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                visible: row.statusText !== ""
                textFormat: Text.PlainText
                text: row.statusText
                color: row.statusColor
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        // A lock for networks that need credentials; Forget on hover for
        // saved ones (directly for saved open networks).
        Item {
            id: right

            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 1.8
            height: width
            visible: row.requiresCredentials || row.canForget

            Rectangle {
                anchors.fill: parent
                radius: Theme.radius
                color: "transparent"
                border.color: Theme.urgent
                border.width: Theme.borderWidth
                visible: rightMouse.containsMouse && row.canForget
            }

            Glyph {
                anchors.centerIn: parent
                glyph: row.forgetVisible ? "\u{F0159}" : "\u{F033E}"
                color: row.forgetVisible ? Theme.urgent : Theme.muted
                font.pixelSize: Theme.fontSize
            }

            MouseArea {
                id: rightMouse

                anchors.fill: parent
                hoverEnabled: true
                enabled: row.canForget && !row.panelBusy
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onContainsMouseChanged: row.hint(containsMouse ? "Forget network" : "")
                onClicked: row.forgetRequested()
            }
        }
    }

    component Field: Rectangle {
        id: field

        property alias text: input.text
        property alias input: input
        property string placeholder
        property bool secret: false

        signal accepted
        signal edited(string text)

        height: Math.round(Theme.fontSize * 2.2)
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: input.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Theme.gap
            anchors.rightMargin: Theme.gap
            verticalAlignment: TextInput.AlignVCenter
            echoMode: field.secret ? TextInput.Password : TextInput.Normal
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            clip: true
            onTextChanged: field.edited(text)
            Keys.onReturnPressed: field.accepted()
            Keys.onEnterPressed: field.accepted()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: field.placeholder
                color: Theme.muted
                font: input.font
            }
        }
    }

    // The prompt: Enter or the check button connects; Escape closes the
    // panel (and with it the prompt).
    Item {
        id: prompt

        visible: row.passwordOpen
        anchors.top: body.bottom
        anchors.topMargin: Theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap
        height: fields.height

        Column {
            id: fields

            anchors.left: parent.left
            anchors.right: connect.left
            anchors.rightMargin: Theme.gap
            spacing: Math.round(Theme.gap / 2)
            visible: !row.busy && !row.failed

            Field {
                id: identity

                width: parent.width
                visible: row.enterprise
                placeholder: "Identity (user@domain)"
                text: row.identityText
                onEdited: t => {
                    if (t !== row.identityText)
                        row.identityEdited(t);
                }
                onAccepted: passphrase.input.forceActiveFocus()
            }

            Field {
                id: passphrase

                width: parent.width
                secret: true
                placeholder: "Passphrase"
                text: row.passwordText
                onEdited: t => {
                    if (t !== row.passwordText)
                        row.passwordEdited(t);
                }
                onAccepted: row.submit()
            }
        }

        // Busy or failed: one line in place of the fields.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            height: Math.round(Theme.fontSize * 2.2)
            visible: row.busy || row.failed
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.color: Theme.border
            border.width: Theme.borderWidth

            Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: row.failed ? row.statusText : "Connecting…"
                color: row.failed ? Theme.urgent : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }

        BarButton {
            id: connect

            anchors.right: parent.right
            anchors.bottom: fields.bottom
            height: Math.round(Theme.fontSize * 2.2)
            visible: !row.busy && !row.failed
            glyph: "\u{F012C}"
            color: row.canSubmit ? Theme.accent : Theme.muted
            onClicked: row.submit()
        }
    }

    // Focus the first empty field when the prompt opens or comes back after
    // a failure. Deferred: the field is not visible yet in this frame.
    function focusPrompt(): void {
        if (!passwordOpen || busy || failed)
            return;
        if (enterprise && identity.text === "")
            identity.input.forceActiveFocus();
        else
            passphrase.input.forceActiveFocus();
    }

    onPasswordOpenChanged: Qt.callLater(focusPrompt)
    onFailedChanged: Qt.callLater(focusPrompt)
    onBusyChanged: Qt.callLater(focusPrompt)
    Component.onCompleted: Qt.callLater(focusPrompt)
}
