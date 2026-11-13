import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Transition.js" as Transition

// haseen.background's wallpaper transition (plan 161). swaybg keeps drawing
// the wallpaper (haseen-background.service); this service only covers the
// moment it is restarted on a new image, so the new one arrives with an
// effect instead of a cut.
//
// The CLI drives it (theme_background_reload in theme-lib.sh), in this
// order:
//   1. `background begin OLD NEW`: one cover per screen opens on the Bottom
//      layer, above swaybg, and decodes both images. Once every screen has
//      drawn the old image, which swaybg is still showing, the effect starts
//      playing. The answer is "loading", or "skip <reason>".
//   2. The CLI asks `background state` until it reads a covered state
//      (playing, holding or leaving), at most about a second, then restarts
//      swaybg underneath, whatever the answer.
//   3. `background shown`: swaybg has been restarted on the new image. The
//      cover waits for the effect to end on the new image and for a short
//      hold, so swaybg has painted, then fades out over two renders of the
//      same image and is freed with its textures.
// The wallpaper changes even when this fails: the CLI restarts swaybg
// either way, and a cover never outlives its bounds (loadTimer, safetyTimer).
//
// At idle nothing is loaded: no window, no image, no shader. A change
// is skipped (instant) when the setting is none, when Hyprland's animations
// are off, and in the game context.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    property var machine: Transition.initial()
    readonly property string phase: machine.name
    readonly property int durationMs: Transition.durationMs(settings.transitionDuration)

    property string oldPath: ""
    property string newPath: ""
    property string effect: "fade"
    property string lastEffect: ""
    // Why the last change showed no transition, or "played".
    property string lastResult: ""
    property real progress: 0
    property real coverOpacity: 1
    property real seed: 0
    property int coveredScreens: 0
    property int screenCount: 0
    // One per change: a cover kept across a change during a change counts
    // its screen again (TransitionCover.qml).
    property int generation: 0

    function dispatch(event: string): void {
        const before = machine.name;
        machine = Transition.reduce(machine, event);
        // begin re-enters loading when a change arrives during a change.
        if (machine.name !== before || event === "begin")
            enter(machine.name);
    }

    function enter(name: string): void {
        if (name === "loading") {
            holdTimer.stop();
            safetyTimer.stop();
            play.stop();
            fadeOut.stop();
            coveredScreens = 0;
            progress = 0;
            coverOpacity = 1;
            loadTimer.restart();
        } else if (name === "playing") {
            loadTimer.stop();
            play.restart();
        } else if (name === "holding") {
            safetyTimer.restart();
        } else if (name === "leaving") {
            safetyTimer.stop();
            lastResult = "played";
            fadeOut.restart();
        } else if (name === "idle") {
            loadTimer.stop();
            holdTimer.stop();
            safetyTimer.stop();
            play.stop();
            fadeOut.stop();
            progress = 0;
            coverOpacity = 1;
            coveredScreens = 0;
            // Clearing the paths frees the decoded images with the windows.
            oldPath = "";
            newPath = "";
        }
    }

    function begin(from: string, to: string): string {
        const picked = Transition.pick(settings.transition, lastEffect, Math.random());
        let why = Transition.skipReason({
            effect: picked,
            oldPath: from,
            newPath: to,
            reduceMotion: Theme.reduceMotion,
            context: Flags.context
        });
        if (!why && (from.charAt(0) !== "/" || to.charAt(0) !== "/"))
            why = "not a path";
        if (!why && Quickshell.screens.length === 0)
            why = "no screen";
        if (why) {
            // A skipped change during a change ends the running one: the
            // CLI restarts swaybg at once.
            if (machine.name !== "idle")
                dispatch("abort");
            lastResult = why;
            return "skip " + why;
        }
        effect = picked;
        lastEffect = picked;
        oldPath = from;
        newPath = to;
        seed = Math.floor(Math.random() * 600) / 10;
        screenCount = Quickshell.screens.length;
        generation++;
        // A change during a change starts over in the covers already on
        // screen: tearing them down would show swaybg, mid-restart, between
        // the two. Each keeps its picture until the new pair is decoded, and
        // counts as covered again only once the new old image is drawn.
        dispatch("begin");
        return machine.name;
    }

    function shown(): void {
        const wasLoading = machine.name === "loading";
        dispatch("shown");
        if (wasLoading)
            lastResult = "restarted before covered";
        else if (machine.name !== "idle")
            holdTimer.restart();
    }

    // From each screen's cover (TransitionWindows.qml).
    function screenCovered(): void {
        if (machine.name !== "loading")
            return;
        coveredScreens++;
        if (coveredScreens >= screenCount)
            dispatch("ready");
    }

    function screenFailed(): void {
        if (machine.name !== "loading")
            return;
        lastResult = "image did not load";
        dispatch("abort");
    }

    function status(): string {
        return JSON.stringify({
            state: machine.name,
            effect: effect,
            progress: Math.round(progress * 1000) / 1000,
            covered: coveredScreens,
            screens: screenCount,
            durationMs: durationMs,
            last: lastResult
        });
    }

    // Architecture 5.5.
    IpcHandler {
        target: "background"

        function begin(oldPath: string, newPath: string): string {
            return root.begin(oldPath, newPath);
        }

        function state(): string {
            return root.phase;
        }

        function shown(): string {
            root.shown();
            return root.phase;
        }

        function status(): string {
            return root.status();
        }
    }

    NumberAnimation {
        id: play

        target: root
        property: "progress"
        from: 0
        to: 1
        duration: root.durationMs
        easing.type: root.effect === "fade" ? Easing.InOutQuad : Easing.Linear
        onFinished: root.dispatch("played")
    }

    // The hand-over: by now swaybg shows the image the cover shows, so the
    // fade is between two renders of the same picture.
    NumberAnimation {
        id: fadeOut

        target: root
        property: "coverOpacity"
        from: 1
        to: 0
        duration: 160
        onFinished: root.dispatch("left")
    }

    // The images must decode and draw within this, or the change goes ahead
    // without a cover (the CLI stops waiting after about a second).
    // haseen:ui-timeout
    Timer {
        id: loadTimer

        interval: 1500
        repeat: false
        onTriggered: {
            root.lastResult = "too slow to load";
            root.dispatch("timeout");
        }
    }

    // After `shown`: time for the restarted swaybg to decode and paint.
    // haseen:ui-timeout
    Timer {
        id: holdTimer

        interval: 500
        repeat: false
        onTriggered: root.dispatch("settled")
    }

    // A CLI that never says `shown` (killed, or swaybg not restarted) does
    // not keep the cover up past this.
    // haseen:ui-timeout
    Timer {
        id: safetyTimer

        interval: 3000
        repeat: false
        onTriggered: root.dispatch("settled")
    }

    LazyLoader {
        active: root.phase !== "idle"
        source: Qt.resolvedUrl("TransitionWindows.qml")
        onItemChanged: if (item)
            item.service = root
    }
}
