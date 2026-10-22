import QtQuick
import qs.Haseen
import "Model.js" as Model
Column {
    id: root
    property var entries: []
    property string selected: ""
    property real viewportHeight: 0
    signal reveal(var item)
    function focusHeading(): void { title.focusHeading(); }
    signal chosen(string entryId)
    spacing: Theme.gap
    Label { id: title; width: parent.width; heading: true; entryHeading: true; text: I18n.tr("Choose exactly one owned entrypoint") }
    StateMessage { width: parent.width; visible: root.entries.length === 0; message: I18n.tr("No verified entrypoints remain."); description: I18n.tr("Refresh and choose again. Nothing was launched.") }
    Inventory {
        width: parent.width
        choices: true
        viewportHeight: root.viewportHeight
        onReveal: item => root.reveal(item)
        onEmptyFocused: title.focusHeading()
        currentId: root.selected
        rows: root.entries.map(e => ({id: e.id, label: Model.text(e.path) + "\n" + Model.text(e.kind) + " • " + (e.usage.state === "ready" ? I18n.tr("Documentation available") : Model.text(e.usage.reason))}))
        onInspected: itemId => root.chosen(itemId)
    }
}
