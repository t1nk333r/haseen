// Adapted from Omarchy shell/Ui/KeyboardPanel.qml and PopupCard.qml (the
// card) and Ui/BorderSurface.qml. MIT, Copyright (c) David Heinemeier Hansson.
// haseen: sized to its content, theme tokens from qs.Haseen.
import QtQuick
import qs.Haseen

// The card a panel lives in, as Omarchy draws its panels' card: the
// [popups] background, the Hyprland active border (its gradient where the
// theme has one) max(1, space(2)) = 2 px wide, Hyprland's corner rounding and
// popup-padding (14 px) inside the border (KeyboardPanel.qml:45,48,391-399;
// PopupCard.qml:14,17-18,151-157). Sized to its content.
Rectangle {
    id: root

    default property alias content: box.data
    property int padding: Theme.spacing.popupPadding
    property var borderSpec: Theme.popups.borderSpec
    // Off for a panel that draws its own card (PanelPopup's overlay).
    property bool bordered: true

    readonly property int borderInset: bordered && borderSpec && borderSpec.width > 0 ? borderSpec.width : 0
    readonly property bool gradientBorder: !!(borderSpec && borderSpec.gradient && borderSpec.gradient.enabled)

    implicitWidth: box.childrenRect.width + (padding + borderInset) * 2
    implicitHeight: box.childrenRect.height + (padding + borderInset) * 2
    color: Theme.popups.background
    radius: Theme.radius
    border.color: gradientBorder ? "transparent" : (borderSpec ? borderSpec.color : "transparent")
    border.width: gradientBorder ? 0 : borderInset

    Loader {
        anchors.fill: parent
        active: root.gradientBorder && root.borderInset > 0
        z: 1

        sourceComponent: BorderRing {
            spec: root.borderSpec
            radius: root.radius
        }
    }

    Item {
        id: box
        x: root.padding + root.borderInset
        y: root.padding + root.borderInset
        width: childrenRect.width
        height: childrenRect.height
    }
}
