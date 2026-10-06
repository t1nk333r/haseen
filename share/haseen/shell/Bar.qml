import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// One bar per screen, on the edge shell.json `bar.position` names. Three
// sections of bar-widget plugins (left/center/right, top to bottom when the
// bar is vertical). With the screen frame on, the bar is the frame's thick
// edge (Frame.qml draws the rest); without it, a hairline marks the inner edge.
//
// Double-clicking empty bar space asks for transparency (plan 015, after
// Omarchy's shell/plugins/bar/Bar.qml toggleTransparency, MIT,
// Copyright (c) David Heinemeier Hansson). `transparent` comes from FrameTextColor:
// it turns true only once a legible text colour for the wallpaper is known.
PanelWindow {
    id: bar

    property bool hidden: false
    property bool transparent: false
    readonly property string position: Config.barPosition
    readonly property bool vertical: Config.barVertical
    // A hidden bar leaves a frame-thick strip so the frame stays closed.
    readonly property int thickness: !hidden ? Config.barThickness : Config.frameEnabled ? Config.frameThickness : 0
    // With the frame on, the bar reaches 1 px under the frame strips at both
    // of its ends (the seam note in Frame.qml).
    readonly property int overlap: Config.frameEnabled ? 1 : 0

    signal transparencyToggleRequested
    // A press on a bar widget, as PanelPlacement.js's opener.
    signal widgetPressed(var opener)

    // The bar spans its edge and the popups share its origin
    // (PanelPlacement.place), so the slot's centre in this window's
    // coordinates, less the overlap, is where along the edge a panel it
    // opens belongs.
    function reportPress(slot: Item): void {
        const c = slot.mapToItem(null, slot.width / 2, slot.height / 2);
        bar.widgetPressed({
            screen: bar.screen,
            position: bar.position,
            centre: (bar.vertical ? c.y : c.x) - overlap,
            extent: (bar.vertical ? bar.height : bar.width) - 2 * overlap,
            time: Date.now()
        });
    }

    visible: thickness > 0
    anchors {
        top: bar.position !== "bottom"
        bottom: bar.position !== "top"
        left: bar.position !== "right"
        right: bar.position !== "left"
    }
    margins {
        top: bar.vertical ? -bar.overlap : 0
        bottom: bar.vertical ? -bar.overlap : 0
        left: bar.vertical ? 0 : -bar.overlap
        right: bar.vertical ? 0 : -bar.overlap
    }
    implicitWidth: thickness
    implicitHeight: thickness
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: thickness
    color: transparent ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) : Theme.background
    WlrLayershell.namespace: "haseen-bar"
    // Quickshell picks an opaque buffer when the first colour is opaque, and
    // transparency would then render black. Ask for alpha up front.
    surfaceFormat.opaque: false
    WlrLayershell.layer: WlrLayer.Top

    // The owner's frame cross-fades with the bar over 420 ms (t1nk33r.screen-frame).
    Behavior on color {
        ColorAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }

    // Below the sections: only clicks on empty bar space reach it.
    MouseArea {
        anchors.fill: parent
        enabled: !bar.hidden
        acceptedButtons: Qt.LeftButton
        onDoubleClicked: bar.transparencyToggleRequested()
    }

    Item {
        anchors.fill: parent
        anchors.leftMargin: bar.vertical ? 0 : Theme.gap + bar.overlap
        anchors.rightMargin: bar.vertical ? 0 : Theme.gap + bar.overlap
        anchors.topMargin: bar.vertical ? Theme.gap + bar.overlap : 0
        anchors.bottomMargin: bar.vertical ? Theme.gap + bar.overlap : 0
        visible: !bar.hidden

        // Each section is anchored on both axes, the one across the bar
        // being a no-op (the section spans it). Anchoring only the axis along
        // the bar left a section at its old offset after a live switch
        // between a vertical and a horizontal bar: removing an anchor keeps
        // the position it set, so the right section sat outside a 28 px bar.
        BarSection {
            anchors.left: parent.left
            anchors.top: parent.top
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: Config.section("left")
            screen: bar.screen
            onWidgetPressed: slot => bar.reportPress(slot)
        }

        BarSection {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: Config.section("center")
            screen: bar.screen
            onWidgetPressed: slot => bar.reportPress(slot)
        }

        BarSection {
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: bar.vertical ? parent.width : implicitWidth
            height: bar.vertical ? implicitHeight : parent.height
            vertical: bar.vertical
            ids: Config.section("right")
            screen: bar.screen
            onWidgetPressed: slot => bar.reportPress(slot)
        }
    }

    // Hairline on the inner edge, only when no frame continues the bar.
    Rectangle {
        visible: !Config.frameEnabled && !bar.transparent && !bar.hidden
        x: bar.position === "left" ? parent.width - width : 0
        y: bar.position === "top" ? parent.height - height : 0
        width: bar.vertical ? Theme.borderWidth : parent.width
        height: bar.vertical ? parent.height : Theme.borderWidth
        color: Theme.border
    }
}
