import QtQuick
import Quickshell
import Quickshell.Wayland

// The covers during a background change (plan 161), one per screen. Each is
// a layer surface on the Bottom layer: above swaybg, which draws on
// Background, and below every window. It takes no input, reserves no space
// and exists only while the change runs; the Transition service creates
// them through a LazyLoader and frees them, and their textures, when it
// ends. The default windowrules.lua turns Hyprland's layer animation off for
// their namespace, so a cover is whole on its first frame. What a cover
// draws and when it counts as covered is TransitionCover.qml.
//
// A file of its own, loaded by URL, so Transition.qml compiles where no
// PanelWindow backend exists (the offscreen engine of the tests).
Variants {
    id: covers

    // The haseen.background Transition service, set by its loader.
    property var service: null

    model: Quickshell.screens

    PanelWindow {
        id: win

        required property var modelData

        screen: modelData
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "haseen-background-transition"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        TransitionCover {
            anchors.fill: parent
            service: covers.service
            pixelRatio: win.devicePixelRatio > 0 ? win.devicePixelRatio : 1
        }
    }
}
