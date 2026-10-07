import QtQuick
import qs.Haseen

// Thin draggable bar for a 0..1 value (seek position, player volume), drawn
// like the audio panel's volume rows. It shows `value` and emits `moved`;
// the owner writes the player and the bar follows the player back. With
// `live` false (seeking) a drag only moves the knob and `moved` fires once,
// on release, so a drag is one SetPosition, not one per pixel. Read-only
// without `enabled`.
Item {
    id: bar

    property real value: 0
    property bool live: true
    property real wheelStep: 0.05
    property real dragValue: 0

    readonly property real shown: Math.max(0, Math.min(1, mouse.pressed && !live ? dragValue : value))

    signal moved(real value)

    function clamp(v: real): real {
        return Math.max(0, Math.min(1, v));
    }

    function drag(x: real): void {
        dragValue = clamp(x / Math.max(1, width));
        if (live)
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

        anchors.fill: parent
        enabled: bar.enabled
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: event => bar.drag(event.x)
        onPositionChanged: event => {
            if (pressed)
                bar.drag(event.x);
        }
        onReleased: {
            if (!bar.live)
                bar.moved(bar.dragValue);
        }
        onWheel: event => bar.moved(bar.clamp(bar.value + (event.angleDelta.y > 0 ? bar.wheelStep : -bar.wheelStep)))
    }
}
