import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Haseen

// A HyprlandFocusGrab that a screenshot does not end (plan 184). A capture
// tool's layer takes the keyboard when it opens, and the compositor clears
// every focus grab then, so a panel, the menu or a tray menu closed under
// PRINT and the capture lost what it was taken for. This grab holds instead
// while a capture tool is open (Capture.active) and takes the focus back when
// it goes; `cleared` means the grab ended for any other reason (a click
// outside, another window), as HyprlandFocusGrab's own `cleared` did.
//
// Hyprland reports the new layer on its event socket and clears the grab on
// the Wayland one, in either order, so a clear with no capture open yet waits
// `settle` ms for the layer's event before it counts. That is the delay a
// click outside now takes to close a panel. When the capture ends, Hyprland
// hands the keyboard back to the window that had it before, which would end
// a grab started at once (seen on luna, 2026-11-22), so the surface asks for
// the keyboard first (`resumed`) and the grab starts `rearm` ms later.
Scope {
    id: root

    property list<QtObject> windows
    property bool active: false
    property int settle: 100
    property int rearm: 100
    // The capture toolbar's own panel: a capture is what it is for, and a
    // click outside it must still close it.
    property bool ignoresCapture: false

    // Read here so the singleton exists, and hears the layer events, from
    // the moment a grab does.
    readonly property bool capturing: Capture.active && !ignoresCapture
    property bool held: false

    signal cleared
    // A capture that held the grab is over: a surface that took the keyboard
    // only once (OnDemand after Exclusive) asks again, and the grab follows.
    signal resumed

    // HyprlandFocusGrab ended. A function, so the test can end it without a
    // compositor.
    function grabCleared(): void {
        if (!active || held)
            return;
        if (capturing)
            hold();
        else
            settleTimer.restart();
    }

    function hold(): void {
        settleTimer.stop();
        rearmTimer.stop();
        held = true;
    }

    onCapturingChanged: {
        if (capturing) {
            rearmTimer.stop();
        } else if (held) {
            resumed();
            rearmTimer.restart();
        }
    }
    onActiveChanged: if (!active) {
        settleTimer.stop();
        rearmTimer.stop();
        held = false;
    }

    HyprlandFocusGrab {
        windows: root.windows
        // Off while held, so it starts again when the capture ends.
        active: root.active && !root.held
        onCleared: root.grabCleared()
    }

    // haseen:ui-timeout
    Timer {
        id: settleTimer

        interval: root.settle
        repeat: false
        onTriggered: {
            if (root.capturing)
                root.hold();
            else if (root.active)
                root.cleared();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: rearmTimer

        interval: root.rearm
        repeat: false
        onTriggered: root.held = false
    }
}
