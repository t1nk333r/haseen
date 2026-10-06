import QtQuick
import qs.Common

// qs.Widgets.DankTextField for DankMaterialShell plugins (architecture 5.4): a
// single-line text field. Property aliases, signals and helper functions
// follow dank-qml-common DCommon/Widgets/DTextField.qml, which DMS's
// DankTextField wraps (MIT, Copyright (c) 2025-2026 Avenge Media LLC). The
// expressive morph, icons and accessory buttons are not provided.
Rectangle {
    id: root

    property alias text: input.text
    property alias cursorPosition: input.cursorPosition
    property alias readOnly: input.readOnly
    property alias font: input.font
    property alias textColor: input.color
    property alias validator: input.validator
    property alias maximumLength: input.maximumLength
    property string placeholderText: ""
    property string labelText: ""
    property bool outlined: false
    property bool isError: false
    property int echoMode: TextInput.Normal
    property color backgroundColor: Theme.surfaceContainerHigh
    property color focusedBorderColor: Theme.primary
    property color normalBorderColor: Theme.outline
    property color placeholderColor: Theme.surfaceVariantText
    property real cornerRadius: Theme.cornerRadius
    property real topPadding: Theme.spacingS
    property real bottomPadding: Theme.spacingS
    property real leftPadding: Theme.spacingM
    property real rightPadding: Theme.spacingM

    signal textEdited
    signal editingFinished
    signal accepted
    signal focusStateChanged(bool hasFocus)

    function getActiveFocus() {
        return input.activeFocus;
    }

    function setFocus(value) {
        input.focus = value;
    }

    function selectAll() {
        input.selectAll();
    }

    function clear() {
        input.clear();
    }

    function insertText(str) {
        input.insert(input.cursorPosition, str);
    }

    implicitWidth: 200
    implicitHeight: Math.max(36, input.implicitHeight + topPadding + bottomPadding)
    radius: cornerRadius
    color: backgroundColor
    border.width: input.activeFocus || outlined || isError ? 1 : 0
    border.color: isError ? Theme.error : (input.activeFocus ? focusedBorderColor : normalBorderColor)

    TextInput {
        id: input

        anchors.fill: parent
        anchors.leftMargin: root.leftPadding
        anchors.rightMargin: root.rightPadding
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.surfaceText
        selectionColor: Theme.withAlpha(Theme.primary, 0.4)
        selectedTextColor: Theme.surfaceText
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSizeMedium
        echoMode: root.echoMode
        clip: true
        selectByMouse: true
        activeFocusOnTab: root.activeFocusOnTab
        onTextEdited: root.textEdited()
        onEditingFinished: root.editingFinished()
        onAccepted: root.accepted()
        onActiveFocusChanged: root.focusStateChanged(activeFocus)
    }

    StyledText {
        anchors.fill: input
        text: root.placeholderText
        visible: input.text === "" && !input.activeFocus
        color: root.placeholderColor
        font.pixelSize: input.font.pixelSize
    }
}
