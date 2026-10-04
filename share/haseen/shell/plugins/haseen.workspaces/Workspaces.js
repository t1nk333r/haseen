.pragma library

// Workspace list logic for haseen.workspaces. Adapted from Omarchy's
// shell/plugins/bar/widgets/Workspaces.qml workspaceIds() (MIT, Copyright (c)
// David Heinemeier Hansson): workspaces 1..persistent always show, any other
// existing workspace up to 10 joins them, sorted. Pure, so tests run it
// headless.

// workspaces: [{ id, monitor }] (monitor = monitor name or "").
// monitor: this bar's monitor name; allMonitors: skip the monitor filter.
function workspaceIds(workspaces, persistent, monitor, allMonitors) {
    const n = Math.max(0, Math.min(10, Math.round(Number(persistent) || 0)));
    const ids = [];
    for (let i = 1; i <= n; i++)
        ids.push(i);
    for (const ws of workspaces || []) {
        if (!(ws.id > 0 && ws.id <= 10) || ids.indexOf(ws.id) >= 0)
            continue;
        if (allMonitors || !monitor || ws.monitor === monitor)
            ids.push(ws.id);
    }
    ids.sort((a, b) => a - b);
    return ids;
}

// Omarchy labels workspace 10 "0", matching the SUPER+0 bind.
function label(id) {
    return id === 10 ? "0" : String(id);
}

// "special:scratchpad" -> "scratchpad".
function specialName(name) {
    return String(name || "").replace(/^special:/, "");
}

// Lua dispatcher expressions for Hyprland 0.56 in Lua mode
// (default/hypr/binds.lua uses the same calls), else the legacy dispatchers.
function focusCommand(target, usingLua) {
    return usingLua ? "hl.dsp.focus({ workspace = \"" + target + "\" })" : "workspace " + target;
}

function toggleSpecialCommand(name, usingLua) {
    return usingLua ? "hl.dsp.workspace.toggle_special(\"" + name + "\")" : "togglespecialworkspace " + name;
}

// Wheel: up (positive steps) = previous, down = next, as SUPER+mouse_up/down.
function scrollTarget(steps) {
    return steps > 0 ? "e-1" : "e+1";
}
