import QtQuick
import qs.Haseen
import qs.Haseen.Widgets

// Stay Awake indicator: a coffee cup while the `idle-off` flag is set
// (`haseen toggle idle`), nothing otherwise. A click allows idle again.
// It is the only on-screen sign that the screen will never lock by itself.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    visible: Flags.idleOff
    implicitWidth: visible ? contentWidth : 0
    glyph: "\u{F0176}"
    onClicked: Flags.set("idle-off", false)
}
