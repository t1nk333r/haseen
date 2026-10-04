import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// haseen.session: Lock, Log out, Suspend, Reboot, Shut down. Arrows move,
// Enter or a click runs; with settings.confirm the destructive ones need a
// second press. Open with `haseen shell ipc panel toggle haseen.session`.
//
// Lock goes to the `lock` role (haseen.lock), falling back to
// `loginctl lock-session` for a lock daemon listening to logind. Log out is
// Hyprland's exit dispatcher over its socket (what `hyprctl dispatch exit`
// sends). Power actions go through `systemctl`, which asks logind and polkit.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool confirm: settings.confirm !== false
    readonly property var actions: [
        {
            id: "lock",
            label: "Lock",
            glyph: "\uf023",
            destructive: false
        },
        {
            id: "logout",
            label: "Log out",
            glyph: "\uf2f5",
            destructive: true
        },
        {
            id: "suspend",
            label: "Suspend",
            glyph: "\uf186",
            destructive: false
        },
        {
            id: "reboot",
            label: "Reboot",
            glyph: "\uf2f9",
            destructive: true
        },
        {
            id: "poweroff",
            label: "Shut down",
            glyph: "\uf011",
            destructive: true
        }
    ]
    property int current: 0
    // Id of the action waiting for its confirming press.
    property string armed: ""

    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function run(id: string): void {
        if (confirm && armed !== id && actions.find(a => a.id === id).destructive) {
            armed = id;
            return;
        }
        armed = "";
        close();
        switch (id) {
        case "lock":
            if (!Plugins.callRole("lock", "lock", []))
                Quickshell.execDetached(["loginctl", "lock-session"]);
            break;
        case "logout":
            Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.exit()" : "exit");
            break;
        case "suspend":
            Quickshell.execDetached(["systemctl", "suspend"]);
            break;
        case "reboot":
            Quickshell.execDetached(["systemctl", "reboot"]);
            break;
        case "poweroff":
            Quickshell.execDetached(["systemctl", "poweroff"]);
            break;
        }
    }

    function shift(delta: int): void {
        current = (current + delta + actions.length) % actions.length;
        armed = "";
    }

    width: Theme.fontSize * 16
    spacing: 2
    focus: true

    Keys.onUpPressed: shift(-1)
    Keys.onDownPressed: shift(1)
    Keys.onTabPressed: shift(1)
    Keys.onBacktabPressed: shift(-1)
    Keys.onReturnPressed: run(actions[current].id)
    Keys.onEnterPressed: run(actions[current].id)

    Component.onCompleted: forceActiveFocus()

    // Test hook (settings.debugIpc): select and press rows over IPC while the
    // panel is open, so a smoke test never injects keys into the session.
    IpcHandler {
        target: "haseen.session"
        enabled: root.settings.debugIpc === true

        function select(index: int): void {
            root.current = Math.max(0, Math.min(index, root.actions.length - 1));
            root.armed = "";
        }

        function press(): void {
            root.run(root.actions[root.current].id);
        }

        function state(): string {
            return JSON.stringify({
                current: root.actions[root.current].id,
                armed: root.armed
            });
        }
    }

    Repeater {
        model: root.actions

        delegate: BarButton {
            required property var modelData
            required property int index

            readonly property bool isArmed: root.armed === modelData.id

            width: root.width
            height: Theme.fontSize * 2.4
            glyph: modelData.glyph
            text: isArmed ? modelData.label + "? Press again" : modelData.label
            color: isArmed ? Theme.urgent : Theme.foreground
            highlighted: root.current === index
            onClicked: {
                root.current = index;
                root.run(modelData.id);
            }
        }
    }
}
