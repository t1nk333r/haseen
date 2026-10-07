import QtQuick
import qs.Haseen

// Thin draggable bar for a 0..1 value, drawn like the audio panel's volume
// rows: the media panel's seek and volume, the display panel's brightness.
// It shows `value` and emits `moved`; the owner writes the value and the bar
// follows it back. While pressed the knob follows the pointer. With `live`
// false (seeking, a DDC monitor) a drag only moves the knob and `moved` fires
// once, on release, so a drag is one write, not one per pixel. `steps` > 0
// snaps the knob to that many even steps (a 3-level keyboard backlight).
// Read-only without `enabled`.
Item {
    id: bar

    property real value: 0
    property bool live: true
    property int steps: 0
    property real wheelStep: 0.05
    property real dragValue: 0
    readonly property bool dragging: mouse.pressed

    readonly property real shown: clamp(dragging ? dragValue : value)

    signal moved(real value)

    function clamp(v: real): real {
        return Math.max(0, Math.min(1, v));
    }

    function snap(v: real): real {
        return steps > 0 ? Math.round(v * steps) / steps : v;
    }

    function drag(x: real): void {
        const next = snap(clamp(x / Math.max(1, width)));
        const changed = next !== dragValue;
        dragValue = next;
        if (live && (changed || !mouse.moving))
            bar.moved(dragValue);
    }

    implicitHeight: Math.round(Theme.fontSize * 0.9)

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.surfaceAlt

        Rectangle {
            width: parent.width * bar.shown
            height: parent.height
            radius: 2
            color: bar.enabled ? Theme.accent : Theme.muted
        }
    }

    Rectangle {
        visible: bar.enabled
        anchors.verticalCenter: parent.verticalCenter
        x: (bar.width - width) * bar.shown
        width: parent.height
        height: width
        radius: width / 2
        color: Theme.foreground
        border.width: Theme.borderWidth
        border.color: Theme.accent
    }

    MouseArea {
        id: mouse

        // False for the press itself, true for the moves after it: a press
        // always sends, a move only when the snapped value changes.
        property bool moving: false

        anchors.fill: parent
        enabled: bar.enabled
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
