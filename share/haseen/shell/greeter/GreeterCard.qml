import QtQuick

// The login card: the user, the password field, the session, and whatever
// greetd last said. All behaviour lives in GreeterSession; this draws it.
//
// Adapted from DankMaterialShell quickshell/Modules/Greetd/GreeterContent.qml
// (MIT, Copyright (c) 2025 Avenge Media LLC).
Item {
    id: root

    required property GreeterPalette theme
    required property GreeterSession session
    property bool active: true

    implicitWidth: theme.fontSize * 26
    // Sized from the column, not from the card: the card fills this item, so
    // asking the card would be a binding loop and a zero-sized login screen.
    implicitHeight: column.implicitHeight + theme.gap * 6

    Connections {
        target: root.session

        // A new prompt or a failure both want the field empty and focused.
        function onPromptChanged(): void {
            password.text = "";
            password.echoMode = root.session.secret ? TextInput.Password : TextInput.Normal;
            if (root.active)
                password.forceActiveFocus();
        }
    }

    Rectangle {
        id: card

        anchors.fill: parent
        color: root.theme.surface
        radius: root.theme.radius
        border.color: root.theme.border
        border.width: root.theme.borderWidth

        Column {
            id: column

            anchors.centerIn: parent
            width: parent.width - root.theme.gap * 6
            spacing: root.theme.gap * 2

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.session.currentUser ? root.session.currentUser.display : "no user on this machine"
                color: root.theme.foreground
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(root.theme.fontSize * 1.6)
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: root.session.users.length > 1
                text: "\u2190 \u2192 another user"
                color: root.theme.muted
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(root.theme.fontSize * 0.9)
            }

            Rectangle {
                width: parent.width
                height: Math.round(root.theme.fontSize * 2.4)
                radius: root.theme.radius
                color: root.theme.surfaceAlt
                border.color: password.activeFocus ? root.theme.accent : root.theme.border
                border.width: root.theme.borderWidth

                TextInput {
                    id: password

                    anchors.fill: parent
                    anchors.margins: root.theme.gap
                    verticalAlignment: TextInput.AlignVCenter
                    echoMode: TextInput.Password
                    enabled: root.active
                    focus: root.active
                    color: root.theme.foreground
                    font.family: root.theme.fontFamily
                    font.pixelSize: root.theme.fontSize

                    Keys.onReturnPressed: root.session.answer(password.text)
                    Keys.onEnterPressed: root.session.answer(password.text)
                    Keys.onLeftPressed: root.session.cycleUser(-1)
                    Keys.onRightPressed: root.session.cycleUser(1)
                    Keys.onTabPressed: root.session.cycleSession(1)
                    Keys.onBacktabPressed: root.session.cycleSession(-1)
                    Component.onCompleted: if (root.active)
                        forceActiveFocus()
                }
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                text: root.session.currentSession ? root.session.currentSession.name + "   (Tab)" : "no session installed"
                color: root.theme.muted
                font.family: root.theme.fontFamily
                font.pixelSize: root.theme.fontSize
            }

            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                visible: root.session.status !== ""
                text: root.session.status
                wrapMode: Text.WordWrap
                color: root.theme.urgent
                font.family: root.theme.fontFamily
                font.pixelSize: Math.round(root.theme.fontSize * 0.95)
            }
        }
    }
}
