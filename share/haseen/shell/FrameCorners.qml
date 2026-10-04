import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// The two inner corners on one side (top or bottom) of the window area. An
// exclusive zone of 0 makes Hyprland place the row inside the area the bar
// and the strips leave free, whatever order they were arranged in, so the
// corners always meet the frame's inner edge. Empty mask: no input.
PanelWindow {
    id: root

    property bool atBottom: false
    property int radius: 12
    property color fill: Theme.background

    anchors {
        top: !root.atBottom
        bottom: root.atBottom
        left: true
        right: true
    }
    implicitHeight: radius
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: 0
    mask: Region {}
    color: "transparent"
    WlrLayershell.namespace: "haseen-frame-corners"
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    FrameCorner {
        anchors.left: parent.left
        radius: root.radius
        fill: root.fill
        atBottom: root.atBottom
    }

    FrameCorner {
        anchors.right: parent.right
        radius: root.radius
        fill: root.fill
        atBottom: root.atBottom
        atRight: true
    }
}
