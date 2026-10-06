// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml (tray menu popup).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file, a plain PopupWindow with a Hyprland focus grab instead of
// Omarchy's PopupCard/bar popout coordinator; theme tokens for every colour.
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Hyprland
import qs.Haseen

// A tray item's DBus menu rendered in-shell. Submenus drill down inside the
// same card: each level keeps its own live QsMenuOpener, because a child
// entry is owned by its parent opener's model (collapsing to one opener would
// destroy the entry being shown). Clicking outside or Escape closes it.
PopupWindow {
    id: root

    property var trayItem: null
    property Item anchorItem: null
    property bool open: false

    signal closeRequested

    property var submenuStack: []
    readonly property int submenuDepth: submenuStack.length
    readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
    readonly property var currentChildren: submenuDepth > 0 ? submenuStack[submenuDepth - 1].opener.children : rootOpener.children
    // Changing level rebuilds the rows under a cursor that has not moved;
    // ignore row clicks for a beat so a double click cannot fire the entry
    // that took the spot.
    property bool settling: false
    readonly property int rowHeight: Theme.fontSize + Theme.gap * 2
    readonly property int menuWidth: Theme.fontSize * 18
    readonly property int maxHeight: Theme.fontSize * 30
    readonly property int headerHeight: header.visible ? header.implicitHeight : 0
    readonly property string pos: Config.barPosition
    readonly property int away: pos === "bottom" ? Edges.Top : pos === "left" ? Edges.Right : pos === "right" ? Edges.Left : Edges.Bottom

    function reset(): void {
        settling = false;
        settleTimer.stop();
        flick.contentY = 0;
        // Clear the reactive stack first, then destroy deepest first: an
        // inner opener's entry belongs to its parent's children model.
        const openers = submenuStack;
        submenuStack = [];
        for (let i = openers.length - 1; i >= 0; i--)
            openers[i].opener.destroy();
    }

    function settle(): void {
        settling = true;
        settleTimer.restart();
    }

    function enterSubmenu(entry: var, title: string): void {
        const opener = openerComponent.createObject(root, {
            menu: entry
        });
        if (!opener)
            return;
        const stack = submenuStack.slice();
        stack.push({
            opener: opener,
            title: title
        });
        submenuStack = stack;
        settle();
    }

    function leaveSubmenu(): void {
        if (submenuStack.length === 0)
            return;
        const stack = submenuStack.slice();
        const top = stack.pop();
        submenuStack = stack;
        top.opener.destroy();
        settle();
    }

    visible: open && anchorItem !== null
    onVisibleChanged: if (!visible)
        reset()
    color: "transparent"
    anchor.item: anchorItem
    anchor.edges: away
    anchor.gravity: away
    anchor.margins.top: pos === "top" ? Theme.gap : 0
    anchor.margins.bottom: pos === "bottom" ? Theme.gap : 0
    anchor.margins.left: pos === "left" ? Theme.gap : 0
    anchor.margins.right: pos === "right" ? Theme.gap : 0
    implicitWidth: menuWidth + Theme.gap * 2
    implicitHeight: Math.max(rowHeight, Math.min(maxHeight, headerHeight + column.implicitHeight)) + Theme.gap * 2

    Component {
        id: openerComponent

        QsMenuOpener {}
    }

    QsMenuOpener {
        id: rootOpener

        menu: root.trayItem ? root.trayItem.menu : null
    }

    // haseen:ui-timeout
    Timer {
        id: settleTimer

        interval: 250
        repeat: false
        onTriggered: root.settling = false
    }

    HyprlandFocusGrab {
        windows: [root]
        active: root.visible
        onCleared: root.closeRequested()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surface
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.border
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        Column {
            id: layout

            anchors.fill: parent
            anchors.margins: Theme.gap

            // Below the root level: names where we are and walks back out.
            Column {
                id: header

                visible: root.submenuDepth > 0
                width: layout.width

                MenuRow {
                    width: header.width
                    height: root.rowHeight
                    lead: "\u2039"
                    label: root.currentTitle
                    onActivated: {
                        if (root.settling)
                            return;
                        flick.contentY = 0;
                        root.leaveSubmenu();
                    }
                }

                MenuSeparator {
                    width: header.width
                }
            }

            Flickable {
                id: flick

                width: layout.width
                height: layout.height - root.headerHeight
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.VerticalFlick
                interactive: contentHeight > height

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                }

                Column {
                    id: column

                    width: flick.width

                    Repeater {
                        model: root.currentChildren

                        delegate: Item {
                            id: entry

                            required property var modelData
                            required property int index

                            readonly property string rowText: String(modelData.text || "")
                            readonly property string itemTitle: root.trayItem ? String(root.trayItem.title || root.trayItem.id || "") : ""
                            // Only the root menu: some apps repeat their name
                            // as a first submenu entry or lead with separators.
                            readonly property bool atRoot: root.submenuDepth === 0
                            readonly property bool hiddenRow: atRoot && ((index === 0 && modelData.hasChildren && rowText.toLowerCase() === itemTitle.toLowerCase()) || (modelData.isSeparator && index <= 1))

                            visible: !hiddenRow
                            width: column.width
                            implicitHeight: hiddenRow ? 0 : modelData.isSeparator ? sep.implicitHeight : root.rowHeight

                            MenuSeparator {
                                id: sep

                                width: parent.width
                                visible: entry.modelData.isSeparator
                            }

                            MenuRow {
                                anchors.fill: parent
                                visible: !entry.modelData.isSeparator
                                enabled: entry.modelData.enabled
                                lead: entry.modelData.buttonType !== QsMenuButtonType.None && entry.modelData.checkState === Qt.Checked ? "\uf00c" : ""
                                icon: String(entry.modelData.icon || "")
                                label: entry.rowText
                                trail: entry.modelData.hasChildren ? "\u203a" : ""
                                onActivated: {
                                    if (root.settling)
                                        return;
                                    if (entry.modelData.hasChildren) {
                                        // Before the model swap destroys this delegate.
                                        flick.contentY = 0;
                                        root.enterSubmenu(entry.modelData, entry.rowText);
                                    } else {
                                        entry.modelData.triggered();
                                        root.closeRequested();
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
