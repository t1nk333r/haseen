import QtQuick
import qs.Haseen
Column {
    id: root
    property string state: "empty"
    property string message: ""
    property string description: ""
    property string action: ""
    signal activated()
    function focusAction(): void { actionButton.forceActiveFocus(); }
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: root.message; Accessible.description: root.state }
    Label { width: parent.width; text: root.description }
    Repeater {
        model: root.state === "loading" ? 3 : 0
        delegate: Rectangle { required property int index; width: root.width; height: Math.round(64 * Theme.fontSize / 11); radius: Theme.radius; color: Theme.surfaceAlt }
    }
    ActionButton { id: actionButton; visible: root.action !== ""; text: root.action; onClicked: root.activated() }
}
