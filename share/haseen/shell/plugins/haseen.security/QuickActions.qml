import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var capabilities: []
    signal chosen(string itemId)
    spacing: Theme.gap
    Inventory {
        width: parent.width
        choices: true
        rows: Model.localIds.map(id => {
            const c = root.capabilities.find(c => c.id === id);
            return {id: id, label: ["TCP listener", "Directory server", "Selected file server", "Proxy CA anchor", "Remote desktop client"][Model.localIds.indexOf(id)] + "\n" + (c ? Model.text(c.state) + " • " + Model.text(c.reason) : "Prerequisite evidence unavailable")};
        })
        onInspected: itemId => root.chosen(itemId)
    }
}
