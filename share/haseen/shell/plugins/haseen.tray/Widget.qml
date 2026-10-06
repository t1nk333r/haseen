// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: no hover reveal and no per-item pin/hide manager; the chevron click
// pins the drawer open (settings.pinned, saved by `haseen bar tray`) and a
// second click collapses it. Theme tokens, haseen popups.
import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import qs.Haseen
import qs.Haseen.Widgets

// StatusNotifier items in a drawer behind a chevron. Collapsed, only the
// chevron shows; clicking it slides the icons out and keeps them there.
// Item clicks: left activates (or opens a menu-only item's menu), middle is
// the secondary action, right opens the item's menu, the wheel scrolls it.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false

    readonly property bool pinned: settings.pinned === true
    // Passive items ask not to be shown (Omarchy's filter too).
    readonly property var items: SystemTray.items.values.filter(item => item.status !== Status.Passive)
    readonly property int count: items.length
    readonly property int cell: Theme.fontSize + Theme.gap * 2
    // 0 collapsed .. 1 open; the reveal animates the drawer's extent.
    property real reveal: pinned ? 1 : 0
    readonly property real iconsExtent: (vertical ? icons.implicitHeight : icons.implicitWidth) * reveal
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"

    property var menuItem: null
    property Item menuAnchor: null
    property bool menuOpen: false

    Behavior on reveal {
        NumberAnimation {
            duration: 300
            easing.type: Easing.OutCubic
        }
    }

    // No tray items: nothing to reveal, so no chevron either.
    visible: count > 0
    implicitWidth: count === 0 ? 0 : vertical ? cell : cell + iconsExtent
    // The bar slot sets the real size; this is only the natural one, and
    // reading the parent here would feed the slot's size back into itself.
    implicitHeight: vertical ? cell + iconsExtent : Config.barThickness

    function togglePinned(): void {
        const next = !pinned;
        if (!next)
            menuOpen = false;
        Config.setRuntime(["plugins", pluginId, "settings", "pinned"], next);
        Quickshell.execDetached([cli, "bar", "tray", next ? "pin" : "unpin", "--no-apply"]);
    }

    function openMenu(item: var, anchor: Item, x: real, y: real): void {
        // Items without a DBus menu model fall back to their own platform
        // menu (the shell runs in QApplication mode for this).
        if (!item.menu) {
            if (item.hasMenu) {
                const p = anchor.mapToItem(QsWindow.window.contentItem, x, y);
                item.display(QsWindow.window, p.x, p.y);
            }
            return;
        }
        // Close first: the menu resets its submenu stack before the opener's
        // root changes to the new item.
        menuOpen = false;
        menuItem = item;
        menuAnchor = anchor;
        menuOpen = true;
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
        visible: root.reveal > 0

        Grid {
            id: icons

            anchors.right: root.vertical ? undefined : parent.right
            anchors.bottom: root.vertical ? parent.bottom : undefined
            anchors.verticalCenter: root.vertical ? undefined : parent.verticalCenter
            columns: root.vertical ? 1 : Math.max(1, root.count)

            Repeater {
                model: root.items

                delegate: TrayItem {
                    extent: root.cell
                    onMenuRequested: (item, anchor, x, y) => root.openMenu(item, anchor, x, y)
                }
            }
        }
    }

    BarButton {
        id: chevron

        objectName: "trayChevron"
        x: root.vertical ? 0 : root.iconsExtent
        y: root.vertical ? root.iconsExtent : 0
        width: root.vertical ? root.width : root.cell
        height: root.vertical ? root.cell : root.height
        padding: 0
        // Points where the icons would appear while collapsed, back at the
        // rest of the bar once pinned open; accent while pinned.
        glyph: root.vertical ? (root.pinned ? "\uf078" : "\uf077") : (root.pinned ? "\uf054" : "\uf053")
        color: root.pinned ? Theme.accent : Theme.barForeground
        onClicked: button => {
            if (button === Qt.LeftButton)
                root.togglePinned();
        }
    }

    TrayMenu {
        trayItem: root.menuItem
        anchorItem: root.menuAnchor
        open: root.menuOpen
        onCloseRequested: root.menuOpen = false
    }
}
