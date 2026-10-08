import QtQuick
import qs.Haseen
import "../haseen.menu/MenuModel.js" as Menu

// One Tab stop for a list; identity is retained across a read/filter update.
Column {
    id: root
    property var rows: []
    property bool services: false
    property bool choices: false
    property int current: 0
    property string currentId: ""
    signal inspected(string itemId)
    signal reveal(var item)
    signal emptyFocused()
    spacing: Theme.gap
    Accessible.role: Accessible.List
    Accessible.name: choices ? "Choices" : services ? "Installed services" : "Tool inventory"
    onRowsChanged: {
        let hadFocus = false;
        for (let i = 0; i < entries.count; i++) {
            const item = entries.itemAt(i).item;
            if (item && item.activeFocus) hadFocus = true;
        }
        const mapped = rows.map(r => {
            const record = {};
            Menu.ROLES.forEach(role => record[role] = role === "childCount" ? 0 : role === "disabled" ? false : "");
            record.itemId = r.id;
            return record;
        });
        Menu.syncRows(stable, mapped);
        const found = rows.findIndex(r => r.id === currentId);
        current = found >= 0 ? found : Math.max(0, Math.min(current, rows.length - 1));
        currentId = rows.length ? rows[current].id : "";
        if (hadFocus) Qt.callLater(function() {
            if (rows.length) {
                const item = entries.itemAt(current).item;
                if (item) { item.forceActiveFocus(); root.reveal(item); }
            } else root.emptyFocused();
        });
    }
    function move(delta: int): void {
        if (!rows.length) return;
        current = (current + delta + rows.length) % rows.length;
        currentId = rows[current].id;
        const item = entries.itemAt(current).item;
        item.forceActiveFocus();
        root.reveal(item);
    }
    ListModel { id: stable }
    Repeater {
        id: entries
        model: stable
        delegate: Loader {
            id: row
            required property string itemId
            readonly property var modelData: root.rows.find(r => r.id === itemId)
            required property int index
            width: root.width
            sourceComponent: root.choices ? choice : root.services ? service : tool
            Component {
                id: tool
                ToolRow {
                    tool: row.modelData
                    activeFocusOnTab: row.index === root.current
                    onClicked: { root.current = row.index; root.currentId = row.modelData.id; root.inspected(row.modelData.id); }
                    Keys.onPressed: event => root.key(event)
                }
            }
            Component {
                id: service
                ServiceRow {
                    service: row.modelData
                    activeFocusOnTab: row.index === root.current
                    onClicked: { root.current = row.index; root.currentId = row.modelData.id; root.inspected(row.modelData.id); }
                    Keys.onPressed: event => root.key(event)
                }
            }
            Component {
                id: choice
                ActionButton {
                    implicitHeight: Math.max(64 * scale, contentItem.implicitHeight + 20 * scale)
                    text: row.modelData ? row.modelData.label : ""
                    activeFocusOnTab: row.index === root.current
                    Accessible.role: Accessible.ListItem
                    onClicked: { root.current = row.index; root.currentId = row.itemId; root.inspected(row.itemId); }
                    Keys.onPressed: event => root.key(event)
                }
            }
        }
    }
    function key(event: var): void {
        if (event.key === Qt.Key_Up || event.key === Qt.Key_K || event.key === Qt.Key_Down || event.key === Qt.Key_J) {
            move(event.key === Qt.Key_Up || event.key === Qt.Key_K ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
            root.inspected(currentId);
            event.accepted = true;
        }
    }
}
