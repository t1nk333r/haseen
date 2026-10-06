import QtQuick
import qs.Haseen

// One cell of the overflow panel: the widget's own bar slot, moved in from
// the bar while the panel is open (BarSection.qml), with the widget's name
// under it. The slot keeps the size it has in the bar, so a widget looks and
// answers clicks exactly as it does there.
Column {
    id: cell

    required property string modelData
    required property var bar
    readonly property var record: Plugins.registry[modelData]

    spacing: 2

    Item {
        id: holder

        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.max(childrenRect.width, 1)
        height: Math.max(childrenRect.height, 1)

        Component.onCompleted: cell.bar.registerCell(cell.modelData, holder)
        Component.onDestruction: cell.bar.unregisterCell(cell.modelData, holder)
    }

    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: Math.min(Math.max(holder.width, Theme.fontSize * 4), Theme.fontSize * 9)
        text: cell.record && cell.record.name ? cell.record.name : cell.modelData
        elide: Text.ElideRight
        horizontalAlignment: Text.AlignHCenter
        color: Theme.barForeground
        opacity: 0.7
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(8, Theme.fontSize - 3)
    }
}
