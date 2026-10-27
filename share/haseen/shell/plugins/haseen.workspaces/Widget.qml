import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
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
//   - with per-monitor workspaces on (plan 105, `haseen toggle
//     monitor-workspaces`), each bar shows its own monitor's block of ten,
//     labelled 1-0, then any workspace only visiting from an unplugged
//     monitor, set apart by a gap; the wheel walks that row.
// Everything comes from Hyprland's event socket (Quickshell.Hyprland); the
// only requests are a monitor refresh on an `activespecial` event, because
// HyprlandMonitor exposes the shown special workspace only via lastIpcObject,
// and, with per-monitor workspaces, a refresh when workspaces move between
// monitors or change number, which Quickshell does not track (Omarchy 4.5's
// widget does the same). Two files are watched, never polled: the toggle,
// read again on each config reload (when Hyprland takes it up), and the
// blocks Hyprland writes. Dispatch uses Hyprland 0.56 Lua expressions when
// Hyprland runs Lua config.
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
    readonly property string monitorName: monitor ? monitor.name : ""
    readonly property bool allMonitors: settings.allMonitors === true
    readonly property int persistent: typeof settings.persistent === "number" ? settings.persistent : 5
    readonly property var all: Hyprland.workspaces.values
    readonly property var listed: all.map(ws => ({
                id: ws.id,
                monitor: ws.monitor ? ws.monitor.name : ""
            }))

    // Per-monitor workspaces: on while Hyprland loads the toggle file.
    readonly property string stateDir: Paths.stateHome + "/haseen"
    property bool perMonitor: false
    property var blocks: ({})
    readonly property int activeId: monitor && monitor.activeWorkspace ? monitor.activeWorkspace.id : -1
    readonly property int block: Ws.monitorBlock(blocks, monitorName, activeId)

    readonly property var ids: perMonitor ? Ws.monitorWorkspaceIds(listed, persistent, monitorName, block) : Ws.workspaceIds(listed, persistent, monitorName, allMonitors)
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

    function focusCommand(id: int): string {
        return perMonitor ? Ws.monitorFocusCommand(id, block, monitorName, Hyprland.usingLua) : Ws.focusCommand(String(id), Hyprland.usingLua);
    }

    // The gap before the first visiting workspace, so its slot number is not
    // read as one of the monitor's own.
    readonly property int guestGap: perMonitor && ids.some((id, i) => i > 0 && Ws.blockOf(id) !== block && Ws.blockOf(ids[i - 1]) === block) ? Math.round(cellSize / 2) : 0

    // Sized from the cell count, not grid.implicitWidth: BarSection gives the
    // slot a height only once the width is non-zero, and a positioner skips
    // zero-height cells, so measuring the grid would stay 0 forever.
    readonly property int count: ids.length + specials.length

    implicitWidth: vertical ? cellSize : count * cellSize + guestGap
    implicitHeight: vertical ? count * cellSize + guestGap : Config.barHeight

    Connections {
        target: Hyprland
        function onRawEvent(event: var): void {
            const name = event.name;
            if (name === "activespecial" || name === "activespecialv2")
                Hyprland.refreshMonitors();
            if (name === "configreloaded")
                toggleFile.reload();
            // Quickshell credits a switch to the focused monitor and misses
            // the workspace a monitor falls back to when its own moves away,
            // and learns a new number only by asking. One bar asks for a
            // plain switch: every bar shares the answer.
            if (!root.perMonitor)
                return;
            const switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused;
            if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
                Hyprland.refreshMonitors();
                Hyprland.refreshWorkspaces();
            }
        }
    }

    FileView {
        id: toggleFile
        path: root.stateDir + "/toggles/hypr/monitor-workspaces.lua"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.perMonitor = true
        onLoadFailed: root.perMonitor = false
    }

    FileView {
        path: root.perMonitor ? root.stateDir + "/monitor-workspaces" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.blocks = Ws.readBlocks(text())
        onLoadFailed: root.blocks = ({})
    }

    Component.onCompleted: Hyprland.refreshMonitors()

    // One workspace or scratchpad cell: label and click. No hover tint, here
    // or from the bar slot (barHoverHighlight): the owner wants none.
    component Cell: Item {
        id: cell

        property string label
        property color tint: Theme.barForeground
        property bool bold: false
        // Space before the cell, inside it (the first visiting workspace).
        property int lead: 0
        signal activated

        width: root.vertical ? root.width : root.cellSize + lead
        height: root.vertical ? root.cellSize + lead : Math.max(1, root.height)

        Text {
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: root.vertical ? 0 : cell.lead / 2
            anchors.verticalCenterOffset: root.vertical ? cell.lead / 2 : 0
            text: cell.label
            color: cell.tint
            font.family: Theme.fontMono
            font.pixelSize: Theme.font.body
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
                required property int index

                readonly property var workspace: root.workspaceById(modelData)
                readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
                readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null && root.monitor.activeWorkspace.id === modelData
                readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
                readonly property bool firstGuest: root.perMonitor && index > 0 && Ws.blockOf(modelData) !== root.block && Ws.blockOf(root.ids[index - 1]) === root.block

                lead: firstGuest ? root.guestGap : 0
                label: shown ? "\u{F14FB}" : root.perMonitor ? Ws.slotLabel(modelData) : Ws.label(modelData)
                tint: workspace !== null && workspace.urgent ? Theme.urgent : Theme.barForeground
                opacity: occupied || shown ? (shown && !focused ? 0.75 : 1) : 0.5
                onActivated: root.dispatch(root.focusCommand(modelData))
            }
        }

        Repeater {
            model: root.specials

            delegate: Cell {
                required property HyprlandWorkspace modelData

                readonly property string name: Ws.specialName(modelData.name)

                label: "\uf005" // i18n-ignore: a glyph
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
            if (steps === 0)
                return;
            if (root.perMonitor) {
                const target = Ws.stepInRow(root.ids, root.activeId, steps);
                if (target > 0)
                    root.dispatch(root.focusCommand(target));
            } else {
                root.dispatch(Ws.focusCommand(Ws.scrollTarget(steps), Hyprland.usingLua));
            }
        }
    }
}
