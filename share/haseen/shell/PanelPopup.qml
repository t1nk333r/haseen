import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "PanelPlacement.js" as Placement

// The popup window for one open panel plugin: a PanelSurface on the bar
// edge, centred under (or beside) the bar widget whose click opened it, or
// centred on the bar edge when a key or the CLI opened it, or centred on the
// screen when the panel's `placement` setting is "center" (PanelPlacement.js). Escape or a click outside closes it.
PanelWindow {
    id: popup

    required property string pluginId
    // The bar press that opened the panel (PanelPlacement.opener), or null.
    property var opener: null
    readonly property var placement: Placement.place(Config.barPosition, opener, implicitWidth, implicitHeight, Theme.gap, Plugins.settingsFor(pluginId).placement)

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
    // The keyboard is taken when the panel appears and then held on demand,
    // as Omarchy's KeyboardPanel does. Exclusive first, so Escape and Enter
    // reach the panel however it was opened: plain OnDemand only gave it the
    // keyboard after a click inside it. OnDemand once the window is active, so
    // the compositor goes back to normal pointer handling and a click outside
    // clears the focus grab below and closes the panel. Under Exclusive that
    // click never cleared the grab. The panel keeps the keyboard because it
    // already has it.
    property bool focusPrimed: false
    WlrLayershell.keyboardFocus: focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    Connections {
        target: surface.Window

        function onActiveChanged(): void {
            if (surface.Window.active)
                popup.focusPrimed = true;
        }
    }

    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible
        onCleared: popup.closeRequested()
    }

    // Escape closes the panel whatever item inside it has focus. A key handler
    // on the surface only saw the key when nothing below it took the press:
    // in the theme and background pickers the focused grid cell's press never
    // reached it (releases did), so Escape did nothing. A window shortcut runs
    // before item delivery.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: popup.closeRequested()
    }

    PanelSurface {
        id: surface

        focus: true

        PluginSlot {
            pluginId: popup.pluginId
            kind: "panel"
            screen: popup.screen
        }
    }
}
