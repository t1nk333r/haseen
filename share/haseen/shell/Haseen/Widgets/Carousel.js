.pragma library

// The arithmetic of SkewCarousel.qml, after Omarchy's image picker
// (shell/plugins/image-picker/ImagePicker.qml and ImagePickerModel.js,
// MIT, Copyright (c) David Heinemeier Hansson). Pure: no Qt types beyond the
// key constants, so tests/test-carousel.sh runs it headless (plan 152).

// Omarchy's geometry (ImagePicker.qml:42-47): the selected item at 768x475,
// the others as 108x432 slices that overlap by 30, every one slanted 28 px.
// 13 slice steps fit in Omarchy's strip beside the selected one.
const GEOMETRY = {
    expandedWidth: 768,
    expandedHeight: 475,
    sliceWidth: 108,
    sliceHeight: 432,
    spacing: -30,
    skew: 28,
    steps: 13
};

// The slices that may load their picture beyond those on screen, so one
// arriving from the edge is already decoded.
const PRELOAD = 2;

// "tokyo-night" or "/x/1-deep_sea.jpg" -> "Tokyo Night", "1 Deep Sea"
// (ImagePickerModel.nameForPath, labelForPath).
function nameFor(path) {
    return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "");
}

function labelFor(path) {
    return nameFor(path).replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
}

// Whether `name` matches the typed filter: a case-insensitive substring of
// the name or of its label (ImagePickerModel.itemMatches).
function matches(name, filter) {
    const needle = String(filter || "").toLowerCase();
    if (needle === "")
        return true;
    return nameFor(name).toLowerCase().indexOf(needle) !== -1 || labelFor(name).toLowerCase().indexOf(needle) !== -1;
}

// The model indices on show for `filter`, in model order.
function shown(names, filter) {
    const out = [];
    const list = names || [];
    for (let i = 0; i < list.length; i++)
        if (matches(list[i], filter))
            out.push(i);
    return out;
}

// The model index `direction` (+1 or -1) steps to from `current` along
// `on`, wrapping at both ends (ImagePicker.selectAdjacent). A current
// index the filter hid steps from the first match. -1 when nothing shows.
function step(on, current, direction) {
    const n = on ? on.length : 0;
    if (n === 0)
        return -1;
    const at = on.indexOf(current);
    if (at < 0)
        return on[0];
    return on[((at + direction) % n + n) % n];
}

// The selection after the filter changed: kept while it still shows, else
// the first match, else unchanged, so clearing the filter returns to it
// (ImagePickerModel.nextSelectedIndexForFilter).
function keep(on, current) {
    if (!on || on.length === 0 || on.indexOf(current) >= 0)
        return current;
    return on[0];
}

// GEOMETRY shrunk to fit a screen of width x height whose labels need
// `chrome` px under the carousel: the selected item keeps one slice of
// room on each side. Omarchy draws at full size whatever the screen; a
// screen it fits on keeps that size (scale 1).
function fit(width, height, chrome) {
    const g = GEOMETRY;
    let s = 1;
    if (width > 0)
        s = Math.min(s, (width - 2 * g.sliceWidth) / g.expandedWidth);
    if (height > 0)
        s = Math.min(s, (height - (chrome || 0)) / g.expandedHeight);
    s = Math.max(0.25, s);
    const r = v => Math.round(v * s);
    return {
        scale: s,
        expandedWidth: r(g.expandedWidth),
        expandedHeight: r(g.expandedHeight),
        sliceWidth: r(g.sliceWidth),
        sliceHeight: r(g.sliceHeight),
        spacing: r(g.spacing),
        skew: r(g.skew),
        steps: g.steps
    };
}

// The strip Omarchy centres on the screen, and the card around it that
// takes clicks without closing the picker (ImagePicker.qml:389,392,402).
function stripWidth(g) {
    return g.expandedWidth + g.steps * (g.sliceWidth + g.spacing);
}

function cardWidth(g, screenWidth) {
    const w = stripWidth(g) + 40;
    return screenWidth > 0 ? Math.min(screenWidth - 80, w) : w;
}

// How many slices beside the selected one reach into `width`, on each side.
function reach(width, g) {
    const stepPx = g.sliceWidth + g.spacing;
    if (!(width > 0) || stepPx <= 0)
        return g.steps;
    const room = (width - g.expandedWidth) / 2 - g.spacing;
    return Math.max(1, Math.ceil(room / stepPx));
}

// Where the item `rel` places from the selected one sits in a carousel
// `width` wide: { x, y, width, height, z } (ImagePicker.qml:406-407,458-461). The
// selected item is centred; earlier items go left, later ones right, and a
// mirrored (right-to-left) carousel swaps the sides.
function slot(rel, width, mirrored, g) {
    const previewX = (width - g.expandedWidth) / 2;
    const stepPx = g.sliceWidth + g.spacing;
    let r;
    if (rel === 0)
        r = { x: previewX, y: 0, width: g.expandedWidth, height: g.expandedHeight, z: 100 };
    else
        r = {
            x: rel < 0 ? previewX + rel * stepPx : previewX + g.expandedWidth + g.spacing + (rel - 1) * stepPx,
            y: (g.expandedHeight - g.sliceHeight) / 2,
            width: g.sliceWidth,
            height: g.sliceHeight,
            z: 50 - Math.min(Math.abs(rel), 40)
        };
    if (mirrored)
        r.x = width - r.x - r.width;
    r.x = Math.round(r.x);
    r.y = Math.round(r.y);
    return r;
}

// Omarchy's filter editing keys (Util.editsFilter/editedFilter): Backspace
// drops a character, Ctrl+Backspace a word, Ctrl+U the whole filter.
// Alt- and Meta-modified keys belong to other shortcuts.
function editsFilter(key, modifiers, text) {
    if (!text || (modifiers & (Qt.AltModifier | Qt.MetaModifier)))
        return false;
    if (key === Qt.Key_U)
        return modifiers === Qt.ControlModifier;
    return key === Qt.Key_Backspace;
}

function editedFilter(key, modifiers, text) {
    if (key === Qt.Key_U)
        return "";
    if (modifiers & Qt.ControlModifier)
        return text.replace(/\s+$/, "").replace(/\S+$/, "");
    return text.slice(0, -1);
}

// A key that types into the filter: one printable character, unmodified or
// shifted.
function typed(text, modifiers) {
    return text.length === 1 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127 && (modifiers === Qt.NoModifier || modifiers === Qt.ShiftModifier);
}
