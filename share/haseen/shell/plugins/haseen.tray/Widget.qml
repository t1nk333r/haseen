import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets

// StatusNotifier items behind a chevron (plan 015). Collapsed by default:
// hovering the tray reveals the icons, leaving it hides them again after a
// short grace; clicking the chevron pins them open (settings.pinned, saved
// by `haseen bar tray`). Left click activates an item, middle click is its
// secondary action, right click (or a menu-only item) opens its menu.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false

    readonly property bool pinned: settings.pinned === true
    readonly property int count: SystemTray.items.values.length
    readonly property bool expanded: pinned || hover.hovered || grace.running
    readonly property int cell: Theme.fontSize + Theme.gap * 2
    // 0 collapsed .. 1 open; the reveal animates the icons' extent.
    property real reveal: expanded ? 1 : 0
    readonly property real iconsExtent: (vertical ? icons.implicitHeight : icons.implicitWidth) * reveal
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    Behavior on reveal {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    // No tray items: nothing to reveal, so no chevron either.
    implicitWidth: count === 0 ? 0 : vertical ? cell : cell + iconsExtent
    // The bar slot sets the real size; this is only the natural one, and
    // reading the parent here would feed the slot's size back into itself.
    implicitHeight: vertical ? cell + iconsExtent : Config.barThickness

    function togglePinned(): void {
        const next = !pinned;
        Config.setRuntime(["plugins", pluginId, "settings", "pinned"], next);
        Quickshell.execDetached([cli, "bar", "tray", next ? "pin" : "unpin", "--no-apply"]);
    }

    HoverHandler {
        id: hover

        onHoveredChanged: {
            if (hovered)
                grace.stop();
            else
                grace.restart();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: grace

        interval: 1500
        repeat: false
    }

    // Icons sit before the chevron (left of it, or above it when vertical),
    // so opening the tray pushes away from the rest of its section.
    Item {
        id: clipper

        x: 0
        y: 0
        width: root.vertical ? root.width : root.iconsExtent
        height: root.vertical ? root.iconsExtent : root.height
        clip: true

        Grid {
            id: icons

            anchors.right: root.vertical ? undefined : parent.right
            anchors.bottom: root.vertical ? parent.bottom : undefined
            columns: root.vertical ? 1 : Math.max(1, root.count)
            spacing: Math.round(Theme.gap / 2)

            Repeater {
                model: SystemTray.items

                delegate: MouseArea {
                    id: cellArea

                    required property SystemTrayItem modelData

                    width: root.vertical ? root.width : root.cell
                    height: root.vertical ? root.cell : root.height
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onClicked: event => {
                        if (event.button === Qt.RightButton || (event.button === Qt.LeftButton && modelData.onlyMenu)) {
                            if (modelData.hasMenu) {
                                const p = cellArea.mapToItem(QsWindow.window.contentItem, event.x, event.y);
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
                        source: cellArea.modelData.icon
                    }
                }
            }
        }
    }

    BarButton {
        id: chevron

        x: root.vertical ? 0 : root.iconsExtent
        y: root.vertical ? root.iconsExtent : 0
        width: root.vertical ? root.width : root.cell
        height: root.vertical ? root.cell : root.height
        padding: 0
        // Points at where the icons are (or would appear); accent when pinned.
        glyph: root.vertical ? (root.expanded ? "\uf078" : "\uf077") : (root.expanded ? "\uf054" : "\uf053")
        color: root.pinned ? Theme.accent : Theme.barForeground
        onClicked: button => {
            if (button === Qt.LeftButton)
                root.togglePinned();
        }
    }
}
