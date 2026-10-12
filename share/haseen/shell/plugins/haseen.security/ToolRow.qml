import QtQuick
import qs.Haseen
import "Model.js" as Model
ActionButton {
    id: root
    property var tool: null
    glyph: "\uf120"
    implicitHeight: Math.max(64 * scale, contentItem.implicitHeight + 24 * scale)
    text: tool ? Model.text(tool.id) + "\n" + Model.toolState(tool) + "\n" + tool.groups.map(Model.text).join(", ") : ""
    explanation: tool ? Model.text(tool.reason) + " Groups: " + tool.groups.map(Model.text).join(", ") + ". Installation and usage are separate evidence." : ""
    Accessible.role: Accessible.ListItem
}
