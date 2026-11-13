.pragma library

// The pure half of haseen.stage (plan 163): the settings, which workspaces
// the stage shows and in what order, which windows each stack holds, the
// stack's per-card offsets, the turn towards the middle of the screen, the
// sizes for a screen and the rules that keep the edge quiet. Plain objects
// in and out, so tests/test-stage.sh runs every function under Qt's own JS
// engine without a compositor.
//
// The behaviour follows pocket-dots' Stage Manager (GPL-3.0, reference
// only, nothing copied).

const EDGES = ["left", "right"];
const DEFAULTS = {
    edge: "left",
    dwell: 200,
    maxWindows: 3,
    tilt: 50
};

function clampInt(value, min, max, fallback) {
    const n = Number(value);
    if (typeof value === "boolean" || value === null || value === "" || !isFinite(n))
        return fallback;
    return Math.max(min, Math.min(max, Math.round(n)));
}

// The plugin's settings, checked: an unknown edge is the left one, numbers
// are clamped to what the stage can draw.
function config(settings) {
    const s = settings && typeof settings === "object" ? settings : {};
    return {
        edge: EDGES.indexOf(s.edge) >= 0 ? s.edge : DEFAULTS.edge,
        dwell: clampInt(s.dwell, 100, 1000, DEFAULTS.dwell),
        maxWindows: clampInt(s.maxWindows, 1, 4, DEFAULTS.maxWindows),
        tilt: clampInt(s.tilt, 0, 60, DEFAULTS.tilt)
    };
}

// Why the edge must not open the stage now, or "" when it may. The order is
// the order a user would want explained: a locked screen first, then a game,
// then a fullscreen window, then a press (a window or a file dragged to the
// edge), then nothing to show.
// state: { locked, context, fullscreen, buttons, count }
function suppressed(state) {
    const s = state || {};
    if (s.locked === true)
        return "locked";
    if (s.context === "game")
        return "game";
    if (s.fullscreen === true)
        return "fullscreen";
    if (Number(s.buttons) > 0)
        return "dragging";
    if (s.count !== undefined && Number(s.count) <= 0)
        return "empty";
    return "";
}

function isSpecial(ws) {
    return Number(ws.id) <= 0 || String(ws.name || "").indexOf("special:") === 0;
}

// clients: [{ address, workspace, focus, cls, width, height, hidden, icon,
// toplevel }]. The windows of one workspace, the most recently focused first
// (Hyprland's focusHistoryID: 0 is the window in focus, larger is older; a
// window Hyprland has not numbered yet goes last), at most `max`. A window
// Hyprland hides (the background tabs of a group) is not drawn.
function stackWindows(clients, workspaceId, max) {
    const list = (Array.isArray(clients) ? clients : []).filter(c => c && Number(c.workspace) === Number(workspaceId) && c.hidden !== true);
    list.sort((a, b) => focusOrder(a) - focusOrder(b) || String(a.address || "").localeCompare(String(b.address || "")));
    return list.slice(0, Math.max(0, max));
}

function focusOrder(c) {
    const f = Number(c.focus);
    return c.focus !== undefined && c.focus !== null && isFinite(f) && f >= 0 ? f : 9999;
}

// workspaces: [{ id, name, monitor }] (monitor = its monitor's name).
// The stage of one monitor: its other workspaces that hold a window, not the
// special ones (scratchpads) and not the one on screen, by number.
function stacks(workspaces, clients, monitor, activeId, max) {
    const out = [];
    const seen = {};
    for (const ws of Array.isArray(workspaces) ? workspaces : []) {
        if (!ws || isSpecial(ws) || ws.monitor !== monitor || Number(ws.id) === Number(activeId) || seen[ws.id])
            continue;
        const windows = stackWindows(clients, ws.id, max);
        if (windows.length === 0)
            continue;
        seen[ws.id] = true;
        out.push({
            id: Number(ws.id),
            name: String(ws.name || ws.id),
            windows: windows
        });
    }
    out.sort((a, b) => a.id - b.id);
    return out;
}

