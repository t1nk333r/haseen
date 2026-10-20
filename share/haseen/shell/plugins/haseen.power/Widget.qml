import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The owner's power button (plan 095), adopted from t1nk33r.power, a fork of
// Omarchy's power panel (MIT, Copyright (c) David Heinemeier Hansson). Only
// the bar side is the fork's: a battery glyph that stops showing charging
// while the charge limit holds the battery, and the percentage beside it
// unless `showPercentage` is false. A right click turns the percentage on
// or off and saves it (`haseen plugin settings`). A left click opens
// haseen.battery's panel, haseen's one power panel (plan 076: charge, time,
// draw, health, cycles, power profile and charge limit through `haseen
// powerprofile` and `haseen battery limit`), so no second copy of it exists.
// UPower signals only, no timer; no battery takes no room. Off by default:
// it replaces the haseen.battery widget in a bar, not stands beside it.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery && device.isPresent
    readonly property bool percentShown: Model.showPercentage(settings.showPercentage) && !vertical
    // The value a right click asked for, while its write runs.
    property var saving: null

    visible: present
    implicitWidth: present ? contentWidth : 0
    glyph: present ? Model.glyph(device, UPower.onBattery) : ""
    text: present && percentShown ? Math.round(Model.fraction(device) * 100) + "%" : ""

    function togglePercentage(): void {
        const want = !Model.showPercentage(settings.showPercentage);
        Config.setRuntime(["plugins", pluginId, "settings", "showPercentage"], want);
        saving = want;
        if (!writer.running)
            writer.running = true;
    }

    onClicked: button => {
        if (button === Qt.LeftButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", "haseen.battery"]);
        else if (button === Qt.RightButton)
            root.togglePercentage();
    }

    // One write at a time, of the latest value: a second click while one
    // runs is written when it ends.
    Process {
        id: writer

        property var written: null

        command: [root.binDir + "/haseen-plugin-settings", root.pluginId, "--yes"]
        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: writeErrors
        }
        onStarted: {
            written = root.saving;
            write(JSON.stringify({
                settings: {
                    showPercentage: written
                }
            }) + "\n");
            stdinEnabled = false;
        }
        onExited: exitCode => {
            stdinEnabled = true;
            if (exitCode !== 0)
                console.warn("haseen.power: cannot save showPercentage:", writeErrors.text);
            if (root.saving !== written)
                running = true;
            else
                root.saving = null;
        }
    }
}
