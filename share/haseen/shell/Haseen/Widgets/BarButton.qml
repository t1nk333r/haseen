import QtQuick
import qs.Haseen

// Bar cell: optional glyph plus optional label, hover tint, click and wheel.
// Sized to its content; height follows the bar.
Item {
    id: root

    property string glyph: ""
    property string text: ""
    property color color: Theme.foreground
    property bool highlighted: false
    property int padding: Theme.gap

    signal clicked(int button)
    signal scrolled(int steps)

    // Natural width; widgets that hide themselves set implicitWidth to 0.
    readonly property real contentWidth: row.implicitWidth + padding * 2

    implicitWidth: contentWidth
    implicitHeight: parent ? parent.height : Theme.fontSize * 2

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: 3
        anchors.bottomMargin: 3
        radius: Theme.radius
        color: root.highlighted ? Theme.selection : Theme.surfaceAlt
        visible: root.highlighted || mouse.containsMouse
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(Theme.gap / 2)

        Glyph {
            glyph: root.glyph
            color: root.color
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            text: root.text
            color: root.color
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: event => root.clicked(event.button)
        onWheel: event => {
            const steps = Math.round(event.angleDelta.y / 120);
            if (steps !== 0)
                root.scrolled(steps);
        }
    }
}
