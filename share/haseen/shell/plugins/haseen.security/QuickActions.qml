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
            return {id: id, label: [I18n.tr("TCP listener"), I18n.tr("Directory server"), I18n.tr("Selected file server"), I18n.tr("Proxy CA anchor"), I18n.tr("Remote desktop client")][Model.localIds.indexOf(id)] + "\n" + (c ? Model.text(c.state) + " • " + Model.text(c.reason) : I18n.tr("Prerequisite evidence unavailable"))};
        })
        onInspected: itemId => root.chosen(itemId)
    }
}
