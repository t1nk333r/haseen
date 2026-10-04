import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Haseen
import qs.Haseen.Widgets

// Workspaces from Hyprland's event socket (Quickshell.Hyprland): no polling.
// Focused = accent, visible on this monitor = foreground, others muted.
Row {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property bool allMonitors: settings.allMonitors === true

    function activate(ws: var): void {
        // Hyprland 0.56 in Lua mode takes Lua dispatcher expressions.
        const target = ws.id > 0 ? String(ws.id) : "name:" + ws.name;
        Hyprland.dispatch(Hyprland.usingLua ? "hl.dsp.focus({ workspace = \"" + target + "\" })" : "workspace " + target);
    }

    height: parent ? parent.height : implicitHeight

    Repeater {
        model: ScriptModel {
            values: Hyprland.workspaces.values.filter(ws => !ws.name.startsWith("special:") && (root.allMonitors || ws.monitor === root.monitor))
        }

        delegate: BarButton {
            required property HyprlandWorkspace modelData

            height: root.height
            text: modelData.id > 0 ? String(modelData.id) : modelData.name
            color: modelData.urgent ? Theme.urgent : modelData.focused ? Theme.accent : modelData.active ? Theme.foreground : Theme.muted
            onClicked: root.activate(modelData)
        }
    }
}
