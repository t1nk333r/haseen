// Adapted from Omarchy shell/Ui/Button.qml. MIT, Copyright (c) David
// Heinemeier Hansson.
// haseen: theme tokens from qs.Haseen; flat borders (controls never take the
// surfaces' gradient); no tooltip (native panels show hints in their own
// text, as before).
import QtQuick
import qs.Haseen

// The panel button (plan 115). States are painted in Omarchy's order:
//
//   pressed (mouse down)         pressed fill
//   activeFocus (Tab focus)      focus fill + focus border
//   hasCursor || hover           hover-cursor fill + hover-cursor border
//   selected                     selected fill (+ selected border, width 0 by default)
//   active                       selected fill
//   idle                         `background`, the normal border if `bordered`
//
// `hovered(bool)` lets a panel with its own keyboard cursor follow the mouse.
Rectangle {
    id: root

    property string text: ""
    property string iconText: ""

    property bool selected: false
    property bool active: false
    property bool hasCursor: false
    property bool focusable: false
    property bool bordered: false

    property color foreground: Theme.foreground
    property color background: "transparent"
    property color accent: Theme.accent

    property string fontFamily: Theme.font.family
    property real fontSize: Theme.font.body
    property real iconSize: Theme.font.icon
    property real horizontalPadding: Theme.spacing.controlPaddingX
    property real verticalPadding: Theme.spacing.controlPaddingY
    property bool leftAlign: false

    readonly property bool hot: mouseArea.containsMouse || hasCursor
    readonly property bool _focusRing: focusable && activeFocus
    readonly property color _selectedColor: Theme.selectedStateColor(foreground, accent)
    // The widest border any state can paint stays reserved, so a borderless
    // idle button does not grow a pixel per side on hover (Button.qml:71-107).
    readonly property int _reserved: Math.max(focusable ? Theme.focusBorderWidth : 0, Theme.hoverBorderWidth, Theme.selectedBorderWidth, bordered ? Theme.normalBorderWidth : 0)
    readonly property real _labelRoom: width - horizontalPadding - _reserved * 2 - (icon.visible ? icon.implicitWidth + (label.visible ? row.spacing : 0) : 0)

    signal clicked
    signal rightClicked
    signal hovered(bool isHovered)

    activeFocusOnTab: focusable
    Keys.onReturnPressed: if (focusable) root.clicked()
    Keys.onEnterPressed: if (focusable) root.clicked()
    Keys.onSpacePressed: if (focusable) root.clicked()

    implicitWidth: (icon.visible ? icon.implicitWidth + (label.visible ? row.spacing : 0) : 0) + (label.visible ? label.implicitWidth : 0) + (horizontalPadding + _reserved) * 2
    implicitHeight: row.implicitHeight + (verticalPadding + _reserved) * 2
    radius: Theme.radius

    color: mouseArea.pressed ? Theme.pressedFillFor(foreground, accent) : _focusRing ? Theme.focusFillFor(foreground, accent) : hot ? Theme.hoverFillFor(foreground, accent) : (selected || active) ? Theme.selectedFillFor(foreground, accent) : background
    border.color: _focusRing ? Theme.focusBorderFor(foreground, accent) : hot ? Theme.hoverBorderFor(foreground, accent) : (selected && Theme.selectedBorderWidth > 0) ? Theme.selectedBorderFor(foreground, accent) : bordered ? Theme.normalBorderFor(foreground, accent) : "transparent"
    border.width: _focusRing ? Theme.focusBorderWidth : hot ? Theme.hoverBorderWidth : (selected && Theme.selectedBorderWidth > 0) ? Theme.selectedBorderWidth : bordered ? Theme.normalBorderWidth : 0

    Behavior on color {
        ColorAnimation {
            duration: Theme.duration(120)
        }
    }

    Row {
        id: row

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: root.leftAlign ? parent.left : undefined
        anchors.leftMargin: root.leftAlign ? root._reserved + root.horizontalPadding : 0
        anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
        spacing: Theme.spacing.controlGap

        Text {
            id: icon

            visible: root.iconText !== ""
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.iconText
            color: root.selected ? root._selectedColor : root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.iconSize
        }

        Text {
            id: label

            visible: root.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, Math.min(implicitWidth, root._labelRoom))
            textFormat: Text.PlainText
            text: root.text
            color: root.selected ? root._selectedColor : root.foreground
            font.family: root.fontFamily
            font.pixelSize: root.fontSize
            font.bold: root.selected
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: Math.round(root.fontSize * 0.75)
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onContainsMouseChanged: root.hovered(containsMouse)
        onClicked: mouse => {
            if (root.focusable)
                root.forceActiveFocus();
            if (mouse.button === Qt.RightButton)
                root.rightClicked();
            else
                root.clicked();
        }
    }
}
