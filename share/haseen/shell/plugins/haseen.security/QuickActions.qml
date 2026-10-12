import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var capabilities: []
    property real viewportHeight: 0
    signal reveal(var item)
    signal chosen(string itemId)
    spacing: Theme.gap
    Inventory {
        width: parent.width
        choices: true
        viewportHeight: root.viewportHeight
        onReveal: item => root.reveal(item)
        rows: Model.localIds.map(id => {
            const c = root.capabilities.find(c => c.id === id);
            return {id: id, label: ["TCP listener", "Directory server", "Selected file server", "Proxy CA anchor", "Remote desktop client"][Model.localIds.indexOf(id)] + "\n" + (c ? Model.text(c.state) + " • " + Model.text(c.reason) : "Prerequisite evidence unavailable")};
        })
        onInspected: itemId => root.chosen(itemId)
    }
}
