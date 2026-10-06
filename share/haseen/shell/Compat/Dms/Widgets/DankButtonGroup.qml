import QtQuick
import qs.Common

// qs.Widgets.DankButtonGroup for DankMaterialShell plugins (architecture 5.4):
// a row of connected segments, single or multi select. Properties, segment
// sizing and the selectionChanged(index, selected) contract follow
// dank-qml-common DCommon/Widgets/DButtonGroup.qml, which DMS's
// DankButtonGroup wraps (MIT, Copyright (c) 2025-2026 Avenge Media LLC):
// single mode reports the pick and leaves currentIndex to the plugin's
// binding. The look is haseen's; expressive radius motion is not provided.
Row {
    id: root

    property var model: []
    property int currentIndex: -1
    property string selectionMode: "single"
    property bool multiSelect: selectionMode === "multi"
    property var initialSelection: []
    property var currentSelection: initialSelection
    property bool checkEnabled: true
    property color selectedColor: Theme.primary
    property color selectedContentColor: Theme.onPrimary
    property color unselectedColor: Theme.surfaceContainerHigh
    property color unselectedContentColor: Theme.surfaceText
    property bool iconOnly: false
    property bool labelOnlySelected: false
    property string size: "medium"
    property int buttonHeight: size === "small" ? Theme.buttonHeightXS : 40
    property int minButtonWidth: size === "small" ? 56 : 64
    property int buttonPadding: size === "small" ? Theme.spacingM : Theme.spacingL
    property int textSize: size === "small" ? Theme.fontSizeSmall : Theme.fontSizeMedium
    property bool userInteracted: false
    property bool fillWidth: false

    signal selectionChanged(int index, bool selected)
    signal animationCompleted

    spacing: 2

    function isSelected(index) {
        return multiSelect ? currentSelection.indexOf(model[index]) >= 0 : index === currentIndex;
    }

    function selectItem(index) {
        userInteracted = true;
        if (multiSelect) {
            const value = model[index];
            const was = currentSelection.indexOf(value) >= 0;
            currentSelection = was ? currentSelection.filter(v => v !== value) : currentSelection.concat([value]);
            selectionChanged(index, !was);
        } else {
            const old = currentIndex;
            selectionChanged(index, true);
            if (old !== index && old >= 0)
                selectionChanged(old, false);
        }
        animationCompleted();
    }

    Repeater {
        id: repeater

        model: root.model

        delegate: Rectangle {
            id: segment

            required property var modelData
            required property int index
            readonly property bool selected: root.isSelected(index)
            readonly property color contentColor: selected ? root.selectedContentColor : root.unselectedContentColor
            readonly property string label: typeof modelData === "string" ? modelData : (modelData.text || "")
            readonly property string icon: typeof modelData === "object" && modelData.icon ? modelData.icon : ""
            readonly property real natural: content.implicitWidth + root.buttonPadding * 2

            width: root.fillWidth ? Math.max(0, (root.width - root.spacing * (repeater.count - 1)) / Math.max(1, repeater.count)) : Math.max(natural, root.minButtonWidth)
            height: root.buttonHeight
            radius: Math.min(height / 2, Theme.cornerRadius)
            color: selected ? root.selectedColor : (mouse.containsMouse ? Theme.withAlpha(root.selectedColor, 0.18) : root.unselectedColor)
            opacity: root.enabled ? 1 : 0.38

            Behavior on color {
                ColorAnimation {
                    duration: Theme.shortDuration
                }
            }

            Row {
                id: content

                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: "check"
                    size: Theme.iconSizeSmall
                    color: segment.contentColor
                    visible: root.checkEnabled && !root.iconOnly && segment.selected
                    anchors.verticalCenter: parent.verticalCenter
                }

                DankIcon {
                    name: segment.icon
                    size: Theme.iconSizeSmall
                    color: segment.contentColor
                    visible: segment.icon !== ""
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: segment.label
                    visible: segment.icon === "" || (root.labelOnlySelected ? segment.selected : !root.iconOnly)
                    font.pixelSize: root.textSize
                    font.weight: Theme.fontWeightMedium
                    color: segment.contentColor
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                enabled: root.enabled
                cursorShape: Qt.PointingHandCursor
                onClicked: root.selectItem(segment.index)
            }
        }
    }
}
