import QtQuick
import qs.Common

// qs.Widgets.DankActionButton for DankMaterialShell plugins (architecture
// 5.4): a round icon button with a hover/press state layer and an optional
// tooltip. Properties and signals follow dank-qml-common
// DCommon/Widgets/DActionButton.qml, which DMS's DankActionButton wraps
// (MIT, Copyright (c) 2025-2026 Avenge Media LLC); it is drawn with haseen's
// theme and without DMS's shape animation.
Rectangle {
    id: root

    property string iconName: ""
    property int iconSize: Theme.iconSize - 4
    property color iconColor: Theme.surfaceText
    property bool iconFilled: false
    property color backgroundColor: "transparent"
    property color stateColor: iconColor
    property bool circular: true
    property int buttonSize: Theme.buttonHeightXS
    property var tooltipText: null
    property string tooltipSide: "bottom"
    readonly property bool hovered: mouse.containsMouse
    readonly property bool pressed: mouse.pressed

    signal clicked
    signal pressAndHold
    signal entered
    signal exited

    implicitWidth: buttonSize
    implicitHeight: buttonSize
    radius: circular ? height / 2 : Theme.cornerRadius
    color: backgroundColor
    Accessible.role: Accessible.Button
    Accessible.name: tooltipText || iconName

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.withAlpha(root.stateColor, root.pressed ? 0.16 : 0.12)
        visible: root.enabled && (root.hovered || root.pressed)
    }

    DankIcon {
        anchors.centerIn: parent
        name: root.iconName
        size: root.iconSize
        filled: root.iconFilled
        color: root.enabled ? root.iconColor : Theme.withAlpha(Theme.surfaceText, 0.38)
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onPressAndHold: root.pressAndHold()
        onEntered: {
            root.entered();
            if (root.tooltipText)
                tip.show(String(root.tooltipText), root, 0, 0, root.tooltipSide);
        }
        onExited: {
            root.exited();
            tip.hide();
        }
    }

    DankTooltipV2 {
        id: tip
    }
}
