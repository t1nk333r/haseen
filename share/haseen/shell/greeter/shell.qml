//@ pragma UseQApplication
//@ pragma Env QT_QUICK_BACKEND=software

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Greetd

// haseen's login screen: one fullscreen layer surface per monitor, the users on
// this machine, the sessions it can start, and greetd doing the authentication.
//
// Adapted from DankMaterialShell quickshell/DMSGreeter.qml and
// Modules/Greetd/GreeterContent.qml (MIT, Copyright (c) 2025 Avenge Media LLC).
// The protocol is not reimplemented: Quickshell's `Greetd` singleton speaks it
// (createSession/respond/launch, authMessage/authFailure/readyToLaunch), which
// is the same contract upstream uses.
//
// Started by bin/haseen-greeter, which greetd runs. Not a desktop shell: no
// bar, no plugins, no IPC.
ShellRoot {
    id: root

    // One palette for every screen; the card takes it as a property, so the
    // greeter needs no singleton and no qs.Haseen import.
    property GreeterPalette theme: GreeterPalette {}
    // One login for every screen: the card on the focused screen drives it.
    property GreeterSession session: GreeterSession {}

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true
            exclusionMode: ExclusionMode.Ignore
            color: root.theme.background
            WlrLayershell.namespace: "haseen-greeter"
            WlrLayershell.layer: WlrLayer.Overlay
            // Only the screen the pointer woke up on takes the keyboard; the
            // others are backdrops, or two cards would fight over the password.
            WlrLayershell.keyboardFocus: modelData === Quickshell.screens[0] ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

            GreeterCard {
                anchors.centerIn: parent
                active: modelData === Quickshell.screens[0]
                theme: root.theme
                session: root.session
            }
        }
    }
}
