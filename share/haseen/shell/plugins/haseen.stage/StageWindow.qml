import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Haseen

// The stage's window (plan 163), created when the stage opens and destroyed
// when it has slid out: an overlay along the edge of one screen, as tall as
// the room the bars leave, as wide as the column of stacks. It takes the
// pointer only on the column and the edge, so the rest of the screen stays
// usable. The keyboard is taken when the window appears and then held on
// demand, as PanelPopup does, only so Escape reaches it. A file of its own,
// loaded by URL, like the strips.
PanelWindow {
    id: win

    // Set by the service's loader.
    property var service: null

    readonly property string edge: service ? service.cfg.edge : "left"
    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null

    function hide(): void {
        view.hide();
    }

    screen: service ? service.stageScreen : null
    anchors {
        top: true
        bottom: true
        left: edge === "left"
        right: edge === "right"
    }
    implicitWidth: Math.max(1, view.columnWidth)
    exclusionMode: ExclusionMode.Normal
    color: "transparent"
    surfaceFormat.opaque: false
    mask: Region {
        item: view.edgeArea

        Region {
            item: view.rail
        }
    }
    WlrLayershell.namespace: "haseen-stage"
    WlrLayershell.layer: WlrLayer.Overlay
    property bool focusPrimed: false
    WlrLayershell.keyboardFocus: focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive

    Connections {
        target: view.Window

        function onActiveChanged(): void {
            if (view.Window.active)
                win.focusPrimed = true;
        }
    }

    // Another workspace on this monitor, however it came: the stacks are
    // stale, so the stage goes.
    Connections {
        target: win.monitor

        function onActiveWorkspaceChanged(): void {
            if (win.service)
                win.service.close();
        }
    }

    StageView {
        id: view

        anchors.fill: parent
        edge: win.edge
        tilt: win.service ? win.service.cfg.tilt : 0
        maxWindows: win.service ? win.service.cfg.maxWindows : 3
        screenWidth: win.screen ? win.screen.width : width
        stacks: win.service ? win.service.stacksFor(win.screen) : []
        entered: win.service ? win.service.openedBy === "edge" : false
        onChosen: id => {
            if (win.service)
                win.service.choose(id);
        }
        onDismissed: {
            if (win.service)
                win.service.close();
        }
        onClosed: {
            if (win.service)
                win.service.closed();
        }
        Component.onCompleted: Qt.callLater(view.show)
    }
}
