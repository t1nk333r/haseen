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
        border.color: Theme.border
        border.width: Theme.borderWidth
        focus: true

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

            // Arrange: clicks move widgets instead of reaching them
            // (BarSection.qml), so placing them needs no modifier key.
            Row {
                spacing: Theme.gap

                Text {
                    width: card.contentWidth - arrangeButton.width - Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    text: panel.arranging ? "Click a bar widget to move it here, or one here to keep it in the bar" : "Widgets moved off the bar"
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
        }
    }
}
