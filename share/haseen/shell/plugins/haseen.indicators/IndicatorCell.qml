import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Indicators.js" as Logic

// One indicator: full when its state is on, dimmed when it is off. A click
// runs the command that flips the state. The cell keeps its place when the
// state flips under the pointer (Widget.qml); only its look and command
// follow the state.
BarButton {
    id: button

    // The entry id (Indicators.js).
    required property string modelData
    // The Widget, which owns the single tooltip.
    required property Item host
    property bool active: false

    readonly property var cell: Logic.cell(modelData, active)

    // Not the parent's height: a Grid's parent is 0 high until it has width,
    // and Grid skips zero-sized children.
    height: vertical ? implicitHeight : Config.barHeight
    padding: Math.round(Theme.gap * 0.75)
    glyph: cell.glyph
    opacity: active ? 1 : 0.45
    onClicked: Quickshell.execDetached(cell.command)
    onCellChanged: {
        if (tip.hovered)
            button.host.showTip(button, true);
    }

    HoverHandler {
        id: tip
        onHoveredChanged: button.host.showTip(button, hovered)
    }
}
