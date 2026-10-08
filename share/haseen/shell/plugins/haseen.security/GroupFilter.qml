import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Controls.ComboBox {
    id: root
    height: Math.max(40, implicitHeight)
    Accessible.name: "Tool group filter"
    activeFocusOnTab: true
    font.family: Theme.fontFamily
    font.pixelSize: Math.round(12 * Theme.fontSize / 11)
    palette.window: Theme.surface
    palette.base: Theme.surface
    palette.button: Theme.surfaceAlt
    palette.text: Theme.foreground
    palette.buttonText: Theme.foreground
    palette.windowText: Theme.foreground
    palette.highlight: Theme.surfaceAlt
    palette.highlightedText: Theme.foreground
    contentItem: Label { text: root.displayText; verticalAlignment: Text.AlignVCenter; leftPadding: 12; rightPadding: 24 }
    background: Rectangle { color: Theme.surfaceAlt; radius: Theme.radius; border.width: root.activeFocus ? 2 : Theme.borderWidth; border.color: root.activeFocus ? Theme.foreground : Theme.border }
}
