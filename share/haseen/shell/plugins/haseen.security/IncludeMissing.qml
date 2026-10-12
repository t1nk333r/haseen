import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Controls.CheckBox {
    id: root
    text: "Include missing"
    height: Math.max(40, implicitHeight)
    Accessible.name: text
    Accessible.description: "Read inventory diagnostics; provisioning reports are not installed evidence."
    activeFocusOnTab: true
    palette.text: Theme.foreground
    palette.windowText: Theme.foreground
    palette.button: Theme.surfaceAlt
    palette.buttonText: Theme.foreground
    palette.highlight: Theme.foreground
    palette.highlightedText: Theme.surface
    contentItem: Label { text: root.text; verticalAlignment: Text.AlignVCenter; leftPadding: root.indicator.width + 12 }
    indicator: Rectangle {
        x: 2; y: (root.height - height) / 2
        width: 24; height: 24; color: Theme.surfaceAlt; radius: Theme.radius
        border.width: root.activeFocus ? 2 : Theme.borderWidth
        border.color: root.activeFocus ? Theme.foreground : Theme.border
        Label { anchors.centerIn: parent; text: root.checked ? "✓" : "" }
    }
    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.width: root.activeFocus ? 2 : 0; border.color: Theme.foreground }
}
