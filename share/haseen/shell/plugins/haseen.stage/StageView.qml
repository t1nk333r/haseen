import QtQuick
import Quickshell
import qs.Haseen
import "Stage.js" as Stage

// What the stage shows (plan 163), apart from its window so the headless
// draw of tests/test-stage.sh can put it in a plain one: a soft shade from
// the edge, and the column of workspace stacks that slides in from past the
// edge and back out. The column takes the pointer, with the edge itself;
// leaving both closes the stage after a short grace, as does Escape. The
// stacks are frozen while the column slides out, so a switch does not
// reshuffle them on the way.
Item {
    id: view

    property string edge: "left"
    property int tilt: 50
    property int maxWindows: 3
    property real screenWidth: width
    // Stage.stacks for this monitor.
    property var stacks: []
    property bool capture: true
    // True once the pointer was on the stage: an IPC open waits for that
    // before leaving can close it.
    property bool entered: false
    property bool shown: false

    signal chosen(int workspaceId)
    signal dismissed
    signal closed

    readonly property int iconSize: Theme.space(30)
    readonly property int inset: Theme.spacing.xxl
    property var drawn: []
    readonly property var metrics: Stage.metrics(screenWidth, height - 2 * inset, drawn.length, maxWindows, iconSize)
    // The window's width: the widest stack and the room around it.
    readonly property int columnWidth: (metrics.stackWidth || 0) + 3 * inset
    readonly property bool inside: edgeHover.hovered || railHover.hovered
    readonly property alias edgeArea: edgeArea
    readonly property alias rail: rail

    // A pointer that left the edge before the window mapped never enters
    // it: the grace runs from the start, and finds it gone.
    function show(): void {
        shown = true;
        if (entered && !inside)
            grace.restart();
    }

    // Slide out, then `closed`. With motion off nothing slides; asked
    // before it slid in, or with nothing sliding, it closes at once.
    function hide(): void {
        if (!shown) {
            if (!slide.running)
                Qt.callLater(view.closed);
            return;
        }
        shown = false;
        if (Theme.duration(160) <= 0)
            Qt.callLater(view.closed);
    }

    onStacksChanged: if (shown || drawn.length === 0)
        drawn = stacks
    onInsideChanged: {
        if (inside) {
            entered = true;
            grace.stop();
        } else if (entered && shown) {
            grace.restart();
        }
    }

    focus: true
    Keys.onEscapePressed: view.dismissed()

    // The shade: the theme's background, fading from the edge, so the
    // stacks read over any window. Only while the stage is out.
    Rectangle {
        anchors.fill: parent
        opacity: view.shown ? 1 : 0
        gradient: Gradient {
            orientation: Gradient.Horizontal

            GradientStop {
                position: 0
                color: view.edge === "right" ? Theme.alpha(Theme.background, 0) : Theme.alpha(Theme.background, 0.55)
            }
            GradientStop {
                position: 1
                color: view.edge === "right" ? Theme.alpha(Theme.background, 0.55) : Theme.alpha(Theme.background, 0)
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.duration(view.shown ? 220 : 160)
            }
        }
    }

    // The edge keeps the stage open along its whole length.
    Item {
        id: edgeArea

        x: view.edge === "right" ? view.width - width : 0
        width: 2
        height: view.height

        HoverHandler {
            id: edgeHover
        }
    }

    Item {
        id: rail

        x: Stage.slideX(view.edge, view.width, view.shown)
        y: view.inset + (view.metrics.top || 0)
        width: view.width
        height: (view.metrics.shown || 0) * (view.metrics.slot || 0)
        opacity: view.shown ? 1 : 0

        Behavior on x {
            NumberAnimation {
                id: slide

                duration: Theme.duration(view.shown ? 220 : 160)
                easing.type: view.shown ? Easing.OutCubic : Easing.InCubic
                onRunningChanged: if (!running && !view.shown)
                    view.closed()
            }
        }
        Behavior on opacity {
            NumberAnimation {
                duration: Theme.duration(view.shown ? 220 : 160)
            }
        }

        HoverHandler {
            id: railHover
        }

        Repeater {
            model: ScriptModel {
                values: view.drawn.slice(0, view.metrics.shown || 0)
                objectProp: "id"
            }

            StageStack {
                y: index * (view.metrics.slot || 0)
                width: rail.width
                height: view.metrics.slot || 0
                edge: view.edge
                tilt: view.tilt
                metrics: view.metrics
                inset: view.inset
                iconSize: view.iconSize
                capture: view.capture
                onChosen: id => view.chosen(id)
            }
        }
    }

    // A short grace after the pointer leaves, so a pointer that slips off a
    // stack for a moment does not close the stage.
    // haseen:ui-timeout
    Timer {
        id: grace

        interval: 350
        repeat: false
        onTriggered: if (!view.inside)
            view.dismissed()
    }
}
