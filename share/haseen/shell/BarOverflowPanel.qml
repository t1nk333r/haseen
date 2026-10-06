import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import qs.Compat as Compat
import "PanelPlacement.js" as Placement

// The overflow panel (architecture 5.3): the widgets that did not fit the bar,
// live, in a wrapping grid of cells with each widget's name under it. It
// slides out of the bar under the overflow button (PanelPlacement.offset,
// the rule every panel follows), and Escape or a click outside closes it.
//
// The window spans the whole bar edge from the popups' origin and is
// transparent outside the card, which alone takes input (mask). Spanning it
// is what lets a widget in here open its own popup at the right place: native
// panels read the press through Bar.reportPress, and Omarchy widgets' popups
// (Ui/KeyboardPanel, Ui/PopupCard) take the window their widget sits in for
// the bar, so they open just below this panel, under the widget.
//
// An Omarchy popup opened from a widget in here is anchored to that widget,
// so the panel stays open under it (`hold`), handing it the keyboard and the
// pointer, and closes with it: Escape or a click outside closes both. Native
// panels open in their own popup, whose focus grab closes this one, as one
// popup at a time does elsewhere.
//
// Arrange mode (Bar.arranging) also shows four edge buttons that move the
// bar (`haseen bar position`), and takes drops: a widget dragged here from
// the bar (or within the panel) lands in front of the cell under the
// pointer (`dropBefore`, Bar.dropAt), marked by an accent line.
PanelWindow {
    id: panel

    required property var barWindow
    // Shown overflow ids, in panel order.
    required property var ids
    // The overflow button's centre along the bar.
    required property real centre
    readonly property string edge: barWindow.position
    readonly property bool vertical: barWindow.vertical
    readonly property bool atStart: edge === "top" || edge === "left"
    property bool hold: false
    // Arrange mode (Bar.arranging), toggled from the footer.
    property bool arranging: false
    // Where a dragged widget would land here: in front of this id, "" at
    // the end, null when the drag is elsewhere.
    property var dropBefore: null
    // 0 tucked under the bar .. 1 out.
    property real reveal: 0
    readonly property real travel: (vertical ? card.width : card.height) + Theme.gap
    // Omarchy popups (Ui/KeyboardPanel) measure their distance from the
    // screen edge by their widget's window size, taking that window for a
    // bar at the edge. This one starts a bar's thickness away from it, so it
    // reaches that much further than the card, transparent and without
    // input, and their popups open below the card rather than over it.
    readonly property int tail: Config.barThickness

    signal closeRequested
    signal arrangeToggled
    signal positionRequested(string pos)

    // This window's origin in the bar window's coordinates. Along the edge
    // both start at the popups' origin, the bar reaching `overlap` further;
    // across it, this window starts where the bar's exclusive zone ends.
    function origin(): point {
        const b = barWindow;
        if (edge === "top")
            return Qt.point(b.overlap, b.height);
        if (edge === "bottom")
            return Qt.point(b.overlap, -height);
        if (edge === "left")
            return Qt.point(b.width, b.overlap);
        return Qt.point(-width, b.overlap);
    }

    function toBar(x: real, y: real): point {
        const o = origin();
        return Qt.point(x + o.x, y + o.y);
    }

    function fromBar(x: real, y: real): point {
        const o = origin();
        return Qt.point(x - o.x, y - o.y);
    }

    function cardContains(x: real, y: real): bool {
        return x >= card.x && y >= card.y && x < card.x + card.width && y < card.y + card.height;
    }

    // The card's background contrasts with the widgets' text colour, which
    // follows the wallpaper while the bar is transparent (Theme.barForeground
    // is then either the theme's foreground or its background).
    function lightness(c: color): real {
        return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
    }
    readonly property color cardColor: Math.abs(lightness(Theme.barForeground) - lightness(Theme.background)) >= Math.abs(lightness(Theme.barForeground) - lightness(Theme.foreground)) ? Theme.background : Theme.foreground

    anchors {
        top: edge !== "bottom"
        bottom: edge !== "top"
        left: edge !== "right"
        right: edge !== "left"
    }
    exclusiveZone: 0
    implicitWidth: vertical ? card.width + Theme.gap + tail : 1
    implicitHeight: vertical ? 1 : card.height + Theme.gap + tail
    color: "transparent"
    mask: Region {
        item: card
    }
    WlrLayershell.namespace: "haseen-panel"
    WlrLayershell.layer: WlrLayer.Top
    // The keyboard is primed as in PanelPopup.qml: Exclusive when the panel
    // appears, so Escape reaches it, then OnDemand once the window is active,
    // so a click outside clears the focus grab. While an Omarchy popup opened
    // from here is up, that popup has it.
    property bool focusPrimed: false
    WlrLayershell.keyboardFocus: hold ? WlrKeyboardFocus.None : focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    Connections {
        target: card.Window

        function onActiveChanged(): void {
            if (card.Window.active)
                panel.focusPrimed = true;
        }
    }

    // Before item delivery, so a widget in here that takes the key press
    // cannot keep Escape from closing the panel.
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: panel.closeRequested()
    }

    Component.onCompleted: reveal = 1

    Behavior on reveal {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCubic
        }
    }

    // The bar is inside the grab: its button closes the panel itself, and a
    // press on another bar widget is not an outside click.
    HyprlandFocusGrab {
        windows: [panel, panel.barWindow]
        active: panel.visible && !panel.hold
        // While held, the grab is off and its end means nothing.
        onCleared: {
            if (!panel.hold)
                panel.closeRequested();
        }
    }

    // A popup that becomes active right after a press on a widget in here is
    // that widget's.
    Connections {
        target: Compat.Runtime

        function onActivePopoutChanged(): void {
            if (Compat.Runtime.activePopout === null) {
                if (panel.hold)
                    panel.closeRequested();
            } else if (Placement.opener({
                    extent: 1,
                    time: panel.barWindow.overflowPressTime
                }, Date.now()) !== null) {
                panel.hold = true;
            } else {
                // Another widget's popup (one in the bar): one at a time.
                panel.closeRequested();
            }
        }
    }

    Rectangle {
        id: card

        readonly property real along: Placement.offset(panel.centre, panel.vertical ? height : width, panel.barWindow.extent, Theme.gap)
        // A gap off the bar, sliding out from under it; the tail is on the
        // far side.
        readonly property real across: (panel.atStart ? Theme.gap : panel.tail) + (panel.atStart ? -1 : 1) * (1 - panel.reveal) * panel.travel
        readonly property int padding: Theme.gap * 2
        readonly property real maxContent: panel.vertical ? Theme.fontSize * 24 : Math.min(panel.barWindow.extent - 2 * Theme.gap - 2 * padding, Theme.fontSize * 40)
        readonly property real contentWidth: Math.max(grid.childrenRect.width, Theme.fontSize * 16)

        x: panel.vertical ? across : along
        y: panel.vertical ? along : across
        width: contentWidth + 2 * padding
        height: content.implicitHeight + 2 * padding
        color: panel.cardColor
        radius: Theme.radius
        border.color: panel.dropBefore === "" ? Theme.accent : Theme.border
        border.width: panel.dropBefore === "" ? Theme.borderWidth * 2 : Theme.borderWidth
        focus: true

        // In front of the cell a dragged widget would land before.
        Rectangle {
            readonly property Item target: typeof panel.dropBefore === "string" && panel.dropBefore !== "" ? panel.barWindow.cells[panel.dropBefore] || null : null
            readonly property point at: target ? target.mapToItem(card, 0, 0) : Qt.point(0, 0)

            z: 1
            visible: target !== null
            x: Math.round(at.x - Theme.gap / 2 - width / 2)
            y: at.y
            width: 2
            height: target ? target.height : 0
            radius: 1
            color: Theme.accent
        }

        Column {
            id: content

            x: card.padding
            y: card.padding
            spacing: Theme.gap

            // Wraps at maxContent; the card takes only the width used.
            Flow {
                id: grid

                width: card.maxContent
                spacing: Theme.gap

                Repeater {
                    // Diffed, so a widget coming back to the bar leaves the
                    // others' cells (and their widgets) where they are.
                    model: ScriptModel {
                        values: panel.ids
                    }

                    delegate: BarOverflowCell {
                        bar: panel.barWindow
                    }
                }
            }

            // Arrange: clicks and drags move widgets instead of reaching
            // them (BarSection.qml), so placing them needs no modifier key.
            Row {
                spacing: Theme.gap

                Text {
                    width: card.contentWidth - arrangeButton.width - Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.arranging ? "Drag a widget to move it, here included; a click moves it between the bar and here" : "Widgets moved off the bar"
                    wrapMode: Text.WordWrap
                    color: Theme.barForeground
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(8, Theme.fontSize - 3)
                }

                BarButton {
                    id: arrangeButton

                    height: Theme.fontSize * 2
                    glyph: "\uf0ec"
                    text: panel.arranging ? "Done" : "Arrange"
                    highlighted: panel.arranging
                    onClicked: button => {
                        if (button === Qt.LeftButton)
                            panel.arrangeToggled();
                    }
                }
            }

            // While arranging: the screen edge the bar sits on.
            Row {
                visible: panel.arranging
                spacing: Theme.gap

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Bar edge"
                    color: Theme.barForeground
                    opacity: 0.6
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(8, Theme.fontSize - 3)
                }

                Repeater {
                    model: [
                        {
                            pos: "top",
                            glyph: "\uf062"
                        },
                        {
                            pos: "bottom",
                            glyph: "\uf063"
                        },
                        {
                            pos: "left",
                            glyph: "\uf060"
                        },
                        {
                            pos: "right",
                            glyph: "\uf061"
                        }
                    ]

                    delegate: BarButton {
                        required property var modelData

                        height: Theme.fontSize * 2
                        glyph: modelData.glyph
                        highlighted: panel.edge === modelData.pos
                        onClicked: button => {
                            if (button === Qt.LeftButton && panel.edge !== modelData.pos)
                                panel.positionRequested(modelData.pos);
                        }
                    }
                }
            }
        }
    }
}
