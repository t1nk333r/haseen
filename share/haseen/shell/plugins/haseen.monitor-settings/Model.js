// Model.js: pure logic for the haseen.monitor-settings panel (plan 098). No
// QML types here, so tests/test-monitor-settings.sh runs it under the real Qt
// JS engine.
//
// Adapted from juliusmork-sys's Omarchy Monitor Settings Extender, Model.js
// and Panel.qml (MIT, Copyright (c) 2026 Julius Getz Mørk): the clean-scale
// rule, friendly EDID names, refresh rates per resolution, rotated
// footprints, edge snapping and the overlap push-out. haseen changes: the
// monitors come from `haseen hardware monitor list`, the snapping is one
// function instead of a drag handler, and scales are a fixed list filtered
// through the clean-scale rule.

// The scales offered; each is snapped to one Hyprland accepts for the mode.
const SCALES = [1, 1.25, 1.5, 1.6, 1.75, 2, 2.5, 3];

// Physical cursor sizes offered; the panel divides by the focused monitor's
// scale before it asks for one (hyprctl setcursor takes logical pixels).
const CURSOR_SIZES = [20, 24, 32, 40, 48, 64];

const ROTATIONS = [
    { value: 0, label: "0°" },
    { value: 1, label: "90°" },
    { value: 2, label: "180°" },
    { value: 3, label: "270°" }
];

function gcd(a, b) {
    while (b) {
        const r = a % b;
        a = b;
        b = r;
    }
    return a;
}

function normalizeScale(scale) {
    const n = parseFloat(String(scale === undefined || scale === null ? "" : scale));
    return isFinite(n) ? Math.round(n * 100) / 100 : 0;
}

// cleanScale(scale, width, height): the nearest scale at or above `scale`
// that divides the mode into whole logical pixels (Hyprland rejects others),
// on a 1/120 grid, as Omarchy's monitor scaling script does.
function cleanScale(scale, width, height) {
    const s = Number(scale), w = Number(width), h = Number(height);
    if (!(s > 0) || !(w > 0) || !(h > 0))
        return 0;
    const divisor = gcd(Math.round(w * 120), Math.round(h * 120));
    let units = Math.round(s * 120);
    if (units > divisor)
        units = divisor;
    while (divisor % units !== 0)
        units++;
    return normalizeScale(units / 120);
}

// scalesFor(width, height): SCALES snapped to the mode, each once, in order.
function scalesFor(width, height) {
    const out = [];
    for (const s of SCALES) {
        const c = cleanScale(s, width, height);
        if (c > 0 && out.indexOf(c) < 0)
            out.push(c);
    }
    return out;
}

function isInternal(name) {
    return /^(eDP|LVDS|DSI)-/i.test(String(name || ""));
}

function looksLikeRawCode(text) {
    const t = String(text || "").trim();
    return t === "" || /^0x[0-9a-f]+$/i.test(t);
}

function cleanVendor(make) {
    return String(make || "")
        .replace(/\b(Electric Company|Electronics Co\.?,?\s*Ltd\.?|Technology Co\.?,?\s*Ltd\.?|Corporation|Incorporated|Inc\.?|Corp\.?|Co\.?,?\s*Ltd\.?)\b/gi, "")
        .replace(/\s+/g, " ")
        .trim();
}

// label(monitor): "Samsung LC34G55T", "Built-in display", else the
// description, else the connector. Laptop panels' EDID model is a part
// number ("0x07DB"), never worth showing.
function label(m) {
    if (!m)
        return "";
    const name = String(m.name || "");
    if (isInternal(name))
        return "Built-in display";
    const make = cleanVendor(m.make);
    const model = String(m.model || "").trim();
    if (!looksLikeRawCode(model))
        return make && make.toLowerCase() !== model.toLowerCase() ? make + " " + model : model;
    const description = String(m.description || "").trim();
    return description || name || "Unknown display";
}

