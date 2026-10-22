import QtQuick
import qs.Haseen
Column {
    id: root
    property string kind: "empty"
    property string message: ""
    property string description: ""
    property string action: ""
    signal activated()
    function focusAction(): void { actionButton.forceActiveFocus(); }
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: root.message; Accessible.description: ({error: I18n.tr("Error"), stale: I18n.tr("Stale"), loading: I18n.tr("Loading"), empty: I18n.tr("Empty")})[root.kind] || "" }
    Label { width: parent.width; text: root.description }
    Repeater {
        model: root.kind === "loading" ? 3 : 0
        delegate: Rectangle { required property int index; width: root.width; height: Math.round(64 * Theme.fontSize / 11); radius: Theme.radius; color: Theme.surfaceAlt }
    }
    // Anchored to the start, so it sits on the right in a mirrored panel.
    ActionButton { id: actionButton; anchors.left: parent.left; visible: root.action !== ""; text: root.action; onClicked: root.activated() }
}
