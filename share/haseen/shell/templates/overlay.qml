import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// @ID@: overlay. A full-screen layer surface this plugin owns (OSD, lock…).
// Keep it hidden until needed so it costs nothing at idle.
Scope {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    property bool shown: false

    PanelWindow {
        visible: root.shown
        screen: root.screen
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "@ID@"
        WlrLayershell.layer: WlrLayer.Overlay

        Text {
            anchors.centerIn: parent
            text: root.pluginId
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize * 2
        }
    }
}
