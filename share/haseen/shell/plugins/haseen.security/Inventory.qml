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
    property real viewportHeight: 0
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
            root.forceLayout();
            if (rows.length) {
                const item = entries.itemAt(current).item;
                if (item) { item.forceActiveFocus(); root.reveal(item); }
            } else root.emptyFocused();
        });
    }
    function focusIndex(index: int): void {
        if (!rows.length) { root.emptyFocused(); return; }
        root.forceLayout();
        current = Math.max(0, Math.min(index, rows.length - 1));
        currentId = rows[current].id;
        const item = entries.itemAt(current).item;
        if (item) item.forceActiveFocus();
    }
    function move(delta: int): void { focusIndex(current + delta); }
    function pageMove(direction: int): void {
        if (!rows.length) return;
        const origin = entries.itemAt(current);
        let target = current;
        for (let i = current + direction; i >= 0 && i < rows.length; i += direction) {
            target = i;
            if (Math.abs(entries.itemAt(i).y - origin.y) >= viewportHeight) break;
        }
        focusIndex(target);
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
                    activeFocusOnTab: activeFocus || row.index === root.current
                    explanation: (tool ? tool.reason : "") + ". Item " + (row.index + 1) + " of " + root.rows.length
                    onActiveFocusChanged: if (activeFocus) { root.current = row.index; root.currentId = row.itemId; root.reveal(this); }
                    onClicked: { root.current = row.index; root.currentId = row.modelData.id; root.inspected(row.modelData.id); }
                    Keys.onPressed: event => root.key(event)
                }
            }
            Component {
                id: service
                ServiceRow {
                    service: row.modelData
                    activeFocusOnTab: activeFocus || row.index === root.current
                    explanation: (service ? service.ownership + ". " + service.reason : "") + ". Item " + (row.index + 1) + " of " + root.rows.length
                    onActiveFocusChanged: if (activeFocus) { root.current = row.index; root.currentId = row.itemId; root.reveal(this); }
                    onClicked: { root.current = row.index; root.currentId = row.modelData.id; root.inspected(row.modelData.id); }
                    Keys.onPressed: event => root.key(event)
                }
            }
            Component {
                id: choice
                ActionButton {
                    implicitHeight: Math.max(64 * scale, contentItem.implicitHeight + 24 * scale)
                    text: row.modelData ? row.modelData.label : ""
                    activeFocusOnTab: activeFocus || row.index === root.current
                    Accessible.role: Accessible.ListItem
                    explanation: "Item " + (row.index + 1) + " of " + root.rows.length
                    onActiveFocusChanged: if (activeFocus) { root.current = row.index; root.currentId = row.itemId; root.reveal(this); }
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
        } else if (event.key === Qt.Key_Home || event.key === Qt.Key_End) {
            focusIndex(event.key === Qt.Key_Home ? 0 : rows.length - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) {
            pageMove(event.key === Qt.Key_PageUp ? -1 : 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.inspected(currentId);
            event.accepted = true;
        }
    }
}
