import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// One thin bar per screen. Three sections of bar-widget plugins from
// shell.json `bar.left|center|right`; a hairline border on the inner edge.
PanelWindow {
    id: bar

    required property var modelData
    readonly property bool atBottom: Config.barPosition === "bottom"

    screen: modelData
    anchors {
        top: !bar.atBottom
        bottom: bar.atBottom
        left: true
        right: true
    }
    implicitHeight: Config.barHeight
    color: Theme.background
    WlrLayershell.namespace: "haseen-bar"
    WlrLayershell.layer: WlrLayer.Top

    Item {
        anchors.fill: parent
        anchors.leftMargin: Theme.gap
        anchors.rightMargin: Theme.gap

        BarSection {
            anchors.left: parent.left
            height: parent.height
            ids: Config.section("left")
            screen: bar.modelData
        }

        BarSection {
            anchors.horizontalCenter: parent.horizontalCenter
            height: parent.height
            ids: Config.section("center")
            screen: bar.modelData
        }

        BarSection {
            anchors.right: parent.right
            height: parent.height
            ids: Config.section("right")
            screen: bar.modelData
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: bar.atBottom ? parent.top : undefined
        anchors.bottom: bar.atBottom ? undefined : parent.bottom
        height: Theme.borderWidth
        color: Theme.border
    }
}
