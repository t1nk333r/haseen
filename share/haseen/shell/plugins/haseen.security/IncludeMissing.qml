import QtQuick
import QtQuick.Controls as Controls
import qs.Haseen
Controls.CheckBox {
    id: root
    text: I18n.tr("Include missing")
    height: Math.max(40, implicitHeight)
    Accessible.name: text
    Accessible.description: I18n.tr("Read inventory diagnostics; provisioning reports are not installed evidence.")
    activeFocusOnTab: true
    palette.text: Theme.foreground
    palette.windowText: Theme.foreground
    palette.button: Theme.surfaceAlt
    palette.buttonText: Theme.foreground
    palette.highlight: Theme.foreground
    palette.highlightedText: Theme.surface
    // The box sits at the start of the row: on the right in a mirrored
    // (right-to-left) panel, with the text clearing it there.
    contentItem: Label { text: root.text; verticalAlignment: Text.AlignVCenter; leftPadding: LayoutMirroring.enabled ? 0 : root.indicator.width + 12; rightPadding: LayoutMirroring.enabled ? root.indicator.width + 12 : 0 }
    indicator: Rectangle {
        x: LayoutMirroring.enabled ? root.width - width - 2 : 2; y: (root.height - height) / 2
        width: 24; height: 24; color: Theme.surfaceAlt; radius: Theme.radius
        border.width: root.activeFocus ? 2 : Theme.borderWidth
        border.color: root.activeFocus ? Theme.foreground : Theme.border
        Label { anchors.centerIn: parent; text: root.checked ? "✓" : "" }
    }
    background: Rectangle { color: Theme.surface; radius: Theme.radius; border.width: root.activeFocus ? 2 : 0; border.color: Theme.foreground }
}
