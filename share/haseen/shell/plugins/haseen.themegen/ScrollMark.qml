import QtQuick
import qs.Haseen

// A 2 px scroll mark on a grid's right edge, shown only while the grid holds
// more rows than it shows, so two full rows never hide that more are there.
Item {
    id: root

    required property Flickable view

    parent: view
    anchors.right: view.right
    width: 2
    height: view.height
    visible: view.visibleArea.heightRatio < 1

    Rectangle {
        anchors.fill: parent
        radius: 1
        color: Theme.border
    }

    Rectangle {
        width: parent.width
        y: root.view.visibleArea.yPosition * root.height
        height: Math.max(Theme.gap, root.view.visibleArea.heightRatio * root.height)
        radius: 1
        color: Theme.accent
    }
}
