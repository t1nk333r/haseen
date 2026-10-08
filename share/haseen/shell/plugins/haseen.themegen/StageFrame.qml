import QtQuick
import qs.Haseen

// One area of haseen.themegen's keyboard flow (plan 083): the pictures or the
// palette. The area the keys act on is framed in the accent; the other keeps
// the same frame unseen, so a stage change moves nothing.
Rectangle {
    id: root

    property bool active: false
    default property alias content: column.data
    readonly property int pad: Math.round(Theme.gap / 2)

    implicitHeight: column.implicitHeight + pad * 2
    radius: Theme.radius
    color: "transparent"
    border.color: active ? Theme.accent : "transparent"
    border.width: Theme.borderWidth

    Column {
        id: column

        x: root.pad
        y: root.pad
        width: root.width - root.pad * 2
        spacing: Theme.gap
    }
}
