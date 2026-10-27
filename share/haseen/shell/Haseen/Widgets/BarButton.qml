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
    // A horizontal label wider than this is elided; 0 means never.
    property real maxTextWidth: 0
    // Wheel delta not yet worth a step: touchpads and hi-res wheels send
    // fractions of a notch (QWheelEvent::angleDelta), which add up.
    property real _wheelDelta: 0

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

        // A bar glyph is Omarchy's bar icon (Style.bar.iconFont, the
        // BarIconButton size), the size plugin bar icons take too (plan 141).
        Glyph {
            glyph: root.glyph
            color: root.color
            visible: root.glyph !== ""
            font.pixelSize: Theme.barMetrics.iconFont
        }

        Text {
            width: root.vertical ? Math.max(1, root.width - 4) : root.maxTextWidth > 0 ? Math.min(implicitWidth, root.maxTextWidth) : implicitWidth
            text: root.text
            // Labels carry outside strings (SSIDs, model ids, titles); a tag in
            // one must not render, let alone load a remote image.
            textFormat: Text.PlainText
            elide: !root.vertical && root.maxTextWidth > 0 ? Text.ElideRight : Text.ElideNone
            color: root.color
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
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
            root._wheelDelta += event.angleDelta.y;
            const steps = Math.trunc(root._wheelDelta / 120);
            if (steps !== 0) {
                root._wheelDelta -= steps * 120;
                root.scrolled(steps);
            }
        }
    }
}
