.pragma library

// The arithmetic of SkewCarousel.qml, adapted from Omarchy's image picker
// (shell/plugins/image-picker/ImagePicker.qml and ImagePickerModel.js,
// MIT, Copyright (c) David Heinemeier Hansson). It uses no Qt types except
// the key constants, so tests/test-carousel.sh runs it without a window
// (plan 152).

// Omarchy's geometry (ImagePicker.qml:42-47, 389). The selected item is
// 768x475. The others are 108x432 slices that overlap by 30 px, each
// slanted 28 px. Omarchy's strip has room for 13 slice steps.
const GEOMETRY = {
    expandedWidth: 768,
    expandedHeight: 475,
    sliceWidth: 108,
    sliceHeight: 432,
    spacing: -30,
    skew: 28,
    steps: 13
};

// How many slices past the screen's edge load their picture early, so a
// slice that moves on screen is already decoded.
const PRELOAD = 2;
// The most slices on each side of a compact carousel, the one a panel card
// shows in the `center` and `bar` placements.
const COMPACT_STEPS = 2;

// The name and label of a theme or a path. "tokyo-night" reads
// "Tokyo Night", and "/x/1-deep_sea.jpg" reads "1 Deep Sea"
// (ImagePickerModel.nameForPath and labelForPath).
function nameFor(path) {
    return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "");
}

function labelFor(path) {
    return nameFor(path).replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
}

// Whether `name` matches the typed filter, as a case-insensitive substring
// of the name or of its label (ImagePickerModel.itemMatches).
function matches(name, filter) {
    const needle = String(filter || "").toLowerCase();
    if (needle === "")
        return true;
    return nameFor(name).toLowerCase().indexOf(needle) !== -1 || labelFor(name).toLowerCase().indexOf(needle) !== -1;
}

// The model indices that `filter` leaves visible, in model order.
function shown(names, filter) {
    const out = [];
    const list = names || [];
    for (let i = 0; i < list.length; i++)
        if (matches(list[i], filter))
            out.push(i);
    return out;
}

// The model index one step from `current` along `on`, in `direction` (+1
// or -1), wrapping at both ends (ImagePicker.selectAdjacent). If the filter
// hid `current`, the step goes to the first match. Returns -1 when nothing
// is visible.
function step(on, current, direction) {
    const n = on ? on.length : 0;
    if (n === 0)
        return -1;
    const at = on.indexOf(current);
    if (at < 0)
        return on[0];
    return on[((at + direction) % n + n) % n];
}

// The selection after the filter changes. It stays while it is visible and
// moves to the first match otherwise. With no match it stays unchanged, so
// clearing the filter returns to it
// (ImagePickerModel.nextSelectedIndexForFilter).
function keep(on, current) {
    if (!on || on.length === 0 || on.indexOf(current) >= 0)
        return current;
    return on[0];
}

// GEOMETRY shrunk to fit a screen `width` by `height` that needs `chrome`
// px under the carousel for its labels. The selected item keeps one slice's
// width of room on each side. Omarchy draws at full size on any screen. Here
// a screen that fits the full size keeps it (scale 1), and the geometry
// never grows.
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

// The strip that Omarchy centres on the screen, and the card around it that
// takes clicks without closing the picker (ImagePicker.qml:389, 393, 402).
function stripWidth(g) {
    return g.expandedWidth + g.steps * (g.sliceWidth + g.spacing);
}

function cardWidth(g, screenWidth) {
    const w = stripWidth(g) + 40;
    return screenWidth > 0 ? Math.min(screenWidth - 80, w) : w;
}

// The screen width that shows the carousel at full size with every step.
// The carousel assumes it when it has no screen to fit.
function designWidth() {
    return stripWidth(GEOMETRY) + 120;
}

// The width a compact carousel fits instead of the screen's. It holds the
// selected item and COMPACT_STEPS slices on each side at full size, in its
// card.
function compactWidth() {
    return GEOMETRY.expandedWidth + 2 * COMPACT_STEPS * (GEOMETRY.sliceWidth + GEOMETRY.spacing) + 120;
}

// How many slices on each side of the selected one reach into `width`. It
// is 0 before the carousel has a width, so nothing loads before layout.
function reach(width, g) {
    const stepPx = g.sliceWidth + g.spacing;
    if (!(width > 0))
        return 0;
    if (stepPx <= 0)
        return g.steps;
    const room = (width - g.expandedWidth) / 2 - g.spacing;
    return Math.max(1, Math.ceil(room / stepPx));
}

// The rectangle { x, y, width, height, z } of the item `rel` places from the
// selected one, in a carousel `width` wide (ImagePicker.qml:406-407,
// 458-462). The selected item is centred, earlier items go left and later
// ones right. A right-to-left carousel swaps the sides.
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

// How many slices on each side fit wholly inside `width`, at most `cap`. A
// compact carousel in a panel card shows no slice that its card would cut.
// The slices sit symmetrically, so mirroring changes nothing here.
function fitReach(width, g, cap) {
    for (let n = cap; n > 0; n--) {
        const left = slot(-n, width, false, g);
        const right = slot(n, width, false, g);
        if (left.x >= 0 && right.x + right.width <= width)
            return n;
    }
    return 0;
}

// Omarchy's filter keys (Util.editsFilter and editedFilter). Backspace
// deletes a character, Ctrl+Backspace a word, and Ctrl+U the whole filter.
// Keys with Alt or Meta belong to other shortcuts.
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

// Whether a key types into the filter. It must be one printable character,
// with no modifier or with Shift only.
function typed(text, modifiers) {
    return text.length === 1 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127 && (modifiers === Qt.NoModifier || modifiers === Qt.ShiftModifier);
}
