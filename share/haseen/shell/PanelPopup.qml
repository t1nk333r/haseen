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
//
// Placement "overlay" (haseen.menu, after Omarchy's menu) gives the panel the
// whole screen instead: an overlay layer that ignores exclusive zones, no
// PanelSurface chrome, no compositor fade (the `haseen-overlay` layer rule in
// default/hypr/windowrules.lua). The panel draws its own scrim and card,
// closes on a click on the scrim, and handles Escape itself. The window never
// changes size while open, so the card never jumps when its rows change.
PanelWindow {
    id: popup

    required property string pluginId
    // The bar press that opened the panel (PanelPlacement.opener), or null.
    property var opener: null
    readonly property bool overlay: Plugins.settingsFor(pluginId).placement === "overlay"
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
    // Normal with no zone of its own (exclusiveZone stays 0); not set here, as
    // setting exclusiveZone switches the mode back to Normal.
    exclusionMode: popup.overlay ? ExclusionMode.Ignore : ExclusionMode.Normal
    implicitWidth: Math.max(surface.implicitWidth, 1)
    implicitHeight: Math.max(surface.implicitHeight, 1)
    color: "transparent"
    WlrLayershell.namespace: popup.overlay ? "haseen-overlay" : "haseen-panel"
    WlrLayershell.layer: popup.overlay ? WlrLayer.Overlay : WlrLayer.Top
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
    // before item delivery. An overlay panel gives Escape a first meaning of
    // its own (the menu clears its search), so it handles the key itself.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        enabled: !popup.overlay
        onActivated: popup.closeRequested()
    }

    PanelSurface {
        id: surface

        focus: true

        PluginSlot {
            id: slot

            pluginId: popup.pluginId
            kind: "panel"
            screen: popup.screen
        }
    }

    // Overlay: the panel fills the window and the surface draws nothing.
    Binding {
        target: slot
        property: "width"
        value: popup.width
        when: popup.overlay
    }
    Binding {
        target: slot
        property: "height"
        value: popup.height
        when: popup.overlay
    }
    Binding {
        target: surface
        property: "padding"
        value: 0
        when: popup.overlay
    }
    Binding {
        target: surface
        property: "color"
        value: "transparent"
        when: popup.overlay
    }
    Binding {
        target: surface
        property: "border.width"
        value: 0
        when: popup.overlay
    }
}
