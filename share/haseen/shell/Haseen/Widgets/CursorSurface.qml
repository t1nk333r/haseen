// Adapted from Omarchy shell/Ui/CursorSurface.qml. MIT, Copyright (c) David
// Heinemeier Hansson.
// haseen: theme tokens from qs.Haseen; flat borders.
import QtQuick
import qs.Haseen

// The chrome of a row a panel's keyboard cursor and the mouse both move
// over (plan 115). The row's visuals follow `hasCursor` and `current` only,
// never its own hover, so one highlight shows at a time: the panel sets
// hasCursor from the pointer and the keys alike. hasCursor paints the
// hover-cursor fill and border, current the selected fill (and border, 0 px
// by default), `bordered` the normal border at rest.
Rectangle {
    property bool hasCursor: false
    property bool current: false
    property bool bordered: false
    property color foreground: Theme.foreground
    property color accent: Theme.accent
    // The row's colour at rest: transparent on a plain card, or a panel's
    // surface where its rows sat on one before (kblayout).
    property color background: "transparent"

    radius: Theme.radius
    color: hasCursor ? Theme.hoverFillFor(foreground, accent) : current ? Theme.selectedFillFor(foreground, accent) : background
    border.color: hasCursor ? Theme.hoverBorderFor(foreground, accent) : current ? Theme.selectedBorderFor(foreground, accent) : bordered ? Theme.normalBorderFor(foreground, accent) : "transparent"
    border.width: hasCursor ? Theme.hoverBorderWidth : current ? Theme.selectedBorderWidth : bordered ? Theme.normalBorderWidth : 0

    Behavior on color {
        ColorAnimation {
            duration: Theme.duration(60)
        }
    }
}
