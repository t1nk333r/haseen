import QtQuick
import qs.Haseen
Column {
    id: root
    property string intent: ""
    property string consequences: ""
    property bool allowed: false
    signal cancel()
    signal preview()
    signal proceed()
    spacing: Theme.gap * 2
    Label { width: parent.width; heading: true; text: "Review — terminal confirmation remains authoritative" }
    Label { width: parent.width; mono: true; text: root.intent }
    Label { width: parent.width; text: root.consequences }
    Label { width: parent.width; text: "Continuing only opens a terminal or requests the verified client. It does not prove completion. The CLI revalidates and may refuse; no --yes is passed." }
    ActionButton { id: cancel; width: parent.width; text: "Cancel"; onClicked: root.cancel(); Component.onCompleted: forceActiveFocus() }
    ActionButton { width: parent.width; text: "Preview — no changes made"; enabled: root.allowed; onClicked: root.preview() }
    ActionButton { width: parent.width; text: "Continue in terminal / open client"; enabled: root.allowed; onClicked: root.proceed() }
}
