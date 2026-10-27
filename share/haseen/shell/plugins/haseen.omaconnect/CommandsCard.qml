import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Commands set up on the device's Run command plugin, listed on demand and
// run with one click. Adapted from OmaConnect's
// components/RemoteCommandsSection.qml (MIT, Copyright (c) 2026 OmaConnect
// contributors).
Column {
    id: card

    required property var service

    spacing: Math.round(Theme.gap / 2)

    Row {
        spacing: Math.round(Theme.gap / 2)

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Commands")
            color: Theme.subtle(Theme.surface)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }

        Pill {
            text: card.service.commandsLoading ? I18n.tr("Loading…") : card.service.commands.length ? I18n.tr("Reload") : I18n.tr("Show")
            busy: card.service.commandsLoading
            onClicked: card.service.fetchCommands()
        }
    }

    Flow {
        width: card.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: card.service.commands

            delegate: Pill {
                required property var modelData

                text: modelData.name
                busy: card.service.busy
                onClicked: card.service.runCommand(modelData.key)
            }
        }
    }
}
