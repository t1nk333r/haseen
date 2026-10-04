import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets

// The popup window for one open panel plugin: a PanelSurface centred on the
// bar edge of the focused screen. Escape or a click outside closes it.
PanelWindow {
    id: popup

    required property string pluginId
    readonly property bool atBottom: Config.barPosition === "bottom"

    signal closeRequested

    anchors {
        top: !popup.atBottom
        bottom: popup.atBottom
    }
    margins {
        top: Theme.gap
        bottom: Theme.gap
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
