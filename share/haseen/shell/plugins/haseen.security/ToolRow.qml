import QtQuick
import qs.Haseen
import "Model.js" as Model
ActionButton {
    id: root
    property var tool: null
    glyph: "\uf120"
    implicitHeight: Math.max(64 * textScale, contentItem.implicitHeight + 24 * textScale)
    text: tool ? Model.text(tool.id) + "\n" + I18n.tr(Model.toolState(tool)) + "\n" + tool.groups.map(Model.text).join(", ") : ""
    explanation: tool ? Model.text(tool.reason) + " " + I18n.tr("Groups: %1", tool.groups.map(Model.text).join(", ")) + ". " + I18n.tr("Installation and usage are separate evidence.") : ""
    Accessible.role: Accessible.ListItem
}
