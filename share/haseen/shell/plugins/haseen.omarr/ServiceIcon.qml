import QtQuick
import qs.Haseen
import "Model.js" as Model

// One service's mark from icons/ (Model.iconSlug), or its initial on a tile
// when there is none, with an optional health dot in the corner.
//
// Adapted from ServiceIcon.qml in omARR (MIT, Copyright (c) 2026 luccast),
// as the owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside
// this file. haseen changes: the tile and the dot take theme tokens.
Item {
    id: root

    property var service: ({})
    readonly property string slug: Model.iconSlug(service)
    property real iconSize: Math.round(Theme.fontSize * 1.5)
    property string health: ""
    property color healthColor: Theme.foreground
    readonly property bool showHealth: health !== ""

    width: iconSize
    height: iconSize
    implicitWidth: iconSize
    implicitHeight: iconSize

    Image {
        id: img

        anchors.fill: parent
        visible: root.slug !== "" && status !== Image.Error
        source: root.slug !== "" ? Qt.resolvedUrl("icons/" + root.slug + ".svg") : ""
        sourceSize.width: Math.round(root.iconSize * 2)
        sourceSize.height: Math.round(root.iconSize * 2)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
    }

    Rectangle {
        visible: !img.visible
        anchors.fill: parent
        radius: width * 0.22
        color: Theme.surfaceAlt
        border.color: Theme.border
        border.width: Theme.borderWidth

        Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: {
                const n = root.service && root.service.name ? String(root.service.name) : "?";
                return n.charAt(0).toUpperCase();
            }
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(8, Math.round(root.iconSize * 0.46))
            font.bold: true
        }
    }

    Rectangle {
        visible: root.showHealth
        width: Math.max(6, Math.round(root.iconSize * 0.3))
        height: width
        radius: width / 2
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        color: root.healthColor
        border.color: Theme.surface
        border.width: 1
    }
}
