import QtQuick
import qs.Haseen

// Bar cell: optional glyph plus optional label, hover tint, click and wheel.
// Sized to its content; height follows the bar. In a vertical (left/right)
// bar BarSection sets `vertical`: the glyph stacks over the label, the label
// shrinks to the bar's width, and the height comes from the content.
Item {
    id: root

    property string glyph: ""
    property string text: ""
    property color color: Theme.barForeground
    property bool highlighted: false
    property int padding: Theme.gap
    property bool vertical: false

    signal clicked(int button)
    signal scrolled(int steps)

    // Natural width; widgets that hide themselves set implicitWidth to 0.
    readonly property real contentWidth: content.implicitWidth + padding * 2

    implicitWidth: contentWidth
    implicitHeight: vertical ? content.implicitHeight + padding : (parent ? parent.height : Theme.fontSize * 2)

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.vertical ? 0 : 3
        anchors.bottomMargin: root.vertical ? 0 : 3
        anchors.leftMargin: root.vertical ? 3 : 0
        anchors.rightMargin: root.vertical ? 3 : 0
        radius: Theme.radius
        color: root.highlighted ? Theme.selection : Theme.surfaceAlt
        visible: root.highlighted || mouse.containsMouse
    }

    Grid {
        id: content
        anchors.centerIn: parent
        columns: root.vertical ? 1 : 2
        spacing: Math.round(Theme.gap / 2)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        Glyph {
            glyph: root.glyph
            color: root.color
            visible: root.glyph !== ""
        }

        Text {
            width: root.vertical ? Math.max(1, root.width - 4) : implicitWidth
            text: root.text
            color: root.color
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            fontSizeMode: root.vertical ? Text.HorizontalFit : Text.FixedSize
            minimumPixelSize: Math.max(6, Theme.fontSize - 5)
            horizontalAlignment: Text.AlignHCenter
            visible: root.text !== ""
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
