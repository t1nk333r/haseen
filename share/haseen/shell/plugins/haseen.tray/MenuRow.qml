// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml (menu row).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file, theme tokens.
import QtQuick
import qs.Haseen

// One tray menu row: check mark (or back arrow), optional icon, label,
// submenu arrow; hover tint; dimmed while disabled.
Item {
    id: root

    property string lead: ""
    property string icon: ""
    property string label: ""
    property string trail: ""

    signal activated

    opacity: enabled ? 1.0 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: mouse.containsMouse && root.enabled
    }

    Text {
        id: leadText

        anchors.verticalCenter: parent.verticalCenter
        width: Theme.fontSize + Theme.gap
        horizontalAlignment: Text.AlignHCenter
        text: root.lead
        color: Theme.foreground
        font.family: Theme.fontMono
        font.pixelSize: Theme.fontSize
    }

    Image {
        id: iconImage

        anchors.verticalCenter: parent.verticalCenter
        anchors.left: leadText.right
        width: Theme.fontSize + 2
        height: Theme.fontSize + 2
        visible: root.icon !== ""
        fillMode: Image.PreserveAspectFit
        sourceSize.width: width * Screen.devicePixelRatio
        sourceSize.height: height * Screen.devicePixelRatio
        source: root.icon
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: iconImage.visible ? iconImage.right : leadText.right
        anchors.leftMargin: Math.round(Theme.gap / 2)
        anchors.right: trailText.left
        anchors.rightMargin: Math.round(Theme.gap / 2)
        text: root.label
        textFormat: Text.PlainText
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        elide: Text.ElideRight
    }

    Text {
        id: trailText

        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: Theme.gap
        text: root.trail
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
