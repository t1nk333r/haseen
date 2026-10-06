import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Indicators.js" as Logic

// One indicator: full when its state is on, dimmed when it is only revealed
// so it can be switched on. A click runs the command that flips the state.
BarButton {
    id: button

    required property var modelData
    // The Widget, which owns the single tooltip.
    required property Item host

    readonly property var cell: Logic.cell(modelData.id, modelData.active)

    // Not the parent's height: a Grid's parent is 0 high until it has width,
    // and Grid skips zero-sized children.
    height: vertical ? implicitHeight : Config.barHeight
    padding: Math.round(Theme.gap * 0.75)
    glyph: cell.glyph
    opacity: modelData.active ? 1 : 0.45
    onClicked: Quickshell.execDetached(cell.command)

    HoverHandler {
        onHoveredChanged: button.host.showTip(button, hovered)
    }
}
