import QtQuick
import qs.Haseen

// @ID@: panel. Open it with `haseen shell ipc panel toggle @ID@`; the host
// draws the surface and closes it on Escape or an outside click.
Column {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    spacing: Theme.gap

    Text {
        text: root.pluginId
        color: Theme.accent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize + 2
    }

    Text {
        text: "Edit " + root.pluginId + "/Panel.qml"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
