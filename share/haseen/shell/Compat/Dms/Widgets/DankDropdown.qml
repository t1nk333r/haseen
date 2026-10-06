import QtQuick
import QtQuick.Controls
import qs.Common

// qs.Widgets.DankDropdown for DankMaterialShell plugins (architecture 5.4): a
// labelled (or compact) trigger that opens a list of string options. The
// properties, the label/compact layout and the selection contract (the pick
// becomes currentValue, then valueChanged(value) fires) follow dank-qml-common
// DCommon/Widgets/DDropdown.qml, which DMS's DankDropdown wraps (MIT,
// Copyright (c) 2025-2026 Avenge Media LLC). The menu is a popup inside the
// plugin's own window; fuzzy search is not provided.
Item {
    id: root

    property string text: ""
    property string description: ""
    property string currentValue: ""
    property var options: []
    property var optionIcons: []
    property bool enableFuzzySearch: false
    property int maxPopupHeight: 360
    property bool openUpwards: false
    property int popupWidth: 0
    property bool alignPopupRight: false
    property int dropdownWidth: 200
    property bool showLabel: true
    property bool compactMode: !showLabel || (text === "" && description === "")
    property bool addHorizontalPadding: false
    property string emptyText: ""
    property color backgroundColor: Theme.surfaceContainerHigh
    property int triggerHeight: 40
    readonly property bool menuOpen: menu.opened

    signal valueChanged(string value)

    function openDropdownMenu() {
        if (options.length > 0)
            menu.open();
    }

    function closeDropdownMenu() {
        menu.close();
    }

    width: compactMode ? dropdownWidth : (parent ? parent.width : dropdownWidth)
    implicitWidth: dropdownWidth
    implicitHeight: compactMode ? triggerHeight : Math.max(Theme.listItemHeight, labels.implicitHeight + Theme.spacingM)

    Column {
        id: labels

        anchors.left: parent.left
        anchors.right: trigger.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: root.addHorizontalPadding ? Theme.spacingM : 0
        anchors.rightMargin: Theme.spacingL
        spacing: Theme.spacingXS
        visible: !root.compactMode

        StyledText {
            width: parent.width
            text: root.text
            font.weight: Theme.fontWeightMedium
        }

        StyledText {
            width: parent.width
            text: root.description
            visible: text !== ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: trigger

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: root.addHorizontalPadding && !root.compactMode ? Theme.spacingM : 0
        width: root.compactMode ? root.width : (root.popupWidth > 0 ? root.popupWidth : root.dropdownWidth)
        height: root.compactMode && root.height > 0 ? root.height : root.triggerHeight
        radius: Theme.cornerRadius
        color: triggerMouse.containsMouse || menu.opened ? Theme.withAlpha(Theme.primary, 0.16) : root.backgroundColor
        border.width: menu.opened ? 1 : 0
        border.color: Theme.primary
        opacity: root.enabled ? 1 : 0.38

        StyledText {
            anchors.left: parent.left
            anchors.right: arrow.left
            anchors.leftMargin: Theme.spacingM
            anchors.rightMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            text: root.currentValue !== "" ? root.currentValue : root.emptyText
            font.pixelSize: Theme.fontSizeMedium
        }

        DankIcon {
            id: arrow

            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: menu.opened ? "expand_less" : "expand_more"
            size: Theme.iconSizeSmall
            color: Theme.surfaceVariantText
        }

        MouseArea {
            id: triggerMouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: root.enabled
            cursorShape: Qt.PointingHandCursor
            onClicked: menu.opened ? root.closeDropdownMenu() : root.openDropdownMenu()
        }
    }

    Popup {
        id: menu

        readonly property int rowHeight: 32

        parent: trigger
        width: Math.max(trigger.width, 160)
        height: Math.min(root.maxPopupHeight, list.contentHeight + padding * 2)
        x: root.alignPopupRight ? trigger.width - width : 0
        y: root.openUpwards ? -height - Theme.spacingXS : trigger.height + Theme.spacingXS
        padding: Theme.spacingXS
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.surfaceContainer
            radius: Theme.cornerRadius
            border.width: 1
            border.color: Theme.outline
        }

        contentItem: ListView {
            id: list

            clip: true
            model: root.options
            boundsBehavior: Flickable.StopAtBounds

            delegate: Rectangle {
                id: row

                required property var modelData
                required property int index
                readonly property bool current: String(modelData) === root.currentValue

                width: ListView.view.width
                height: menu.rowHeight
                radius: Theme.cornerRadius
                color: rowMouse.containsMouse ? Theme.withAlpha(Theme.primary, 0.16) : (current ? Theme.withAlpha(Theme.primary, 0.08) : "transparent")

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DankIcon {
                        name: root.optionIcons.length > row.index ? root.optionIcons[row.index] : ""
                        visible: name !== ""
                        size: Theme.iconSizeSmall
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    StyledText {
                        text: String(row.modelData)
                        color: row.current ? Theme.primary : Theme.surfaceText
                        font.weight: row.current ? Theme.fontWeightMedium : Font.Normal
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: rowMouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const value = String(row.modelData);
                        root.currentValue = value;
                        root.valueChanged(value);
                        root.closeDropdownMenu();
                    }
                }
            }
        }
    }
}
