import QtQuick
import Quickshell
import qs.Haseen

// The lock screen itself: clock, date, password field and a status line.
// Shared by the session-lock surfaces and the preview window. When the
// fingerprint reader is armed, a fingerprint glyph sits inside the field's
// right edge, as in Omarchy's lock (shell/plugins/lock/LockView.qml, MIT,
// Copyright (c) David Heinemeier Hansson) and hyprlock.
Rectangle {
    id: root

    property bool busy: false
    property string message: ""
    property bool preview: false
    // Fingerprint unlock is armed: show the hint. fingerprintError: the last
    // scan did not match, so the hint turns urgent until the next one.
    property bool fingerprint: false
    property bool fingerprintError: false

    // Room kept clear on both sides for the hint, so the centred dots stay
    // centred and never run under it.
    readonly property real fingerprintReserve: fingerprint ? Math.ceil(fingerprintHint.implicitWidth + Theme.gap) : 0

    signal submitted(string password)
    signal cancelled

    color: Theme.background

    // A failed attempt clears the field for the next one.
    onMessageChanged: {
        if (message !== "")
            input.text = "";
    }

    SystemClock {
        id: clock

        precision: SystemClock.Minutes
        enabled: root.visible
    }

    Column {
        anchors.centerIn: parent
        spacing: Theme.gap * 2

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(clock.date, "HH:mm")
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize * 6
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDate(clock.date, "dddd, d MMMM")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Theme.fontSize * 22
            height: Theme.fontSize * 3
            radius: Theme.radius
            color: Theme.surface
            border.color: input.activeFocus ? Theme.accent : Theme.border
            border.width: Theme.borderWidth

            TextInput {
                id: input

                anchors.fill: parent
                anchors.leftMargin: Theme.gap * 2 + root.fingerprintReserve
                anchors.rightMargin: Theme.gap * 2 + root.fingerprintReserve
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                echoMode: TextInput.Password
                passwordCharacter: "\u2022"
                readOnly: root.busy
                focus: true
                color: Theme.foreground
                selectionColor: Theme.selection
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
                onAccepted: root.submitted(text)
                Keys.onEscapePressed: {
                    if (root.preview)
                        root.cancelled();
                    else
                        text = "";
                }
            }

            Text {
                anchors.centerIn: parent
                visible: input.text === "" && !root.busy
                text: "Password"
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                id: fingerprintHint

                objectName: "fingerprintHint"
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap * 2
                anchors.verticalCenter: parent.verticalCenter
                visible: root.fingerprint
                // nf-md-fingerprint
                text: "󰈷"
                color: root.fingerprintError ? Theme.urgent : Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize + 6
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.busy ? "Checking…" : root.message
            visible: text !== ""
            color: root.busy ? Theme.muted : Theme.urgent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: root.preview
            text: "Preview: the session is not locked. Escape closes it."
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    Component.onCompleted: input.forceActiveFocus()
}
