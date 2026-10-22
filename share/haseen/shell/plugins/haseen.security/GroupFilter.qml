import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Controls.ComboBox {
    id: root
    height: Math.max(40, implicitHeight)
    Accessible.name: I18n.tr("Tool group filter")
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
    // The wider padding clears the indicator, which a mirrored
    // (right-to-left) panel moves to the left.
    contentItem: Label { text: root.displayText; verticalAlignment: Text.AlignVCenter; leftPadding: LayoutMirroring.enabled ? 24 : 12; rightPadding: LayoutMirroring.enabled ? 12 : 24 }
    // Basic's own delegate, but mirrored with the panel: a popup is parented
    // to the window overlay and does not inherit LayoutMirroring.
    delegate: Controls.ItemDelegate {
        required property var modelData
        required property int index
        width: ListView.view.width
        text: modelData
        palette.text: root.palette.text
        palette.highlightedText: root.palette.highlightedText
        font.weight: root.currentIndex === index ? Font.DemiBold : Font.Normal
        highlighted: root.highlightedIndex === index
        hoverEnabled: root.hoverEnabled
        LayoutMirroring.enabled: root.LayoutMirroring.enabled
    }
    background: Rectangle { color: Theme.surfaceAlt; radius: Theme.radius; border.width: root.activeFocus ? 2 : Theme.borderWidth; border.color: root.activeFocus ? Theme.foreground : Theme.border }
}
