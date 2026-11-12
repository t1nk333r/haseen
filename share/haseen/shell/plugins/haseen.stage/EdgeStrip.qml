import QtQuick
import Quickshell
import Quickshell.Wayland

// The hot edge of one screen (plan 163): a strip two pixels wide along the
// chosen edge, transparent, with no exclusive zone. It draws nothing and
// takes the pointer only on itself, and only while the stage may open
// (Service.quietReason). The pointer has to rest against it for the dwell,
// with no button held, before it asks the service to open; passing by does
// nothing. A file of its own, loaded by URL, so Service.qml compiles where
// no PanelWindow backend exists (the offscreen engine of tests).
//
// Exclusive zone 0 (the Normal mode with no zone of its own) asks the
// compositor to keep the strip off any surface that reserves an edge: with
// the bar on the same edge the strip runs along the bar's inner side, and
// with the bar on top it starts below the bar, so it never covers a pixel of
// the bar and never takes a click meant for it (decision in plan 163). The
// Top layer puts it under a fullscreen window, which Hyprland draws above
// that layer, as a second guard beside the fullscreen rule.
PanelWindow {
    id: strip

    // Set by the service's loader.
    property var service: null
    property var edgeScreen: null

    readonly property string edge: service ? service.cfg.edge : "left"
    readonly property string quiet: service ? service.quietReason(edgeScreen, 0) : "off"
    readonly property bool armed: quiet === ""

    screen: edgeScreen
    anchors {
        top: true
        bottom: true
        left: edge === "left"
        right: edge === "right"
    }
    implicitWidth: 2
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    surfaceFormat.opaque: false
    // While the stage may not open the strip lets every click through.
    mask: Region {
        width: strip.armed ? strip.width : 0
        height: strip.armed ? strip.height : 0
    }
    WlrLayershell.namespace: "haseen-stage-edge"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    onArmedChanged: if (!armed)
        dwell.stop()

    MouseArea {
        id: area

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        // A press at the edge is not a push: a window or a file is being
        // dragged there, or a click was meant for what lies under it.
        onPressed: dwell.stop()
        onContainsMouseChanged: {
            if (containsMouse && pressedButtons === Qt.NoButton && strip.armed)
                dwell.restart();
            else
                dwell.stop();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: dwell

        interval: strip.service ? strip.service.cfg.dwell : 200
        repeat: false
        onTriggered: {
            if (strip.service && area.containsMouse && area.pressedButtons === Qt.NoButton)
                strip.service.edgeOpen(strip.edgeScreen, area.pressedButtons);
        }
    }
}
