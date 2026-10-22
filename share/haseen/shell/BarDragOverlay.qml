import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// What a drag on the bar shows (plan 112), after Omarchy's DragGhostPanel and
// BarMoveGhostPanel (shell/plugins/bar/Bar.qml, v4.5.0-rc1, MIT, Copyright
// (c) David Heinemeier Hansson): a dragged widget's ghost under the pointer,
// picked up where it was pressed, or the edge the bar would move to. A window
// over the whole screen that takes no input (an empty mask), so the pointer
// stays with the bar's own grab; Bar.qml creates it as a drag starts and
// frees it as the drag ends.
PanelWindow {
    id: overlay

    // The bar's strip (BarStrip.qml): the drag's state.
    required property var strip
    readonly property bool ghostShown: strip.dragId !== "" && strip.dragSlot !== null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    surfaceFormat.opaque: false
    mask: Region {}
    WlrLayershell.namespace: "haseen-bar-drag"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The widget as it was in the bar; its outline until its picture is
    // taken, and if it never is.
    Item {
        visible: overlay.ghostShown
        x: Math.round(overlay.strip.dragScreenAt.x - overlay.strip.dragGrip.x)
        y: Math.round(overlay.strip.dragScreenAt.y - overlay.strip.dragGrip.y)
        width: overlay.strip.dragSlot ? overlay.strip.dragSlot.width : 0
        height: overlay.strip.dragSlot ? overlay.strip.dragSlot.height : 0

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.85)
            border.color: Theme.accent
            border.width: Theme.borderWidth
        }

        Image {
            anchors.fill: parent
            source: overlay.strip.ghostUrl
            fillMode: Image.Stretch
            opacity: 0.9
        }
    }

    // The four edges, the one the bar would go to drawn as a bar.
    Repeater {
        model: ["top", "bottom", "left", "right"]

        delegate: Rectangle {
            required property string modelData
            readonly property bool side: modelData === "left" || modelData === "right"
            // As thick as the bar would be there (Config.barThickness).
            readonly property int thickness: side ? Math.max(Config.barHeight, Theme.fontSize * 3) : Config.barHeight

            visible: overlay.strip.barMoving && overlay.strip.barEdge === modelData
            x: modelData === "right" ? overlay.width - width : 0
            y: modelData === "bottom" ? overlay.height - height : 0
            width: side ? thickness : overlay.width
            height: side ? overlay.height : thickness
            color: Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0.7)
            border.color: Theme.accent
            border.width: Theme.borderWidth
        }
    }
}