// The sizes for a screen: the plane a front window is fitted into, the
// step between cards, the room one stack takes and how many stacks fit.
// screenWidth, height: the stage window's logical size; count: stacks.
function metrics(screenWidth, height, count, maxWindows, iconSize) {
    const icon = Math.max(0, Math.round(Number(iconSize) || 0));
    const back = Math.max(0, clampInt(maxWindows, 1, 4, DEFAULTS.maxWindows) - 1);
    const design = Math.max(160, Math.min(260, Math.round((Number(screenWidth) || 0) * 0.13)));
    const slotOf = w => {
        const planeH = Math.round(w * 0.62);
        const step = Math.max(6, Math.round(w * 0.08));
        const rise = Math.max(5, Math.round(w * 0.07));
        return {
            planeWidth: w,
            planeHeight: planeH,
            step: step,
            rise: rise,
            slot: planeH + rise * back + Math.round(icon / 2) + Math.max(8, Math.round(w * 0.06))
        };
    };
    let m = slotOf(design);
    const n = Math.max(0, Math.round(Number(count) || 0));
    const room = Math.max(0, Number(height) || 0);
    if (n > 0 && n * m.slot > room) {
        // Shrink to fit, to half size at most; past that the stage shows the
        // first stacks that fit, by number.
        const scaled = Math.max(Math.round(design * 0.5), Math.floor(design * room / (n * m.slot)));
        m = slotOf(scaled);
    }
    const shown = m.slot > 0 ? Math.min(n, Math.floor(room / m.slot)) : 0;
    m.shown = shown;
    m.top = Math.max(0, Math.round((room - shown * m.slot) / 2));
    m.stackWidth = m.planeWidth + m.step * back;
    return m;
}

// A window's card inside the plane: the front window fills the plane as far
// as its shape allows, and every other window keeps its size relative to it,
// as the windows stand on the desktop. width, height: the window's size.
function cardSize(width, height, frontWidth, frontHeight, planeWidth, planeHeight) {
    const fw = Math.max(1, Number(frontWidth) || 16), fh = Math.max(1, Number(frontHeight) || 10);
    const scale = Math.min(planeWidth / fw, planeHeight / fh);
    const w = Math.max(1, Number(width) || fw), h = Math.max(1, Number(height) || fh);
    return {
        width: Math.round(Math.max(16, Math.min(planeWidth, w * scale))),
        height: Math.round(Math.max(16, Math.min(planeHeight, h * scale)))
    };
}

// Card `index` (0 = front) of `count`: how far it sits from the edge side
// and above the front card, how big and how bright. The cards behind step
// away from the edge and up, smaller and dimmer, the way the windows behind
// the focused one sink; under the pointer they spread.
function fan(index, count, step, rise, hovered) {
    const i = Math.max(0, Math.min(Math.round(Number(index) || 0), Math.max(0, count - 1)));
    const spread = hovered ? 1.5 : 1;
    return {
        dx: Math.round(i * step * spread),
        dy: Math.round(i * rise * spread),
        scale: 1 - i * 0.06,
        opacity: i === 0 ? 1 : Math.max(0.35, 0.85 - (i - 1) * 0.15),
        z: count - i
    };
}

// The card's x in its stack: measured from the edge the stage is on.
function cardX(edge, dx, width, stackWidth) {
    return edge === "right" ? stackWidth - width - dx : dx;
}

// The turn towards the middle of the screen: a rotation about the vertical
// axis through the stack's edge side. Positive turns the far side away on
// the left edge; the right edge mirrors it. Under the pointer the stack
// turns part of the way back towards the viewer.
function tilt(edge, degrees, hovered) {
    const d = Math.max(0, Math.min(60, Number(degrees) || 0));
    const a = hovered ? Math.round(d * 0.55) : d;
    return edge === "right" ? -a : a;
}

// The rotation's axis: the stack's side nearest the edge.
function tiltOriginX(edge, stackWidth) {
    return edge === "right" ? stackWidth : 0;
}

// Where the stage's column sits while hidden: off the screen past its edge.
function slideX(edge, width, shown) {
    if (shown)
        return 0;
    return edge === "right" ? width : -width;
}

// The dispatch that switches the monitor to workspace `id`, in the syntax
// of the running Hyprland (Lua expressions since 0.56); "" for anything
// that is not a workspace number, so nothing else reaches the compositor.
function focusCommand(id, usingLua) {
    const n = Number(id);
    if (!Number.isInteger(n) || n <= 0)
        return "";
    return usingLua ? "hl.dsp.focus({ workspace = \"" + n + "\" })" : "workspace " + n;
}

// The icon-theme name for a window class with no desktop entry. The class
// is the client's own string: only a plain icon name reaches the icon theme,
// never a path or a URL (haseen.windows does the same, plan 081).
function themeIcon(cls) {
    const name = String(cls || "").toLowerCase();
    return /^[a-z0-9][a-z0-9._-]*$/.test(name) ? name : "application-x-executable";
}
