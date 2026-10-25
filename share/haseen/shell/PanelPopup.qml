import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "PanelPlacement.js" as Placement

// The popup window for one open panel plugin: a PanelSurface (Omarchy's
// panel card, plan 115) on the bar edge, centred under (or beside) the bar widget whose click opened it, or
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
    // Omarchy's panels sit gapsOut off the bar and off the screen's edges
    // (KeyboardPanel.qml:44,51): half of Hyprland's gaps_out (Theme.gapsOut).
    readonly property var placement: Placement.place(Config.barPosition, opener, implicitWidth, implicitHeight, Theme.gapsOut, Plugins.settingsFor(pluginId).placement)

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
        // Omarchy's panel card fades in over 140 ms (KeyboardPanel.qml:400-403),
        // none while Hyprland's animations are off. The popup is destroyed on
        // close, so there is no fade out. An overlay panel draws its own card.
        opacity: popup.overlay ? 1 : 0
        Component.onCompleted: if (!popup.overlay) opacity = 1

        Behavior on opacity {
            enabled: !popup.overlay
            NumberAnimation {
                duration: Theme.duration(140)
                easing.type: Easing.OutCubic
            }
        }
        // Arabic and any right-to-left language mirror a native panel's
        // layout (plan 109): rows run from the right, chevrons and sliders
        // follow. A panel keeps unmirrored what must not flip (media
        // transport, a seek bar) by setting LayoutMirroring.enabled false on
        // that item. Omarchy and DMS panels keep the layout they were written
        // for; one that reads Commons.I18n.rightToLeft can mirror itself.
        LayoutMirroring.enabled: I18n.rightToLeft && (Plugins.registry[popup.pluginId] || {}).compat === ""
        LayoutMirroring.childrenInherit: true

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
        property: "bordered"
        value: false
        when: popup.overlay
    }
}
