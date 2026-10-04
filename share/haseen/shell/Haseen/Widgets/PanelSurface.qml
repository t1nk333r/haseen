import QtQuick
import qs.Haseen

// The card a panel lives in: theme surface, border, radius, padding. Sized
// to its content.
Rectangle {
    id: root

    default property alias content: box.data
    property int padding: Theme.gap * 2

    implicitWidth: box.childrenRect.width + padding * 2
    implicitHeight: box.childrenRect.height + padding * 2
    color: Theme.surface
    radius: Theme.radius
    border.color: Theme.border
    border.width: Theme.borderWidth

    Item {
        id: box
        x: root.padding
        y: root.padding
        width: childrenRect.width
        height: childrenRect.height
    }
}