function num(v, fallback) {
    const n = Number(v);
    return isFinite(n) ? n : fallback;
}

// parseList(text): the JSON of `haseen hardware monitor list` as
// { monitors: [...], mirror, laptopOff, cursorSize }, or an empty state.
function parseList(text) {
    let data = null;
    try {
        data = JSON.parse(String(text || ""));
    } catch (e) {
        data = null;
    }
    const empty = { monitors: [], mirror: false, laptopOff: false, cursorSize: 24 };
    if (!data || typeof data !== "object" || !Array.isArray(data.monitors))
        return empty;
    const monitors = [];
    for (const m of data.monitors) {
        if (!m || typeof m.name !== "string" || !/^[A-Za-z0-9._-]+$/.test(m.name))
            continue;
        monitors.push({
            name: m.name,
            label: label(m),
            internal: isInternal(m.name),
            x: Math.round(num(m.x, 0)),
            y: Math.round(num(m.y, 0)),
            width: Math.round(num(m.width, 0)),
            height: Math.round(num(m.height, 0)),
            refreshRate: num(m.refreshRate, 0),
            scale: num(m.scale, 1) > 0 ? num(m.scale, 1) : 1,
            transform: Math.round(num(m.transform, 0)) & 7,
            disabled: m.disabled === true,
            focused: m.focused === true,
            modes: Array.isArray(m.availableModes) ? m.availableModes.map(String) : [],
            userRule: m.userRule === true
        });
    }
    return {
        monitors: monitors,
        mirror: data.mirror === true,
        laptopOff: data.laptopOff === true,
        cursorSize: num(data.cursorSize, 24) > 0 ? Math.round(num(data.cursorSize, 24)) : 24
    };
}

// ratesFor(modes, width, height): the refresh rates offered at exactly this
// resolution, highest first, each once.
function ratesFor(modes, width, height) {
    const out = [];
    for (const mode of modes || []) {
        const m = /^([0-9]+)x([0-9]+)@([0-9.]+)Hz$/.exec(String(mode).trim());
        if (!m || Number(m[1]) !== Number(width) || Number(m[2]) !== Number(height))
            continue;
        const rate = Number(m[3]);
        if (isFinite(rate) && out.indexOf(rate) < 0)
            out.push(rate);
    }
    return out.sort((a, b) => b - a);
}

function formatHz(rate) {
    const n = Math.round(Number(rate) * 100) / 100;
    if (!isFinite(n))
        return "";
    return (Number.isInteger(n) ? String(n) : n.toFixed(2)) + " Hz";
}

// nearest(values, current): hyprctl reports 164.99899 for a 165.00 mode.
function nearest(values, current) {
    let best = NaN, dist = Infinity;
    for (const v of values || []) {
        const d = Math.abs(v - Number(current));
        if (d < dist) {
            dist = d;
            best = v;
        }
    }
    return best;
}

// modeArg(monitor, rate): the --mode value for this resolution at `rate`.
function modeArg(m, rate) {
    return m.width + "x" + m.height + "@" + (Math.round(Number(rate) * 100) / 100);
}

// footprint(monitor): its size in the layout, logical pixels; a 90° or 270°
// rotation swaps width and height.
function footprint(m) {
    const s = m.scale > 0 ? m.scale : 1;
    const w = m.width / s, h = m.height / s;
    return (m.transform & 1) === 1 ? { w: h, h: w } : { w: w, h: h };
}

// rects(monitors, except): the enabled monitors' layout rectangles.
function rects(monitors, except) {
    const out = [];
    for (const m of monitors || []) {
        if (m.disabled || m.name === except)
            continue;
        const f = footprint(m);
        out.push({ name: m.name, x: m.x, y: m.y, w: f.w, h: f.h });
    }
    return out;
}

// Touching edges do not overlap, so a flush layout is never a collision.
function overlaps(a, b) {
    return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
}

