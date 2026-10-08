import QtQuick
import qs.Haseen
import "Model.js" as Model
ActionButton {
    property var service: null
    glyph: "\uf013"
    implicitHeight: Math.max(64 * scale, contentItem.implicitHeight + 20 * scale)
    text: service ? Model.text(service.id) + " • " + Model.serviceState(service) + "\n" + Model.text(service.unit || service.reason) : ""
    explanation: service ? "Ownership: " + Model.text(service.ownership) + ". " + Model.text(service.reason) : ""
    Accessible.role: Accessible.ListItem
}
