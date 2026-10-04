import QtQuick
import qs.Haseen

// Panel control for haseen.prayers, standing in for the Omarchy Ui control
// of the same role that upstream OmaPrayers used. Theme tokens only.
// A text button; `bordered` draws the outline upstream's settings used.
Rectangle {
    id: root

    property string text: ""
    property bool bordered: false
    property color foreground: Theme.foreground
    property color background: "transparent"
    property string fontFamily: Theme.fontFamily
    property int fontSize: Theme.fontSize
    property int horizontalPadding: Math.round(Theme.fontSize * 0.7)
    property int verticalPadding: Math.round(Theme.fontSize * 0.3)
    property string tooltipText: ""

    signal clicked

    implicitWidth: label.implicitWidth + horizontalPadding * 2
    implicitHeight: label.implicitHeight + verticalPadding * 2
    width: implicitWidth
    height: implicitHeight
    radius: Theme.radius
    opacity: enabled ? 1 : 0.5
    color: mouse.containsMouse && enabled ? Qt.rgba(foreground.r, foreground.g, foreground.b, 0.13) : background
    border.width: bordered ? Theme.borderWidth : 0
    border.color: mouse.containsMouse ? Theme.accent : Theme.border

    Text {
        id: label

        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: root.text
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    PrayerToolTip {
        visible: mouse.containsMouse && root.tooltipText !== ""
        text: root.tooltipText
    }
}
