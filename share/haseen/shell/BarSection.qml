import QtQuick
import Quickshell
import qs.Haseen
import "BarDrag.js" as BarDrag

// A row (or, in a left/right bar, a column) of bar-widget cells. Disabled
// ids are filtered out; unknown ones are skipped by PluginSlot with one log
// line. The widgets themselves live in the bar's pool (BarStrip.qml,
// BarSlot.qml): each cell here registers itself as the place for its id,
// takes the size of that id's slot, and the slot moves in (plan 112). So a
// widget that changes sections, or moves within one, is never rebuilt: only
// its cell is.
//
// A widget that is invisible or reports implicitWidth 0 (its "hidden" signal
// in both orientations) gets a zero-size slot, so a zero-size cell:
// positioners neither place nor space zero-size children, so it adds no gap.
//
// Overflow (Overflow.js): an overflowed widget's cell shrinks to nothing (the
// grid skips it) and its slot moves into the overflow panel's cell while the
// panel is open, back here when it closes; here it is clipped, never made
// invisible, so a widget whose width follows its own visibility
// (`implicitWidth: visible ? w : 0`) keeps reporting its size.
//
// While a widget is dragged its cell folds away too (its ghost follows the
// pointer) and the section the drop would land in opens a room of the
// widget's length where it would land (BarDrag.rows), so its neighbours
// make way as the pointer moves.
Grid {
    id: section

    required property var ids
    // "left", "center" or "right": where a drop's `section` points.
    required property string name
    // The bar's strip (BarStrip.qml) or a stand-in with the same members.
    required property var host
    property bool vertical: false
    readonly property var shownIds: ids.filter(id => Config.isEnabled(id))
    readonly property var rows: BarDrag.rows(shownIds, name, host.dragId !== "" ? host.drop : null)

    // The shown widgets still in the bar, in order, as [{ id, start, end }]
    // along the bar in `target`'s coordinates (Overflow.dropTarget). A
    // dragged widget counts where it was: the drag reads this as it starts.
    function spans(target: Item): var {
        const out = [];
        for (let i = 0; i < repeater.count; i++) {
            const c = repeater.itemAt(i);
            if (!c || c.room || c.overflowed || c.slotLength <= 0)
                continue;
            const p = c.mapToItem(target, 0, 0);
            const start = vertical ? p.y : p.x;
            out.push({
                id: c.modelData,
                start: start,
                end: start + c.slotLength
            });
        }
        return out;
    }

    objectName: "barSection-" + name
    // Column count only (no `rows`): flipping both at once briefly asks for
    // a 1x1 grid and Qt warns.
    columns: vertical ? 1 : Math.max(1, rows.length)
    spacing: Math.round(Theme.gap / 2)
    // Neighbours glide aside while a drag moves the room, and only then.
    move: host.dragId !== "" ? roomMove : null

    Transition {
        id: roomMove

        NumberAnimation {
            properties: "x,y"
            duration: 120
            easing.type: Easing.OutCubic
        }
    }

    Repeater {
        id: repeater

        model: ScriptModel {
            values: section.rows
        }

        delegate: Item {
            id: cell

            required property string modelData
            readonly property bool room: modelData === BarDrag.ROOM
            readonly property Item slot: room ? null : section.host.slots[modelData] || null
            readonly property bool overflowed: !room && section.host.fit.ids.indexOf(modelData) >= 0
            readonly property bool lifted: !room && section.host.dragId === modelData
            readonly property real slotLength: slot ? (section.vertical ? slot.height : slot.width) : 0
            readonly property bool folded: overflowed || lifted

            width: room ? (section.vertical ? section.host.cross : section.host.dragLength) : folded || !slot ? 0 : slot.width
            height: room ? (section.vertical ? section.host.dragLength : section.host.cross) : folded || !slot ? 0 : slot.height
            // Hides a parked or lifted widget without making it invisible.
            clip: folded
            Component.onCompleted: {
                if (!room)
                    section.host.registerSectionCell(modelData, cell);
            }
            Component.onDestruction: {
                if (!room)
                    section.host.unregisterSectionCell(modelData, cell);
            }

            // The room: where the dragged widget would land.
            Rectangle {
                anchors.fill: parent
                anchors.topMargin: section.vertical ? 0 : 3
                anchors.bottomMargin: section.vertical ? 0 : 3
                anchors.leftMargin: section.vertical ? 3 : 0
                anchors.rightMargin: section.vertical ? 3 : 0
                visible: cell.room
                radius: Theme.radius
                color: Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.35)
                border.color: Theme.accent
                border.width: Theme.borderWidth
            }
        }
    }
}
