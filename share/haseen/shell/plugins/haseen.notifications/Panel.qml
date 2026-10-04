import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Recent notifications, newest first, with do-not-disturb and clear. Reads
// the running haseen.notifications service through the role registry; the
// list lives in memory only. Open with `haseen shell ipc panel toggle haseen.notifications`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.notifications;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    readonly property var items: service ? service.history.slice().reverse() : []

    width: typeof settings.width === "number" && settings.width >= 200 ? settings.width : 360
    spacing: Theme.gap

    Item {
        width: parent.width
        height: Theme.fontSize * 2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: root.service && root.service.dnd ? "Notifications (do not disturb)" : "Notifications"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Row {
            anchors.right: parent.right
            height: parent.height
            visible: root.service !== null

            BarButton {
                height: parent.height
                glyph: root.service && root.service.dnd ? "\uf1f6" : "\uf0f3"
                highlighted: root.service !== null && root.service.dnd
                onClicked: root.service.toggleDnd()
            }

            BarButton {
                height: parent.height
                glyph: "\uf1f8"
                visible: root.items.length > 0
                onClicked: root.service.clear()
            }
        }
    }

    Text {
        width: parent.width
        visible: root.items.length === 0
        text: root.service ? "No notifications" : "The notification service is not running"
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Flickable {
        width: parent.width
        height: Math.min(list.implicitHeight, Theme.fontSize * 40)
        visible: root.items.length > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list

            width: parent.width
            spacing: Theme.gap

            Repeater {
                model: root.items

                delegate: NotificationCard {
                    required property var modelData

                    notification: modelData
                    width: list.width
                    onActivated: root.service.invokeDefault(modelData)
                    onCloseClicked: root.service.dismiss(modelData)
                }
            }
        }
    }
}
