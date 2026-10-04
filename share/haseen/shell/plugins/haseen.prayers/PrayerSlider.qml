import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// Drag or click; liveValue follows the pointer, released(value) fires once
// on release so one drag is one shell.json write. The wheel steps it.
Item {
    id: root

    property real minimum: 0
    property real maximum: 100
    property real step: 1
    property bool integer: true
    property real value: 0
    readonly property real liveValue: drag.pressed ? drag.dragValue : value

    signal released(real next)

    implicitHeight: Math.round(Theme.fontSize * 1.4)
    height: implicitHeight

    function snap(v: real): real {
        let n = Math.round((v - minimum) / step) * step + minimum;
        n = Math.max(minimum, Math.min(maximum, n));
        return integer ? Math.round(n) : n;
    }

    function fraction(v: real): real {
        return maximum > minimum ? (v - minimum) / (maximum - minimum) : 0;
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 4
        radius: 2
        color: Theme.border

        Rectangle {
            width: parent.width * root.fraction(root.liveValue)
            height: parent.height
            radius: 2
            color: Theme.accent
        }
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: (root.width - width) * root.fraction(root.liveValue)
        width: Math.round(Theme.fontSize * 0.9)
        height: width
        radius: width / 2
        color: Theme.foreground
        border.width: Theme.borderWidth
        border.color: Theme.accent
    }

    MouseArea {
        id: drag

        property real dragValue: root.value

        function valueAt(x: real): real {
            return root.snap(root.minimum + Math.max(0, Math.min(1, x / Math.max(1, width))) * (root.maximum - root.minimum));
        }

        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: event => dragValue = valueAt(event.x)
        onPositionChanged: event => dragValue = valueAt(event.x)
        onReleased: event => {
            const v = valueAt(event.x);
            if (v !== root.value)
                root.released(v);
        }
        onWheel: event => {
            const v = root.snap(root.value + (event.angleDelta.y > 0 ? root.step : -root.step));
            if (v !== root.value)
                root.released(v);
        }
    }
}
