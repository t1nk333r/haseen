import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "PanelPlacement.js" as Placement

// The popup window for one open panel plugin: a PanelSurface on the bar
// edge, centred under (or beside) the bar widget whose click opened it, or
// centred on the bar edge when a key or the CLI opened it
// (PanelPlacement.js). Escape or a click outside closes it.
PanelWindow {
    id: popup

    required property string pluginId
    // The bar press that opened the panel (PanelPlacement.opener), or null.
    property var opener: null
    readonly property var placement: Placement.place(Config.barPosition, opener, implicitWidth, implicitHeight, Theme.gap)

    signal closeRequested

    anchors {
        top: popup.placement.top
        bottom: popup.placement.bottom
        left: popup.placement.left
        right: popup.placement.right
    }
    margins {
        top: popup.placement.marginTop
        bottom: popup.placement.marginBottom
        left: popup.placement.marginLeft
        right: popup.placement.marginRight
    }
    exclusiveZone: 0
    implicitWidth: Math.max(surface.implicitWidth, 1)
    implicitHeight: Math.max(surface.implicitHeight, 1)
    color: "transparent"
    WlrLayershell.namespace: "haseen-panel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.closeRequested()
    }

    PanelSurface {
        id: surface

        focus: true
        Keys.onEscapePressed: popup.closeRequested()

        PluginSlot {
            pluginId: popup.pluginId
            kind: "panel"
            screen: popup.screen
        }
    }
}
