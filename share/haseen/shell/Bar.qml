import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// One bar per screen, on the edge shell.json `bar.position` names. With the
// screen frame on, the bar is the frame's thick edge (Frame.qml draws the
// rest); without it, a hairline marks the inner edge.
//
// This file is the bar's window; what is in it, the widgets, the overflow
// chevron and every gesture on the bar, is BarStrip.qml (plan 112). Here:
// - the overflow panel (BarOverflowPanel.qml), lazy, opened from the chevron
//   or the nook (architecture 5.3). Each bar computes its own overflow, from
//   its own length, so every screen gets its own answer;
// - what a drag shows (BarDragOverlay.qml), lazy, only while one lasts;
// - Escape during a drag from the overflow panel: that panel has the keyboard
//   and puts the widget (or the bar) back. The bar itself never takes it: a
//   layer surface that switches to exclusive keyboard focus mid-gesture loses
//   the pointer grab on Hyprland, which ended every bar drag at once
//   (measured on io, 2026-10-25, plan 120).
//
// Double-clicking the bar asks for transparency (plan 015, after Omarchy's
// shell/plugins/bar/Bar.qml toggleTransparency, MIT, Copyright (c) David
// Heinemeier Hansson; BarStrip.qml). `transparent` comes from
// FrameTextColor: it turns true only once a legible text colour for the
// wallpaper is known.
PanelWindow {
    id: bar

    property bool hidden: false
    property bool transparent: false
    readonly property string position: Config.barPosition
    readonly property bool vertical: Config.barVertical
    // A hidden bar leaves a frame-thick strip so the frame stays closed.
    readonly property int thickness: !hidden ? Config.barThickness : Config.frameEnabled ? Config.frameThickness : 0
    // With the frame on, the bar reaches 1 px under the frame strips at both
    // of its ends (the seam note in Frame.qml).
    readonly property int overlap: Config.frameEnabled ? 1 : 0
    // The bar's length along its edge, as the popups measure it.
    readonly property real extent: strip.extent
    // The nook's widget while it is in this bar (it registers itself).
    property Item nookItem: null

    // The strip's state, for shell.qml, the overflow panel and the nook.
    readonly property var fit: strip.fit
    readonly property var overflowShown: strip.overflowShown
    property alias overflowOpen: strip.overflowOpen
    readonly property bool arranging: strip.arranging
    readonly property var cells: strip.cells
    readonly property string overflowGlyph: strip.overflowGlyph
    readonly property real overflowPressTime: strip.overflowPressTime
    readonly property bool dragging: strip.dragging

    signal transparencyToggleRequested
    // A press on a bar widget, as PanelPlacement.js's opener.
    signal widgetPressed(var opener)
    // A click while arranging: `haseen bar overflow <verb> <id>` (add or pin).
    signal overflowEditRequested(string verb, string id)
    // A drop: `haseen bar move <id> <to> --before <before> [--pin]`.
    signal moveRequested(string id, string to, string before, bool pin)
    // The bar let go of over another edge, or the panel's edge buttons:
    // `haseen bar position <pos>`.
    signal positionRequested(string pos)

    function registerCell(id: string, item: Item): void {
        strip.registerCell(id, item);
    }

    function unregisterCell(id: string, item: Item): void {
        strip.unregisterCell(id, item);
    }

    function toggleOverflowFrom(item: Item): void {
        strip.toggleOverflowFrom(item);
    }

    function setArranging(on: bool): void {
        strip.setArranging(on);
    }

    // Escape, here or in the overflow panel: nothing lands.
    function cancelDrag(): void {
        strip.cancelDrag();
        strip.cancelBarMove();
    }

    visible: thickness > 0
    anchors {
        top: bar.position !== "bottom"
        bottom: bar.position !== "top"
        left: bar.position !== "right"
        right: bar.position !== "left"
    }
    margins {
        top: bar.vertical ? -bar.overlap : 0
        bottom: bar.vertical ? -bar.overlap : 0
        left: bar.vertical ? 0 : -bar.overlap
        right: bar.vertical ? 0 : -bar.overlap
    }
    implicitWidth: thickness
    implicitHeight: thickness
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: thickness
    color: transparent ? Qt.rgba(Theme.background.r, Theme.background.g, Theme.background.b, 0) : Theme.background
    WlrLayershell.namespace: "haseen-bar"
    // Quickshell picks an opaque buffer when the first colour is opaque, and
    // transparency would then render black. Ask for alpha up front.
    surfaceFormat.opaque: false
    WlrLayershell.layer: WlrLayer.Top
    // Never the keyboard: asking for exclusive focus while a drag lasts made
    // Hyprland drop the pointer grab the moment the ghost appeared (plan 120).
    // The strip's 15 s watchdog ends a drag nothing finishes.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // The owner's frame cross-fades with the bar over 420 ms (t1nk33r.screen-frame).
    Behavior on color {
        ColorAnimation {
            duration: 420
            easing.type: Easing.InOutCubic
        }
    }

    BarStrip {
        id: strip

        anchors.fill: parent
        screen: bar.screen
        position: bar.position
        overlap: bar.overlap
        hidden: bar.hidden
        panel: overflowLoader.item
        nookItem: bar.nookItem
        onTransparencyToggleRequested: bar.transparencyToggleRequested()
        onWidgetPressed: opener => bar.widgetPressed(opener)
        onOverflowEditRequested: (verb, id) => bar.overflowEditRequested(verb, id)
        onMoveRequested: (id, to, before, pin) => bar.moveRequested(id, to, before, pin)
        onPositionRequested: pos => bar.positionRequested(pos)
    }

    // Lazy, like every panel: nothing exists until the button is clicked,
    // and closing it frees the window again (the widgets go back to their
    // cells in the bar first, BarSlot.qml).
    LazyLoader {
        id: overflowLoader

        active: strip.overflowOpen && (strip.overflowShown.length > 0 || strip.arranging) && !bar.hidden

        BarOverflowPanel {
            barWindow: bar
            screen: bar.screen
            ids: strip.overflowShown
            centre: strip.overflowCentre >= 0 ? strip.overflowCentre : strip.buttonCentre
            arranging: strip.arranging
            dropBefore: strip.drop !== null && strip.drop.section === "overflow" ? strip.drop.before : null
            onArrangeToggled: strip.setArranging(!strip.arranging)
            onCloseRequested: strip.overflowOpen = false
            onPositionRequested: pos => bar.positionRequested(pos)
        }
    }

    // The ghost of a dragged widget and the edge a moved bar would go to:
    // a window only while a drag lasts.
    LazyLoader {
        active: strip.dragging && !bar.hidden

        BarDragOverlay {
            screen: bar.screen
            stripItem: strip
        }
    }

}
