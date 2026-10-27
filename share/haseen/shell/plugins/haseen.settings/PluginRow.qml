import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Written for haseen's port (plan 096); no upstream code.
// One plugin: name, id · origin · state (and why it does not load), the
// on/off switch, the settings button when its manifest declares any, and for
// a plugin installed under ~/.config/haseen/plugins a select box and delete.
Item {
    id: root

    property var row: ({})
    property string stateText: ""
    property bool busy: false
    property bool selected: false

    signal toggled(bool on)
    signal openSettings
    signal select
    signal remove

    readonly property string problem: !row.valid ? (row.errors || []).map(e => e.message || e).join("; ") : (row.unmet || []).join("; ")

    height: Math.round(Theme.fontSize * (problem !== "" ? 4.2 : 3))

    Rectangle {
        anchors.fill: parent
        radius: Theme.radius
        color: root.selected ? Theme.selection : Theme.surfaceAlt
        visible: root.selected || hover.containsMouse
    }

    MouseArea {
        id: hover

        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    BarButton {
        id: box

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.fontSize * 2
        visible: root.row.deleteName !== ""
        glyph: root.selected ? "\u{f0132}" : "\u{f0131}"
        color: Theme.foreground
        onClicked: root.select()
    }

    Column {
        anchors.left: box.visible ? box.right : parent.left
        anchors.leftMargin: Theme.gap
        anchors.right: actions.left
        anchors.rightMargin: Theme.gap
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.row.name
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.row.valid && root.row.unmet.length === 0 ? Theme.foreground : Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
        }

        Text {
            width: parent.width
            text: root.row.id + " · " + root.row.origin + " · " + root.stateText
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }

        Text {
            width: parent.width
            visible: root.problem !== ""
            text: root.problem
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: Theme.warning
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    Row {
        id: actions

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: Theme.fontSize * 2
        spacing: 2

        BarButton {
            height: parent.height
            visible: root.row.settingKeys.length > 0
            glyph: "\u{f0493}"
            color: Theme.foreground
            onClicked: root.openSettings()
        }

        BarButton {
            height: parent.height
            visible: root.row.valid
            text: root.busy ? "…" : root.row.enabled && root.row.listed ? I18n.tr("On") : I18n.tr("Off")
            highlighted: root.row.enabled && root.row.listed
            color: root.row.enabled && root.row.listed ? Theme.accent : Theme.muted
            onClicked: if (!root.busy)
                root.toggled(!(root.row.enabled && root.row.listed))
        }

        BarButton {
            height: parent.height
            visible: root.row.deleteName !== ""
            glyph: ""
            color: Theme.muted
            onClicked: root.remove()
        }
    }
}
