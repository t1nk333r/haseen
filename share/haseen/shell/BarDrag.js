.pragma library

// Dragging on the bar (plan 112): widgets anywhere in it and the bar to
// another screen edge (BarStrip.qml, BarSlot.qml, BarSection.qml,
// BarDragOverlay.qml). Pure: no Qt types, so tests/test-bar-drag.sh runs it
// under the Qt JS engine.
//
// edgeAt is adapted from Omarchy's shell/plugins/bar/Bar.qml
// (nearestScreenEdge, v4.5.0-rc1,
// https://github.com/basecamp/omarchy, MIT, Copyright (c) David Heinemeier
// Hansson).

// The room a drag opens in a section, where the widget would land. Never a
// plugin id: those are lowercase dotted names (plugin.schema.json).
const ROOM = "\u0000room";

// How far a press travels before it becomes a drag: one and a half times
// Qt's own drag distance. A widget's own drag (a MouseArea with drag.target
// or preventStealing, a Slider) starts at Qt's distance and keeps the mouse
// grab, so the bar never takes it over; and a click that slips a few pixels
// stays a click. Omarchy's bar uses 4 px, but there the bar owns every press.
function threshold(startDragDistance) {
    const d = Number(startDragDistance);
    return Math.round((d > 0 ? d : 10) * 1.5);
}

// The screen edge nearest a point on a screen, split along the screen's
// diagonals in normalised space, so a wide screen does not favour its left
// and right edges. point { x, y } and size { width, height } in the same
// units; a point off the screen counts as on its border.
function edgeAt(point, size) {
    const clamp = v => Math.max(0, Math.min(1, v));
    const nx = size && size.width > 0 ? clamp(point.x / size.width) : 0.5;
    const ny = size && size.height > 0 ? clamp(point.y / size.height) : 0.5;
    let edge = "top", best = ny;
    if (1 - ny < best) {
        edge = "bottom";
        best = 1 - ny;
    }
    if (nx < best) {
        edge = "left";
        best = nx;
    }
    if (1 - nx < best)
        edge = "right";
    return edge;
}

// Where the bar window's top-left sits on its screen (Bar.qml anchors it to
// `edge` and reaches `overlap` past both ends of it). win and screen are
// { width, height }.
function windowOrigin(edge, win, screen, overlap) {
    const o = Number(overlap) || 0;
    if (edge === "bottom")
        return { x: -o, y: screen.height - win.height };
    if (edge === "left")
        return { x: 0, y: -o };
    if (edge === "right")
        return { x: screen.width - win.width, y: -o };
    return { x: -o, y: 0 };
}

// A section's rows while a widget is dragged: its shown ids with the room
// in front of where the drop would land (Overflow.dropTarget's answer) when
// that is this section. The dragged widget keeps its own row (folded away,
// BarSection.qml), so it is never rebuilt.
function rows(ids, section, drop) {
    const out = Array.isArray(ids) ? ids.slice() : [];
    if (!drop || drop.section !== section)
        return out;
    const i = drop.before ? out.indexOf(drop.before) : -1;
    if (i < 0)
        out.push(ROOM);
    else
        out.splice(i, 0, ROOM);
    return out;
}
