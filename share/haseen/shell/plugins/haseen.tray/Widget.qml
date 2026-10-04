import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Haseen

// StatusNotifier items. Left click activates, middle click is the
// secondary action, right click (or a menu-only item) opens its menu.
Row {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    height: parent ? parent.height : implicitHeight
    spacing: Math.round(Theme.gap / 2)

    Repeater {
        model: SystemTray.items

        delegate: MouseArea {
            id: cell

            required property SystemTrayItem modelData

            width: Theme.fontSize + Theme.gap * 2
            height: root.height
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onClicked: event => {
                if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && modelData.onlyMenu)) {
                    if (modelData.hasMenu) {
                        const p = cell.mapToItem(QsWindow.window.contentItem, event.x, event.y);
                        modelData.display(QsWindow.window, p.x, p.y);
                    }
                } else if (event.button === Qt.MiddleButton) {
                    modelData.secondaryActivate();
                } else {
                    modelData.activate();
                }
            }
            onWheel: event => modelData.scroll(event.angleDelta.y, false)

            IconImage {
                anchors.centerIn: parent
                implicitSize: Theme.fontSize + 2
                source: cell.modelData.icon
            }
        }
    }
}
