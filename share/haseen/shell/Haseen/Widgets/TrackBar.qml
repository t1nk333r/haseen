// Adapted from Omarchy shell/Ui/PanelSlider.qml (track, fill and knob).
// MIT, Copyright (c) David Heinemeier Hansson.
import QtQuick
import qs.Haseen

// Thin draggable bar for a 0..1 value, drawn as Omarchy's PanelSlider (plan
// 115): the media panel's seek and volume, the display panel's brightness.
// It shows `value` and emits `moved`; the owner writes the value and the bar
// follows it back. While pressed the knob follows the pointer. With `live`
// false (seeking, a DDC monitor) a drag only moves the knob and `moved` fires
// once, on release, so a drag is one write, not one per pixel. `steps` > 0
// snaps the knob to that many even steps (a 3-level keyboard backlight).
// Read-only without `enabled`. Under LayoutMirroring (a right-to-left
// interface, plan 109) the bar fills from the right; a seek bar that must
// run with time sets LayoutMirroring.enabled false on itself.
Item {
    id: bar

    property real value: 0
    property bool live: true
    property int steps: 0
    property real wheelStep: 0.05
    property real dragValue: 0
    readonly property bool dragging: mouse.pressed

    readonly property real shown: clamp(dragging ? dragValue : value)
    readonly property bool mirrored: LayoutMirroring.enabled

    signal moved(real value)

    function clamp(v: real): real {
        return Math.max(0, Math.min(1, v));
    }

    function snap(v: real): real {
        return steps > 0 ? Math.round(v * steps) / steps : v;
    }

    function drag(x: real): void {
        const fraction = x / Math.max(1, width);
        const next = snap(clamp(mirrored ? 1 - fraction : fraction));
        const changed = next !== dragValue;
        dragValue = next;
        if (live && (changed || !mouse.moving))
            bar.moved(dragValue);
    }

    // PanelSlider.qml:18-19,39: a 4 px track, a 14 px knob, 22 px tall.
    readonly property int trackHeight: Math.max(4, Math.round(Theme.spacing.controlHeight * 0.11))
    readonly property int knobSize: Math.max(14, Math.round(Theme.spacing.controlHeight * 0.38))
    readonly property bool hot: mouse.containsMouse || dragging

    implicitHeight: Math.max(Theme.space(22), knobSize + Theme.spacing.md)

    // The track is the selected fill and the filled part the foreground
    // (PanelSlider.qml:14-15,51-74); a read-only bar fills in muted.
    Rectangle {
        id: track

        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: bar.trackHeight
        radius: height / 2
        color: Theme.selectedFill

        Rectangle {
            x: bar.mirrored ? parent.width - width : 0
            width: parent.width * bar.shown
            height: parent.height
            radius: parent.radius
            color: bar.enabled ? Theme.foreground : Theme.muted
        }
    }

    // A foreground knob ringed in the card's background, 15 % larger while
    // hovered or dragged (PanelSlider.qml:90-109).
    Rectangle {
        visible: bar.enabled
        anchors.verticalCenter: parent.verticalCenter
        x: Math.max(0, Math.min(bar.width - width, bar.width * (bar.mirrored ? 1 - bar.shown : bar.shown) - width / 2))
        width: bar.knobSize
        height: width
        radius: width / 2
        color: Theme.foreground
        border.width: Math.max(1, Theme.space(2))
        border.color: Theme.popups.background
        scale: bar.hot ? 1.15 : 1.0

        Behavior on scale {
            NumberAnimation {
                duration: Theme.duration(110)
                easing.type: Easing.OutCubic
            }
        }
    }

    MouseArea {
        id: mouse

        // False for the press itself, true for the moves after it: a press
        // always sends, a move only when the snapped value changes.
        property bool moving: false

        anchors.fill: parent
        enabled: bar.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: event => {
            moving = false;
            bar.drag(event.x);
            moving = true;
        }
        onPositionChanged: event => {
            if (pressed)
                bar.drag(event.x);
        }
        onReleased: {
            if (!bar.live)
                bar.moved(bar.dragValue);
        }
        // With steps, one notch is at least one step, or snapping would undo it.
        onWheel: event => {
            const step = bar.steps > 0 ? Math.max(bar.wheelStep, 1 / bar.steps) : bar.wheelStep;
            bar.moved(bar.snap(bar.clamp(bar.value + (event.angleDelta.y > 0 ? step : -step))));
        }
    }
}
