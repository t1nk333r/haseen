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
    Label { width: parent.width; heading: true; text: I18n.tr("Review — nothing has run yet") }
    // The command, one word per line: never mirrored, always from the left.
    Label { width: parent.width; mono: true; text: root.intent; LayoutMirroring.enabled: false }
    Label { width: parent.width; text: root.consequences }
    Label { width: parent.width; text: I18n.tr("Continuing only opens a terminal or requests the verified client. It does not prove completion. The CLI revalidates and may refuse; no --yes is passed.") }
    ActionButton { id: cancel; width: parent.width; text: I18n.tr("Cancel"); onClicked: root.cancel(); Component.onCompleted: forceActiveFocus() }
    ActionButton { width: parent.width; text: I18n.tr("Preview — no changes made"); enabled: root.allowed; onClicked: root.preview() }
    ActionButton { width: parent.width; text: I18n.tr("Continue in terminal / open client"); enabled: root.allowed; onClicked: root.proceed() }
}
