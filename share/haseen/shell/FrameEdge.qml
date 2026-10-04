import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// One thin frame strip along a screen edge: draws the frame colour, reserves
// its thickness, takes no input.
PanelWindow {
    id: root

    required property string edge
    property int thickness: 6
    property color fill: Theme.background

    anchors {
        top: root.edge !== "bottom"
        bottom: root.edge !== "top"
        left: root.edge !== "right"
        right: root.edge !== "left"
    }
    implicitWidth: thickness
    implicitHeight: thickness
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: thickness
    mask: Region {}
    // Alpha up front, or the transparent bar's frame would render black (Bar.qml).
    surfaceFormat.opaque: false
    color: fill
    WlrLayershell.namespace: "haseen-frame"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Same cross-fade as the bar (Bar.qml).
    Behavior on color {
        ColorAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }
}