// pushOut(target, other): `target` moved out of `other` along the axis that
// needs the smaller move.
function pushOut(t, o) {
    if (!overlaps(t, o))
        return { x: t.x, y: t.y };
    const px = Math.min(t.x + t.w, o.x + o.w) - Math.max(t.x, o.x);
    const py = Math.min(t.y + t.h, o.y + o.h) - Math.max(t.y, o.y);
    if (px < py)
        return { x: t.x + (t.x < o.x ? -px : px), y: t.y };
    return { x: t.x, y: t.y + (t.y < o.y ? -py : py) };
}

// resolve(target, others): a few passes, as clearing one neighbour can graze
// another; whole logical pixels, as Hyprland positions are.
function resolve(target, others) {
    let x = target.x, y = target.y;
    for (let pass = 0; pass < 4; pass++) {
        let moved = false;
        for (const o of others || []) {
            const box = { x: x, y: y, w: target.w, h: target.h };
            if (overlaps(box, o)) {
                const p = pushOut(box, o);
                x = p.x;
                y = p.y;
                moved = true;
            }
        }
        if (!moved)
            break;
    }
    return { x: Math.round(x), y: Math.round(y) };
}

// snap(x, y, w, h, others, threshold): a dragged box's edges and its
// neighbours' edges within `threshold` (layout pixels) are made to meet.
function snap(x, y, w, h, others, threshold) {
    let bx = null, by = null;
    for (const o of others || []) {
        for (const d of [o.x - x, o.x + o.w - (x + w), o.x - (x + w), o.x + o.w - x])
            if (Math.abs(d) <= threshold && (bx === null || Math.abs(d) < Math.abs(bx)))
                bx = d;
        for (const d of [o.y - y, o.y + o.h - (y + h), o.y - (y + h), o.y + o.h - y])
            if (Math.abs(d) <= threshold && (by === null || Math.abs(d) < Math.abs(by)))
                by = d;
    }
    return { x: Math.round(x + (bx === null ? 0 : bx)), y: Math.round(y + (by === null ? 0 : by)) };
}

// place(monitors, name, x, y, threshold): where a drop of `name` at x, y
// lands: snapped to its neighbours, then pushed clear of them.
function place(monitors, name, x, y, threshold) {
    const m = (monitors || []).find(v => v.name === name);
    if (!m)
        return null;
    const f = footprint(m);
    const others = rects(monitors, name);
    const s = snap(x, y, f.w, f.h, others, threshold);
    return resolve({ x: s.x, y: s.y, w: f.w, h: f.h }, others);
}

// rotated(monitors, name, transform): the position a rotation keeps the
// monitor clear of its neighbours at (the footprint changes shape in place).
function rotated(monitors, name, transform) {
    const m = (monitors || []).find(v => v.name === name);
    if (!m)
        return null;
    const f = footprint(Object.assign({}, m, { transform: transform }));
    return resolve({ x: m.x, y: m.y, w: f.w, h: f.h }, rects(monitors, name));
}

// bounds(rects): the box around them all, for the diagram's scale.
function bounds(list) {
    if (!list || list.length === 0)
        return { x: 0, y: 0, w: 1, h: 1 };
    let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
    for (const r of list) {
        x0 = Math.min(x0, r.x);
        y0 = Math.min(y0, r.y);
        x1 = Math.max(x1, r.x + r.w);
        y1 = Math.max(y1, r.y + r.h);
    }
    return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, y1 - y0) };
}

// cursorLogical(physical, scale): the logical size that draws `physical`
// pixels on a monitor at `scale`.
function cursorLogical(physical, scale) {
    return Math.max(8, Math.round(Number(physical) / (Number(scale) > 0 ? Number(scale) : 1)));
}

// cursorPhysical(logical, scale, options): the option that `logical` came
// from, so the pill that was picked stays lit after the round trip.
function cursorPhysical(logical, scale, options) {
    return nearest(options || CURSOR_SIZES, Number(logical) * (Number(scale) > 0 ? Number(scale) : 1));
}
