import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// The two inner corners on one side (top or bottom) of the window area. An
// exclusive zone of 0 makes Hyprland place the row inside the area the bar
// and the strips leave free, whatever order they were arranged in, so the
// corners always meet the frame's inner edge. The row reaches 1 px further
// on its three outer sides, under the bar and the strips, and each corner
// fills that bleed (seams: Frame.qml). Empty mask: no input.
PanelWindow {
    id: root

    property bool atBottom: false
    property int radius: 12
    property color fill: Theme.background
    readonly property int bleed: 1

    anchors {
        top: !root.atBottom
        bottom: root.atBottom
        left: true
        right: true
    }
    margins {
        top: root.atBottom ? 0 : -root.bleed
        bottom: root.atBottom ? -root.bleed : 0
        left: -root.bleed
        right: -root.bleed
    }
    implicitHeight: radius + bleed
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
        bleed: root.bleed
        fill: root.fill
        atBottom: root.atBottom
    }

    FrameCorner {
        anchors.right: parent.right
        radius: root.radius
        bleed: root.bleed
        fill: root.fill
        atBottom: root.atBottom
        atRight: true
    }
}
