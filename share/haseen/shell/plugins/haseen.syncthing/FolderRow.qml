import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// One folder in the haseen.syncthing panel: label, state and path, then
// Rescan, Pause or Resume, and Share… which lists the devices to share it
// with (a lit pill is shared; a click toggles it). Adapted from the folder
// rows of ilyaZar's omarchy-syncthing (MIT, Copyright (c) 2026 IlyaZar).
Column {
    id: row

    required property var folder
    required property var service
    property bool sharing: false

    readonly property var devices: service.info ? service.info.devices : []
    readonly property color subtle: Theme.subtle(Theme.surface)

    spacing: Math.round(Theme.gap / 2)

    Item {
        width: row.width
        height: Math.round(Theme.fontSize * 2.4)

        Column {
            anchors.left: parent.left
            anchors.right: buttons.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: row.folder.label + "  ·  " + Model.folderText(row.folder, I18n)
                color: Model.folderFailed(row.folder) ? Theme.urgent : Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.body
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                text: row.folder.path + "  ·  " + Model.formatBytes(row.folder.globalBytes)
                color: row.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }
        }

        Row {
            id: buttons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.gap / 2)

            Pill {
                text: I18n.tr("Rescan")
                busy: row.service.busy
                enabled: !row.folder.paused
                onClicked: row.service.rescan(row.folder.id)
            }

            Pill {
                text: row.folder.paused ? I18n.tr("Resume") : I18n.tr("Pause")
                busy: row.service.busy
                onClicked: row.service.setPaused(row.folder.id, !row.folder.paused)
            }

            Pill {
                text: I18n.tr("Share")
                active: row.sharing
                enabled: row.devices.length > 0
                onClicked: row.sharing = !row.sharing
            }
        }
    }

    Flow {
        width: row.width
        visible: row.sharing
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: row.devices

            delegate: Pill {
                required property var modelData
                readonly property bool on: Model.shared(row.folder, modelData.id)

                text: modelData.name
                active: on
                busy: row.service.busy
                onClicked: row.service.share(row.folder.id, modelData.id, !on)
            }
        }
    }
}
