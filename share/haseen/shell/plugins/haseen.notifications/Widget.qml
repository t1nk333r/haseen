import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Do-not-disturb indicator: a crossed-out bell while the `dnd` flag is set
// (`haseen toggle dnd`, the panel button, `notifications toggleDnd`),
// nothing otherwise. A click lets notifications through again.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    visible: Flags.dnd
    implicitWidth: visible ? contentWidth : 0
    glyph: "\u{F009B}"
    onClicked: Flags.set("dnd", false)
}
