import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.syncthing panel (plan 098), ported from ilyaZar's omarchy-syncthing,
// hosts/omarchy/OmarchyPanel.qml (MIT, Copyright (c) 2026 IlyaZar): the state
// in a line, the user service and Pause all / Resume all, invitations from
// devices and the folders they offer, every folder with its state and
// sharing, the devices, a new folder, and the recent file activity.
// Everything comes from the haseen.syncthing service (role `syncthing`);
// opening the panel asks it for a fresh status. haseen changes: native haseen
// widgets; upstream's themed web UI is not ported (Open web UI opens
// Syncthing's own); the folder lifecycle (folder types, ignore patterns,
// versioning) stays in that web UI.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    property var service: {
        const entry = Plugins.roles.syncthing;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var info: service && service.online ? service.info : null
    readonly property color subtle: Theme.subtle(Theme.surface)

    width: Theme.fontSize * 30
    spacing: Theme.gap

    Component.onCompleted: {
        if (service)
            service.refresh();
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            id: title

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Syncthing"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.left: title.right
            anchors.leftMargin: Theme.gap
            anchors.right: actions.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            text: root.service ? root.service.summary.text : ""
            color: root.service && root.service.summary.kind === "error" ? Theme.urgent : root.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Row {
            id: actions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.gap / 2)
            visible: root.info !== null

            Pill {
                readonly property bool allPaused: root.info !== null && root.info.devices.length > 0 && root.info.devices.every(d => d.paused)

                text: allPaused ? "Resume all" : "Pause all"
                busy: root.service !== null && root.service.busy
                onClicked: root.service.setAllPaused(!allPaused)
            }

            Pill {
                text: "Web UI"
                enabled: root.info !== null && root.info.guiUrl !== ""
                onClicked: root.service.openWebUi()
            }
        }
    }

    // Not running: why, and the user service.
    Column {
        width: parent.width
        visible: root.service === null || (root.service.loaded && !root.service.online)
        spacing: Math.round(Theme.gap / 2)

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: !root.service ? "The haseen.syncthing service is not running: list it in the shell's services." : root.service.problem
            color: root.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        Pill {
            visible: root.service !== null
            text: root.service && root.service.serviceState === "active" ? "Restart Syncthing" : "Start Syncthing"
            busy: root.service !== null && root.service.busy
            onClicked: root.service.controlService(root.service.serviceState === "active" ? "restart" : "start")
        }
    }

    // Invitations: a device asking to connect, a folder a device offers.
    Repeater {
        model: root.info ? root.info.pendingDevices : []

        delegate: Item {
            id: invite

            required property var modelData

            width: root.width
            height: Math.round(Theme.fontSize * 2.4)

            Text {
                anchors.left: parent.left
                anchors.right: inviteButtons.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: invite.modelData.name + " (" + invite.modelData.id.slice(0, 7) + ") wants to connect"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Row {
                id: inviteButtons

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Math.round(Theme.gap / 2)

                Pill {
                    text: "Add"
                    active: true
                    busy: root.service.busy
                    onClicked: root.service.acceptDevice(invite.modelData.id, invite.modelData.name)
                }

                Pill {
                    text: "Dismiss"
                    busy: root.service.busy
                    onClicked: root.service.dismissDevice(invite.modelData.id)
                }
            }
        }
    }

    Repeater {
        model: root.info ? root.info.pendingFolders : []

        delegate: Column {
            id: offer

            required property var modelData

            width: root.width
            spacing: Math.round(Theme.gap / 2)

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: offer.modelData.deviceName + " offers the folder " + offer.modelData.label
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Row {
                width: parent.width
                spacing: Math.round(Theme.gap / 2)

                Field {
                    id: offerPath

                    width: parent.width - acceptOffer.width - dismissOffer.width - 2 * parent.spacing
                    text: "~/" + offer.modelData.label.replace(/[\/\x00]/g, "_")
                    placeholder: "Where to keep it"
                    onAccepted: root.service.acceptFolder(offer.modelData, text)
                }

                Pill {
                    id: acceptOffer

                    text: "Accept"
                    active: true
                    busy: root.service.busy
                    onClicked: root.service.acceptFolder(offer.modelData, offerPath.text)
                }

                Pill {
                    id: dismissOffer

                    text: "Dismiss"
                    busy: root.service.busy
                    onClicked: root.service.dismissFolder(offer.modelData)
                }
            }
        }
    }

    Heading {
        visible: root.info !== null
        text: "Folders"
    }

    Repeater {
        model: root.info ? root.info.folders : []

        delegate: FolderRow {
            required property var modelData

            width: root.width
            folder: modelData
            service: root.service
        }
    }

    Row {
        width: parent.width
        visible: root.info !== null
        spacing: Math.round(Theme.gap / 2)

        Field {
            id: newFolder

            width: parent.width - addFolder.width - parent.spacing
            placeholder: "Sync another folder, e.g. ~/Documents"
            onAccepted: {
                if (root.service.addFolder(text))
                    text = "";
            }
        }

        Pill {
            id: addFolder

            text: "Add"
            enabled: newFolder.text.trim() !== ""
            busy: root.service !== null && root.service.busy
            onClicked: {
                if (root.service.addFolder(newFolder.text))
                    newFolder.text = "";
            }
        }
    }

    Heading {
        visible: root.info !== null && root.info.devices.length > 0
        text: "Devices"
    }

    Flow {
        width: parent.width
        visible: root.info !== null
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: root.info ? root.info.devices : []

            delegate: Text {
                required property var modelData

                textFormat: Text.PlainText
                text: modelData.name + (modelData.paused ? " · paused" : modelData.connected ? " · connected" : " · offline") + "   "
                color: modelData.connected ? Theme.foreground : root.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }

    Heading {
        visible: root.service !== null && root.service.activity.length > 0
        text: "Recent activity"
    }

    Repeater {
        model: root.service ? root.service.activity.slice(0, 8) : []

        delegate: Text {
            required property var modelData

            width: root.width
            textFormat: Text.PlainText
            elide: Text.ElideMiddle
            text: Model.activityText(modelData, root.info ? root.info.folders : [])
            color: modelData.error ? Theme.urgent : root.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: parent.width
        visible: text !== ""
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: root.service ? (root.service.error || root.service.message) : ""
        color: root.service && root.service.error ? Theme.urgent : Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
