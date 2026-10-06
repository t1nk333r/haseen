// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml (TrayItem).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file, theme tokens, haseen's popup tooltip.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Haseen

// One StatusNotifier item. Left click activates it (or opens the menu of a
// menu-only item), middle click is its secondary action, right press opens
// its menu, the wheel scrolls it.
Item {
    id: root

    required property SystemTrayItem modelData
    property int extent: Theme.fontSize + Theme.gap * 2

    signal menuRequested(SystemTrayItem item, Item anchor, real x, real y)

    readonly property string tooltip: modelData.tooltipTitle || modelData.title || modelData.id || ""

    implicitWidth: extent
    implicitHeight: extent

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: mouse.containsMouse
    }

    TrayIcon {
        anchors.centerIn: parent
        width: Theme.fontSize + 2
        height: Theme.fontSize + 2
        icon: root.modelData.icon
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: event => {
            if (event.button === Qt.RightButton)
                root.menuRequested(root.modelData, root, event.x, event.y);
        }
        onClicked: event => {
            if (event.button === Qt.RightButton)
                return;
            if (event.button === Qt.MiddleButton)
                root.modelData.secondaryActivate();
            else if (root.modelData.onlyMenu)
                root.menuRequested(root.modelData, root, event.x, event.y);
            else
                root.modelData.activate();
        }
        onWheel: event => root.modelData.scroll(event.angleDelta.y, false)
    }

    // Hover tooltip; the window exists only while hovered.
    LazyLoader {
        active: mouse.containsMouse && root.tooltip !== ""

        PopupWindow {
            readonly property string pos: Config.barPosition
            readonly property int away: pos === "bottom" ? Edges.Top : pos === "left" ? Edges.Right : pos === "right" ? Edges.Left : Edges.Bottom

            visible: true
            color: "transparent"
            anchor.item: root
            anchor.edges: away
            anchor.gravity: away
            anchor.margins.top: pos === "top" ? Theme.gap : 0
            anchor.margins.bottom: pos === "bottom" ? Theme.gap : 0
            anchor.margins.left: pos === "left" ? Theme.gap : 0
            anchor.margins.right: pos === "right" ? Theme.gap : 0
            implicitWidth: Math.ceil(label.implicitWidth) + Theme.gap * 2
            implicitHeight: Math.ceil(label.implicitHeight) + Theme.gap * 2

            Rectangle {
                anchors.fill: parent
                color: Theme.surface
                radius: Theme.radius
                border.width: Theme.borderWidth
                border.color: Theme.border

                Text {
                    id: label

                    anchors.centerIn: parent
                    text: root.tooltip
                    textFormat: Text.PlainText
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }
            }
        }
    }
}
