pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import "Capture.js" as C

// Whether a screenshot tool is on screen (plan 184). Omasnap, slurp and
// hyprpicker cover the screen with a layer of their own that takes the
// keyboard and the pointer, which ended every panel's focus grab and the
// stage's hover: PRINT closed the menu, a tray menu or the stage it was
// meant to capture. Hyprland's openlayer and closelayer events name the
// layer, so this counts the capture tools' layers however they were started
// (PRINT, the capture menu, a script of the owner's), with no polling.
//
// haseen.capture's toolbar counts too: PRINT opens it while that plugin is on
// (IO), it covers the screen as well, and the capture runs after it has gone.
// Its service sets `toolbar` while the toolbar is open or a capture waits out
// its delay, and calls expect() as it starts the capture command, which
// covers the moment before that command's layer appears.
Singleton {
    id: root

    property int open: 0
    property bool toolbar: false
    readonly property bool active: open > 0 || toolbar || expecting.running

    function expect(): void {
        expecting.restart();
    }

    Connections {
        target: Hyprland

        function onRawEvent(event): void {
            if (event.name !== "openlayer" && event.name !== "closelayer")
                return;
            const next = C.nextCount(root.open, event.name, event.data);
            if (next > root.open)
                expecting.stop();
            root.open = next;
        }
    }

    // How long a started capture command has to show its layer. A command
    // with none (a whole-screen recording) only keeps panels held this long.
    // haseen:ui-timeout
    Timer {
        id: expecting

        interval: 2000
        repeat: false
    }
}
