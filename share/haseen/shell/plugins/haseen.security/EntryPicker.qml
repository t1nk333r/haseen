import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var entries: []
    property string selected: ""
    signal chosen(string entryId)
    spacing: Theme.gap
    Label { width: parent.width; heading: true; text: "Choose exactly one owned entrypoint" }
    StateMessage { width: parent.width; visible: root.entries.length === 0; message: "No verified entrypoints remain."; description: "Refresh and choose again. Nothing was launched." }
    Inventory {
        width: parent.width
        choices: true
        currentId: root.selected
        rows: root.entries.map(e => ({id: e.id, label: Model.text(e.path) + "\n" + Model.text(e.kind) + " • " + (e.usage.state === "ready" ? "Documentation available" : Model.text(e.usage.reason))}))
        onInspected: itemId => root.chosen(itemId)
    }
}
