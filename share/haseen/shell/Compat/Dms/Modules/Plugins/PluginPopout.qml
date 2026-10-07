import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Haseen as Haseen
import qs.Compat as Compat

// qs.Modules.Plugins.PluginPopout for DankMaterialShell plugins (architecture
// 5.4): the popout a bar widget's popoutContent opens in. The properties
// (pluginId, pluginContent, contentWidth, contentHeight, shouldBeVisible),
// open()/close()/toggle(), the content padding, the height following the
// content and the closePopout/parentPopout hand-over follow DankMaterialShell's
// quickshell/Modules/Plugins/PluginPopout.qml (MIT, Copyright (c) 2025
// Avenge Media LLC).
//
// The window is haseen's, like the Omarchy PopupCard: a popup of the bar
// window, `Theme.gap` off the bar, centred on the widget and kept on the bar,
// drawn as a haseen panel card. The content exists only while the popout is
// open. One popout or panel is open at a time (Compat.Runtime.requestPopout);
// a click outside, Escape or the widget again closes it.
PopupWindow {
    id: root

    property string pluginId: ""
    property Item anchorItem: null
    property Component pluginContent: null
    property real contentWidth: 400
    property real contentHeight: 0
    property bool shouldBeVisible: false

    readonly property real contentPadding: Theme.spacingL
    readonly property real margin: Haseen.Theme.gap
    readonly property string position: Haseen.Config.barPosition
    readonly property bool vertical: position === "left" || position === "right"
    readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
    readonly property var popupScreen: anchorWindow ? anchorWindow.screen : null
    // Room beside the bar on its screen.
    readonly property real roomHeight: popupScreen ? popupScreen.height - (vertical ? 0 : anchorWindow.height) - margin * 2 : Infinity
    readonly property Item loadedContent: content.item

    signal opened
    signal popoutClosed

    function open(): void {
        if (shouldBeVisible || anchorWindow === null || !Compat.Runtime.requestPopout(root))
            return;
        shouldBeVisible = true;
        opened();
    }

    function close(): void {
        if (!shouldBeVisible)
            return;
        shouldBeVisible = false;
        Compat.Runtime.releasePopout(root);
        popoutClosed();
    }

    function toggle(): void {
        if (shouldBeVisible)
            close();
        else
            open();
    }

    visible: shouldBeVisible
    color: "transparent"
    implicitWidth: Math.max(1, Math.round(contentWidth))
    implicitHeight: Math.max(1, Math.round(Math.min(content.item ? content.item.implicitHeight + contentPadding * 2 : contentHeight, roomHeight)))

    onShouldBeVisibleChanged: {
        if (shouldBeVisible)
            Qt.callLater(() => scope.forceActiveFocus());
    }

    Component.onDestruction: Compat.Runtime.releasePopout(root)

    anchor {
        id: popupAnchor

        window: root.anchorWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
            const target = root.anchorItem;
            const window = root.anchorWindow;
            if (!target || !window)
                return;
            const w = root.implicitWidth, h = root.implicitHeight, m = root.margin;
            const centre = window.contentItem.mapFromItem(target, target.width / 2, target.height / 2);
            let x, y;
            if (root.vertical) {
                x = root.position === "left" ? window.width + m : -w - m;
                y = Math.max(m, Math.min(centre.y - h / 2, window.height - h - m));
            } else {
                x = Math.max(m, Math.min(centre.x - w / 2, window.width - w - m));
                y = root.position === "bottom" ? -h - m : window.height + m;
            }
            popupAnchor.rect.x = Math.round(x);
            popupAnchor.rect.y = Math.round(y);
        }
    }

    HyprlandFocusGrab {
        active: root.shouldBeVisible
        windows: root.anchorWindow ? [root, root.anchorWindow] : [root]
        onCleared: root.close()
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.outline
        border.width: Haseen.Theme.borderWidth
        clip: true

        FocusScope {
            id: scope

            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: event => {
                root.close();
                event.accepted = true;
            }

            Loader {
                id: content

                // DMS's loader carries the id; plugin content reads it.
                property string pluginId: root.pluginId

                x: root.contentPadding
                y: root.contentPadding
                width: parent.width - root.contentPadding * 2
                active: root.shouldBeVisible
                sourceComponent: root.pluginContent

                onLoaded: {
                    if ("closePopout" in item)
                        item.closePopout = () => root.close();
                    if ("parentPopout" in item)
                        item.parentPopout = root;
                }
            }
        }
    }
}
