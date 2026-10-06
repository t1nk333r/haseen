import QtQuick
import qs.Common

// qs.Widgets.DankToggle for DankMaterialShell plugins (architecture 5.4): a
// switch, optionally with a label and description. Properties, the 52x32
// track and the controlled contract (a click emits clicked() and
// toggled(!checked); the plugin owns `checked`) follow dank-qml-common
// DCommon/Widgets/DToggle.qml, which DMS's DankToggle wraps (MIT, Copyright
// (c) 2025-2026 Avenge Media LLC). The thumb spring is a plain animation.
Item {
    id: toggle

    property bool checked: false
    property bool toggling: false
    property string text: ""
    property string description: ""
    property color descriptionColor: Theme.surfaceVariantText
    property bool hideText: false
    property string checkedIcon: "check"
    property string uncheckedIcon: ""
    readonly property bool showText: text !== "" && !hideText
    readonly property int trackWidth: 52
    readonly property int trackHeight: 32

    signal clicked
    signal toggled(bool checked)
    signal toggleCompleted(bool checked)

    function handleClick() {
        if (!enabled || toggling)
            return;
        clicked();
        toggled(!checked);
    }

    width: showText ? (parent ? parent.width : trackWidth) : trackWidth
    height: showText ? Math.max(trackHeight, labels.implicitHeight + Theme.spacingM * 2) : trackHeight
    implicitWidth: width
    implicitHeight: height
    opacity: enabled ? 1 : 0.38

    Column {
        id: labels

        anchors.left: parent.left
        anchors.right: track.left
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS
        visible: toggle.showText

        StyledText {
            width: parent.width
            text: toggle.text
            font.weight: Theme.fontWeightMedium
            wrapMode: Text.WordWrap
        }

        StyledText {
            width: parent.width
            text: toggle.description
            visible: text !== ""
            font.pixelSize: Theme.fontSizeSmall
            color: toggle.descriptionColor
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: track

        anchors.right: parent.right
        anchors.rightMargin: toggle.showText ? Theme.spacingM : 0
        anchors.verticalCenter: parent.verticalCenter
        width: toggle.trackWidth
        height: toggle.trackHeight
        radius: height / 2
        color: toggle.checked ? Theme.primary : Theme.surfaceContainerHighest
        border.width: toggle.checked ? 0 : 2
        border.color: Theme.outline

        Behavior on color {
            ColorAnimation {
                duration: Theme.shortDuration
            }
        }

        Rectangle {
            id: thumb

            readonly property real size: toggle.checked ? 24 : 16

            width: size
            height: size
            radius: size / 2
            anchors.verticalCenter: parent.verticalCenter
            x: toggle.checked ? parent.width - width - 4 : 8
            color: toggle.checked ? Theme.onPrimary : Theme.outline

            Behavior on x {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Easing.OutCubic
                }
            }

            DankIcon {
                anchors.centerIn: parent
                name: toggle.checked ? toggle.checkedIcon : toggle.uncheckedIcon
                visible: name !== ""
                size: 14
                color: toggle.checked ? Theme.primary : Theme.surfaceContainerHighest
            }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: toggle.enabled && !toggle.toggling
        cursorShape: Qt.PointingHandCursor
        onClicked: toggle.handleClick()
    }
}
