import QtQuick
import qs.Haseen

// One screen's cover during a background change (plan 161): the picture
// (TransitionView) and the report to the Transition service that the old
// image is on screen. TransitionWindows.qml puts one in a layer surface per
// screen; a plain Item, so the tests host the same code in a bare window.
Item {
    id: cover

    // The haseen.background Transition service.
    property var service: null
    property real pixelRatio: 1
    // The old image is on screen: two frames after both images were ready.
    property bool covering: false
    property int frames: 0
    readonly property alias view: view

    // One query per change: Qt's image cache keys on the URL, and a theme
    // change can put a different picture at a path a recent change showed
    // (current/theme/backgrounds/BG1.png), which must not come back from it.
    function source(path: string): string {
        return path ? Paths.fileUrl(path) + "?change=" + service.generation : "";
    }

    onCoveringChanged: if (covering && service)
        service.screenCovered()

    Connections {
        target: cover.service
        // A change during a change keeps this cover: count again.
        function onGenerationChanged(): void {
            cover.frames = 0;
            cover.covering = false;
        }
    }

    TransitionView {
        id: view

        anchors.fill: parent
        opacity: cover.service ? cover.service.coverOpacity : 0
        oldSource: cover.service ? cover.source(cover.service.oldPath) : ""
        newSource: cover.service ? cover.source(cover.service.newPath) : ""
        effect: cover.service ? cover.service.effect : "fade"
        progress: cover.service ? cover.service.progress : 0
        seed: cover.service ? cover.service.seed : 0
        pixelRatio: cover.pixelRatio
        // A switching contagion cell is tinted with the theme's accent. The
        // outline is the foreground a fifth of the way to the accent, at
        // 75 %: a pencil line, not a glow.
        glow: Theme.accent
        pencil: Qt.rgba(Theme.foreground.r * 0.8 + Theme.accent.r * 0.2, Theme.foreground.g * 0.8 + Theme.accent.g * 0.2, Theme.foreground.b * 0.8 + Theme.accent.b * 0.2, 0.75)

        onFailedChanged: if (failed && cover.service)
            cover.service.screenFailed()
    }

    // The old image must be on screen, not only decoded, before the CLI
    // restarts swaybg: two frames after both images are ready.
    FrameAnimation {
        running: view.ready && !cover.covering
        onTriggered: {
            cover.frames++;
            if (cover.frames >= 2)
                cover.covering = true;
        }
    }
}
