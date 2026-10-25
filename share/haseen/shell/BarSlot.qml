import QtQuick
import qs.Haseen
import qs.Compat as Compat

// One bar widget on one bar (plan 112): its plugin slot, its hover
// highlight, and what a press on it can start. Each bar keeps one of these
// per shown widget (BarStrip.qml's pool), in whatever section the widget
// sits, and moves it by reparenting: into its section's cell
// (BarSection.qml), into the overflow panel's cell while that is open
// (BarOverflowCell.qml), or parked. A widget is built once and never rebuilt
// by a move, within a section or between sections, so it keeps its state and
// its IPC targets stay single (plan 050).
//
// Vertical bars: every slot is the bar's width. A widget that declares
// `property bool vertical` gets it set and sizes its own height; any other
// widget gets a square cell, clipped, so it stays inside the bar.
//
// Every shown widget gets a hover highlight unless it sets
// `barHoverHighlight: false` (haseen.workspaces).
//
// A press belongs to the widget: a click, the wheel, the right and middle
// buttons and a double click reach it exactly as without the bar around it.
// A DragHandler on the slot only watches (a passive grab) until the pointer
// has travelled `host.dragThreshold` with the left button held; then it
// takes the pointer over, the widget's own press is cancelled (no click),
// and the bar moves the widget where it is dropped (BarStrip.qml). A widget
// keeps a drag of its own in two ways: by Qt's own rule, since a MouseArea
// with drag.target or preventStealing, or a Slider, holds the mouse grab
// (keepMouseGrab) from Qt's smaller drag distance on and cannot be taken
// over; or by setting `barDraggable: false`. The tray never moves.
PluginSlot {
    id: slot

    required property string modelData
    // The bar's strip (BarStrip.qml) or a stand-in with the same members.
    required property var host

    readonly property bool ready: status === Loader.Ready && item !== null
    // Set once per loaded item, not bound: a binding that reads the item's
    // `vertical` while also writing it loops.
    property bool adapts: false
    // `visible` too: an invisible widget with a size (an Omarchy widget
    // hidden by `visible: false`) must not leave an empty, hoverable gap.
    // Compat hosts report their widget's visibility through their
    // implicitWidth (OmarchyHost, DmsHost).
    readonly property bool shown: ready && item.visible && item.implicitWidth > 0
    // The natural length along the bar, wherever the slot sits; the fit is
    // computed from it (Overflow.fit).
    readonly property real length: host.vertical ? height : width
    readonly property bool fixed: host.fixedIds.indexOf(modelData) >= 0
    readonly property bool draggable: shown && !fixed && !(item && item.barDraggable === false)

    parent: host.hostFor(modelData)
    pluginId: modelData
    kind: "bar-widget"
    screen: host.screen
    width: !shown ? 0 : host.vertical ? host.cross : item.implicitWidth
    // Read the item's own `vertical`, not the bar's: while it is still false
    // the widget sizes itself horizontally (height from its parent) and must
    // get a fixed cell.
    height: !shown ? 0 : !host.vertical ? host.cross : adapts && item.vertical ? item.implicitHeight : host.cross
    clip: host.vertical && !adapts
    opacity: host.dragId === modelData ? 0.35 : 1
    // After the load settles: assigning while the Loader is still parenting
    // and sizing the new item trips a binding-loop warning.
    onItemChanged: Qt.callLater(() => {
        adapts = item !== null && ("vertical" in item);
        if (adapts)
            item.vertical = Qt.binding(() => slot.host.vertical);
    })
    onLengthChanged: host.report(modelData, length)
    Component.onCompleted: {
        host.registerSlot(modelData, slot);
        host.report(modelData, length);
    }
    Component.onDestruction: {
        host.unregisterSlot(modelData, slot);
        host.forget(modelData);
    }

    // Hover highlight for every widget, native or compat, drawn behind it
    // with BarButton's tint and insets, so a BarButton widget looks as it
    // always did. On the slot itself, not on the item above the widget: a
    // HoverHandler there takes the hover from the widget's own MouseArea.
    HoverHandler {
        id: hover
    }

    // A widget of haseen's own asks for Omarchy's hover tooltip by setting
    // `barTooltip` (plan 119); adapted widgets keep their own via the compat
    // host. Same window, delay and placement as the adapted ones.
    readonly property string tooltipText: item && typeof item.barTooltip === "string" ? item.barTooltip : ""
    Compat.Tooltip {
        target: hover.hovered && slot.tooltipText !== "" ? slot : null
        text: slot.tooltipText
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: slot.host.vertical ? 0 : 3
        anchors.bottomMargin: slot.host.vertical ? 0 : 3
        anchors.leftMargin: slot.host.vertical ? 3 : 0
        anchors.rightMargin: slot.host.vertical ? 3 : 0
        z: -1
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: hover.hovered && !(slot.item && slot.item.barHoverHighlight === false)
    }

    // Arrange mode (Bar.qml): this takes the press, so the widget never sees
    // it (outlined, so the mode shows), and a click moves the widget between
    // the bar and the overflow panel. A drag still moves it anywhere (the
    // slot's DragHandler takes it over from here).
    MouseArea {
        id: arrange

        anchors.fill: parent
        z: 1
        enabled: slot.host.arranging && !slot.fixed
        hoverEnabled: true
        // Unset outside arrange mode (undefined resets it): a disabled
        // MouseArea's cursor still wins over the widget's own under it.
        cursorShape: !enabled ? undefined : Qt.OpenHandCursor
        onClicked: slot.host.arrangeClicked(slot.modelData)

        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            visible: arrange.enabled
            radius: Theme.radius
            color: arrange.containsMouse ? Qt.rgba(Theme.selection.r, Theme.selection.g, Theme.selection.b, 0.5) : "transparent"
            border.color: Theme.accent
            border.width: Theme.borderWidth
        }
    }

    // Topmost, so it sees every press first: a pointer handler in an item
    // that handles no events itself only takes a passive grab on a press, so
    // the press goes on to the widget as if it were not here. One in the slot
    // itself would never see a press the widget accepts.
    Item {
        anchors.fill: parent
        z: 2

        PointHandler {
            acceptedButtons: Qt.AllButtons
            enabled: !slot.host.arranging
            onActiveChanged: {
                if (active)
                    slot.host.reportPress(slot);
            }
        }
    }

    // On the slot, the widget's parent, as Qt means a DragHandler to sit
    // over controls: the widget (or arrange mode's area) takes the press
    // first, and the handler, seeing it after, only watches. Put in an item
    // above the widget instead, it took presses no other handler there let
    // through (measured: arrange mode's clicks vanished).
    DragHandler {
        id: drag

        // The bar draws the widget's ghost (BarDragOverlay.qml); the slot
        // itself stays where its section puts it.
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: slot.host.dragThreshold
        enabled: slot.draggable && !slot.host.hidden
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            if (active)
                slot.host.beginDrag(slot.modelData, slot, centroid.pressPosition, centroid.scenePosition);
            else
                slot.host.releaseDrag(slot.modelData);
        }
        onCentroidChanged: {
            if (active)
                slot.host.moveDrag(slot.modelData, slot, centroid.scenePosition);
        }
        // The grab taken away (by the compositor, or by an item that
        // insists): nothing lands.
        onCanceled: slot.host.cancelDrag()
    }
}
