import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Polkit
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets

// haseen.polkit: the session's polkit authentication agent. When an app asks
// for a privileged action, a dialog shows the polkit message, the identity
// and the PAM prompt; the window exists only during a request.
//
// polkit accepts one agent per session. If another agent registered first
// (hyprpolkitagent, DMS, omarchy-shell), registration fails, one line is
// logged, and that agent keeps answering; nothing else changes.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var flow: agent.flow

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // Identity exposes displayName, string (user/group name), id and isGroup.
    function identityName(identity: var): string {
        if (!identity)
            return "";
        return identity.displayName || identity.string || "";
    }

    // Registration is asynchronous. When another agent owns the session,
    // Quickshell logs "An authentication agent already exists for the given
    // subject" and isRegistered stays false.
    PolkitAgent {
        id: agent

        path: "/org/haseen/PolkitAgent"
        onIsRegisteredChanged: console.info(root.pluginId + ": " + (isRegistered ? "registered as the polkit agent" : "polkit agent unregistered"))
    }

    LazyLoader {
        active: agent.isActive && root.flow !== null

        PanelWindow {
            id: dialog

            screen: root.focusedScreen()
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.namespace: "haseen-polkit"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            PanelSurface {
                anchors.centerIn: parent
                padding: Theme.gap * 3

                Column {
                    width: Theme.fontSize * 28
                    spacing: Theme.gap * 1.5

                    Row {
                        spacing: Theme.gap

                        Glyph {
                            glyph: "\uf023"
                            color: Theme.accent
                        }

                        Text {
                            text: "Authentication required"
                            color: Theme.accent
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize + 2
                        }
                    }

                    Text {
                        width: parent.width
                        text: root.flow ? root.flow.message : ""
                        color: Theme.foreground
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }

                    Text {
                        width: parent.width
                        visible: root.flow !== null && root.flow.identities.length > 0
                        text: {
                            if (!root.flow)
                                return "";
                            const many = root.flow.identities.length > 1;
                            return "As " + root.identityName(root.flow.selectedIdentity) + (many ? "  (click to switch)" : "");
                        }
                        color: Theme.muted
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.flow !== null && root.flow.identities.length > 1
                            onClicked: {
                                const ids = Array.from(root.flow.identities);
                                const i = ids.indexOf(root.flow.selectedIdentity);
                                root.flow.selectedIdentity = ids[(i + 1) % ids.length];
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Theme.fontSize * 2.6
                        radius: Theme.radius
                        color: Theme.surfaceAlt
                        border.color: input.activeFocus ? Theme.accent : Theme.border
                        border.width: Theme.borderWidth

                        TextInput {
                            id: input

                            anchors.fill: parent
                            anchors.leftMargin: Theme.gap * 1.5
                            anchors.rightMargin: Theme.gap * 1.5
                            verticalAlignment: TextInput.AlignVCenter
                            echoMode: root.flow && root.flow.responseVisible ? TextInput.Normal : TextInput.Password
                            enabled: root.flow !== null && root.flow.isResponseRequired
                            focus: true
                            color: Theme.foreground
                            selectionColor: Theme.selection
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                            onAccepted: {
                                if (root.flow && root.flow.isResponseRequired) {
                                    root.flow.submit(text);
                                    text = "";
                                }
                            }
                            Keys.onEscapePressed: root.flow.cancelAuthenticationRequest()
                            Component.onCompleted: forceActiveFocus()
                            // The field starts disabled until polkit asks for the
                            // response; a disabled item cannot hold focus, so the
                            // completion-time forceActiveFocus() is lost and typing
                            // and Enter would go nowhere. Take focus when it opens.
                            onEnabledChanged: if (enabled)
                                forceActiveFocus()
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.gap * 1.5
                            anchors.verticalCenter: parent.verticalCenter
                            visible: input.text === ""
                            text: root.flow && root.flow.inputPrompt !== "" ? root.flow.inputPrompt : "Password"
                            color: Theme.muted
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize
                        }
                    }

                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: {
                            if (!root.flow)
                                return "";
                            if (root.flow.supplementaryMessage !== "")
                                return root.flow.supplementaryMessage;
                            return root.flow.failed ? "Authentication failed, try again" : "";
                        }
                        color: root.flow && (root.flow.supplementaryIsError || root.flow.failed) ? Theme.urgent : Theme.muted
                        wrapMode: Text.Wrap
                        textFormat: Text.PlainText
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize - 1
                    }

                    Row {
                        anchors.right: parent.right
                        spacing: Theme.gap

                        BarButton {
                            height: Theme.fontSize * 2.2
                            text: "Cancel"
                            onClicked: root.flow.cancelAuthenticationRequest()
                        }

                        BarButton {
                            height: Theme.fontSize * 2.2
                            text: "Authenticate"
                            highlighted: true
                            onClicked: input.accepted()
                        }
                    }
                }
            }
        }
    }
}
