import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen

// The covers during a background change (plan 161), one per screen. Each is
// a layer surface on the Bottom layer: above swaybg, which draws on
// Background, and below every window. It takes no input, reserves no space
// and exists only while the change runs; the Transition service creates
// them through a LazyLoader and frees them, and their textures, when it
// ends. The default windowrules.lua turns Hyprland's layer animation off for
// their namespace, so a cover is whole on its first frame.
//
// A file of its own, loaded by URL, so Transition.qml compiles where no
// PanelWindow backend exists (the offscreen engine of the tests).
Variants {
    id: covers

    // The haseen.background Transition service, set by its loader.
    property var service: null

    model: Quickshell.screens

    PanelWindow {
        id: win

        required property var modelData
        property bool covering: false
        property int frames: 0

        screen: modelData
        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "haseen-background-transition"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        onCoveringChanged: if (covering && covers.service)
            covers.service.screenCovered()

        Connections {
            target: covers.service
            function onGenerationChanged(): void {
                win.frames = 0;
                win.covering = false;
            }
        }

        TransitionView {
            id: view

            anchors.fill: parent
            opacity: covers.service ? covers.service.coverOpacity : 0
            oldSource: covers.service ? Paths.fileUrl(covers.service.oldPath) : ""
            newSource: covers.service ? Paths.fileUrl(covers.service.newPath) : ""
            effect: covers.service ? covers.service.effect : "fade"
            progress: covers.service ? covers.service.progress : 0
            seed: covers.service ? covers.service.seed : 0
            pixelRatio: win.devicePixelRatio > 0 ? win.devicePixelRatio : 1
            // The burning edge is the theme's accent. The line is the
            // foreground a fifth of the way to the accent, at 75 %: a pencil
            // line, not a glow.
            ember: Theme.accent
            ink: Qt.rgba(Theme.foreground.r * 0.8 + Theme.accent.r * 0.2, Theme.foreground.g * 0.8 + Theme.accent.g * 0.2, Theme.foreground.b * 0.8 + Theme.accent.b * 0.2, 0.75)

            onFailedChanged: if (failed && covers.service)
                covers.service.screenFailed()
        }

        // The old image must be on screen, not only decoded, before the CLI
        // restarts swaybg: two frames after both images are ready.
        FrameAnimation {
            running: view.ready && !win.covering
            onTriggered: {
                win.frames++;
                if (win.frames >= 2)
                    win.covering = true;
            }
        }
    }
}
