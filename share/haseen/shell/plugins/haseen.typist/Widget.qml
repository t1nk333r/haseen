// Adapted from Panel.qml (the bar button) in the owner's fork t1nk33r.typist
// 1.1.0 of sanjuanjor/typist (MIT, Copyright (c) 2026 sanjuanjor); see
// LICENSE and UPSTREAM.md beside this file.
// haseen: BarButton, the picker as the haseen.typist panel, `haseen typist`.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// Left click opens the picker, or stops a run in progress (the button is
// highlighted while typing); middle click types the clipboard at once; right
// click opens the snippets file. Typing can also start from a hotkey
// (`haseen typist start`), which this button learns of on its next probe:
// it asks systemd only after a click of its own and every 2 s while a run it
// knows of is going, never while idle.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string cli: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen-typist"
    property bool typing: false

    function probe(): void {
        if (!stateProbe.running)
            stateProbe.running = true;
    }

    function run(args: var): void {
        Quickshell.execDetached([root.cli].concat(args));
        settle.restart();
    }

    glyph: "\u{f030c}"
    highlighted: typing
    color: typing ? Theme.accent : Theme.barForeground

    onClicked: button => {
        if (button === Qt.MiddleButton)
            root.run(["start"]);
        else if (button === Qt.RightButton)
            Apps.launch([root.cli, "snippets", "edit"]);
        else if (root.typing)
            root.run(["stop"]);
        else
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }

    Component.onCompleted: probe()

    Process {
        id: stateProbe

        command: ["systemctl", "--user", "is-active", "--quiet", "haseen-typist.service"]
        onExited: code => root.typing = code === 0
    }

    // One look shortly after a start or stop of our own.
    // haseen:ui-timeout
    Timer {
        id: settle

        interval: 600
        repeat: false
        onTriggered: root.probe()
    }

    // While a run goes, notice when it ends.
    // haseen:sample
    Timer {
        interval: 2000
        repeat: true
        running: root.typing
        onTriggered: root.probe()
    }
}
