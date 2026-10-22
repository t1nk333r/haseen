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

// --- Per-monitor workspaces (plan 105) ----------------------------------------
// With `haseen toggle monitor-workspaces on`, every monitor owns a block of ten
// Hyprland ids (the laptop panel 1-10, the next monitor 11-20; Hyprland's side
// is default/hypr/monitor-workspaces.lua) and each bar shows its own block,
// labelled 1-0. Adapted from Omarchy 4.5's shell/plugins/bar/widgets/
// Workspaces.qml@v4.5.0-rc1, commit f2bd3cef6, pull request 15655
// (MIT, Copyright (c) David Heinemeier Hansson).

const SLOTS = 10;

// The state file's lines are block<TAB>connector<TAB>identity; a monitor that
// is not plugged in has no connector. Returns { connector: block }.
function readBlocks(text) {
    const blocks = {};
    for (const line of String(text || "").split("\n")) {
        const fields = line.split("\t");
        if (fields.length >= 3 && fields[1] !== "" && /^\d+$/.test(fields[0]))
            blocks[fields[1]] = parseInt(fields[0], 10);
    }
    return blocks;
}

function blockOf(id) {
    return Math.floor((id - 1) / SLOTS);
}

function slotOf(id) {
    return (id - 1) % SLOTS + 1;
}

// The slot's key: 10 is the 0 key.
function slotLabel(id) {
    return slotOf(id) === SLOTS ? "0" : String(slotOf(id));
}

// The bar's block: from the file Hyprland writes, else (before it has) the
// block of the workspace the monitor shows, else the first.
function monitorBlock(blocks, monitor, activeId) {
    if (blocks && blocks[monitor] !== undefined)
        return blocks[monitor];
    return activeId > 0 ? blockOf(activeId) : 0;
}

// The first `persistent` of the monitor's own, and any of the rest of its
// block that exist. After them come workspaces that are only visiting: those
// of a monitor that is unplugged, which had no room to join this one's.
// workspaces: [{ id, monitor }].
function monitorWorkspaceIds(workspaces, persistent, monitor, block) {
    const n = Math.max(0, Math.min(SLOTS, Math.round(Number(persistent) || 0)));
    const base = block * SLOTS;
    const own = [];
    const guests = [];
    for (let i = 1; i <= n; i++)
        own.push(base + i);
    for (const ws of workspaces || []) {
        if (!(ws.id > 0))
            continue;
        if (blockOf(ws.id) === block) {
            if (own.indexOf(ws.id) < 0)
                own.push(ws.id);
        } else if (ws.monitor === monitor && guests.indexOf(ws.id) < 0) {
            guests.push(ws.id);
        }
    }
    own.sort((a, b) => a - b);
    guests.sort((a, b) => a - b);
    return own.concat(guests);
}

// A cell's click: the monitor's own goes through haseen.workspaces.focus, which
// brings it home from wherever an unplug left it; a guest is focused as it is.
function monitorFocusCommand(id, block, monitor, usingLua) {
    if (!usingLua)
        return "workspace " + id;
    if (blockOf(id) === block)
        return "haseen.workspaces.focus(" + slotOf(id) + ", " + JSON.stringify(String(monitor)) + ")";
    return focusCommand(String(id), true);
}

// The wheel walks the row and holds at either end, so a touchpad swipe that
// runs long stops on the last workspace. -1 when there is nowhere to go.
function stepInRow(ids, activeId, steps) {
    const index = (ids || []).indexOf(activeId);
    if (index < 0 || steps === 0)
        return -1;
    const target = ids[Math.max(0, Math.min(ids.length - 1, index - steps))];
    return target === activeId ? -1 : target;
}
