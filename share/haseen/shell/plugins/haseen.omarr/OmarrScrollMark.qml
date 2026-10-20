import QtQuick
import qs.Haseen

// A 2 px scroll mark on a Flickable's right edge, shown only while it holds
// more than it shows; it stands in for upstream's ScrollBar.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: the mark of haseen.themegen instead of a Controls
// ScrollBar.
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
