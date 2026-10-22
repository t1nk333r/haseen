import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// Under LayoutMirroring (the panel's Arabic layout) the knob sits on the
// left when on, the way a right-to-left switch reads.
Rectangle {
    id: root

    property bool checked: false
    readonly property bool mirrored: LayoutMirroring.enabled
    property color foreground: Theme.foreground
    property int trackHeight: Math.round(Theme.fontSize * 1.5)

    signal toggled

    width: trackHeight * 2
    height: trackHeight
    radius: height / 2
    color: checked ? Theme.accent : Qt.rgba(foreground.r, foreground.g, foreground.b, 0.13)
    border.width: Theme.borderWidth
    border.color: checked ? Theme.accent : Theme.border

    Rectangle {
        width: root.height - 6
        height: width
        radius: width / 2
        y: 3
        x: root.checked !== root.mirrored ? root.width - width - 3 : 3
        color: root.checked ? Theme.accentFg : root.foreground
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }
}
