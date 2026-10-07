import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Haseen
import "Workspaces.js" as Ws

// Hyprland workspaces, a port of Omarchy's workspaces bar widget
// (shell/plugins/bar/widgets/Workspaces.qml, MIT, Copyright (c) David
// Heinemeier Hansson) to qs.Haseen:
//   - workspaces 1..persistent always show; other existing ones up to 10 join;
//   - the active workspace shows Omarchy's dot glyph, empty ones are dimmed,
//     10 is labelled "0", urgent ones use Theme.urgent;
//   - special workspaces (scratchpads) follow as stars while they exist,
//     bright while shown on this monitor; click toggles one;
//   - click focuses, wheel walks e-1/e+1 like SUPER+wheel.
// Everything comes from Hyprland's event socket (Quickshell.Hyprland); the
// only request is a monitor refresh on an `activespecial` event, because
// HyprlandMonitor exposes the shown special workspace only via lastIpcObject.
// Dispatch uses Hyprland 0.56 Lua expressions when Hyprland runs Lua config.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false
    // No hover tint from the bar slot (BarSection); the owner wants none here.
    readonly property bool barHoverHighlight: false

    readonly property var monitor: screen ? Hyprland.monitorFor(screen) : null
    readonly property bool allMonitors: settings.allMonitors === true
    readonly property int persistent: typeof settings.persistent === "number" ? settings.persistent : 5
    readonly property var all: Hyprland.workspaces.values
    readonly property var ids: Ws.workspaceIds(all.map(ws => ({
                id: ws.id,
                monitor: ws.monitor ? ws.monitor.name : ""
            })), persistent, monitor ? monitor.name : "", allMonitors)
    readonly property var specials: all.filter(ws => ws.name.startsWith("special:") && (allMonitors || !monitor || ws.monitor === monitor))
    readonly property string shownSpecial: {
        const ipc = monitor ? monitor.lastIpcObject : null;
        return ipc && ipc.specialWorkspace ? String(ipc.specialWorkspace.name || "") : "";
    }
    readonly property int cellSize: Math.round(Theme.fontSize * 1.6)

    function workspaceById(id: int): var {
        return all.find(ws => ws.id === id) || null;
    }

    function dispatch(cmd: string): void {
        Hyprland.dispatch(cmd);
    }

    // Sized from the cell count, not grid.implicitWidth: BarSection gives the
    // slot a height only once the width is non-zero, and a positioner skips
    // zero-height cells, so measuring the grid would stay 0 forever.
    readonly property int count: ids.length + specials.length

    implicitWidth: vertical ? cellSize : count * cellSize
    implicitHeight: vertical ? count * cellSize : Config.barHeight

    Connections {
        target: Hyprland
        function onRawEvent(event: var): void {
            if (event.name === "activespecial" || event.name === "activespecialv2")
                Hyprland.refreshMonitors();
        }
    }

    Component.onCompleted: Hyprland.refreshMonitors()

    // One workspace or scratchpad cell: label and click. No hover tint, here
    // or from the bar slot (barHoverHighlight): the owner wants none.
    component Cell: Item {
        id: cell

        property string label
        property color tint: Theme.barForeground
        property bool bold: false
        signal activated

        width: root.vertical ? root.width : root.cellSize
        height: root.vertical ? root.cellSize : Math.max(1, root.height)

        Text {
            anchors.centerIn: parent
            text: cell.label
            color: cell.tint
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize
            font.bold: cell.bold
        }

        MouseArea {
            id: cellMouse
            anchors.fill: parent
            onClicked: cell.activated()
        }
    }

    Grid {
        id: grid
        columns: root.vertical ? 1 : root.ids.length + root.specials.length

        Repeater {
            model: root.ids

            delegate: Cell {
                id: wsCell

                required property int modelData

                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
                readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
                readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

                label: shown ? "\u{F14FB}" : Ws.label(modelData)
                tint: workspace !== null && workspace.urgent ? Theme.urgent : Theme.barForeground
                opacity: occupied || shown ? (shown && !focused ? 0.75 : 1) : 0.5
                onActivated: root.dispatch(Ws.focusCommand(String(modelData), Hyprland.usingLua))
            }
        }

        Repeater {
            model: root.specials

            delegate: Cell {
                required property HyprlandWorkspace modelData

                readonly property string name: Ws.specialName(modelData.name)

                label: "\uf005"
                tint: modelData.urgent ? Theme.urgent : modelData.name === root.shownSpecial ? Theme.accent : Theme.barForeground
                opacity: modelData.name === root.shownSpecial ? 1 : 0.5
                onActivated: root.dispatch(Ws.toggleSpecialCommand(name, Hyprland.usingLua))
            }
        }
    }

    // Wheel anywhere on the widget; clicks go to the cells.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: event => {
            const steps = Math.round(event.angleDelta.y / 120);
            if (steps !== 0)
                root.dispatch(Ws.focusCommand(Ws.scrollTarget(steps), Hyprland.usingLua));
        }
    }
}
