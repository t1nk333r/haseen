// Model.js: pure logic for the haseen.display panel (plan 077). Devices come
// from `haseen brightness list` lines; no QML types here, so
// tests/test-brightness.sh runs it under the real Qt JS engine.

const KINDS = ["backlight", "keyboard", "ddc"];

// Nerd Font glyphs: a sun for the panel (the OSD's), a keyboard, a monitor.
const GLYPHS = { backlight: "\uf185", keyboard: "\uf11c", ddc: "\u{F0379}" };

function glyph(kind) {
    return GLYPHS[kind] || GLYPHS.backlight;
}

function toInt(text) {
    const s = String(text === undefined || text === null ? "" : text).trim();
    return /^[0-9]+$/.test(s) ? parseInt(s, 10) : -1;
}

// parseList(text): `ID KIND PERCENT VALUE MAX NAME WATCH` lines (tabs) as
// devices, in kind order; malformed lines and unknown kinds are dropped, and
// a duplicate id keeps its first line. Names that repeat get their id added.
function parseList(text) {
    const found = [], seen = {};
    for (const line of String(text || "").split("\n")) {
        const f = line.split("\t");
        if (f.length < 7 || KINDS.indexOf(f[1]) < 0 || seen[f[0]])
            continue;
        const value = toInt(f[3]), max = toInt(f[4]);
        if (f[0] === "" || value < 0 || max <= 0)
            continue;
        seen[f[0]] = true;
        found.push({ id: f[0], kind: f[1], value: Math.min(value, max), max: max, name: f[5] || f[0], watch: f[6] === "-" ? "" : f[6] });
    }
    // By kind, each kind in the order listed (V4's sort is not stable).
    const out = [];
    for (const kind of KINDS)
        for (const d of found)
            if (d.kind === kind)
                out.push(d);
    const count = {};
    for (const d of out)
        count[d.name] = (count[d.name] || 0) + 1;
    for (const d of out)
        d.label = count[d.name] > 1 ? d.name + " · " + d.id : d.name;
    return out;
}

// merge(sysfs, ddc): one list, sysfs devices first, an id once.
function merge(a, b) {
    const ids = {}, out = [];
    for (const d of (a || []).concat(b || [])) {
        if (ids[d.id])
            continue;
        ids[d.id] = true;
        out.push(d);
    }
    return out;
}

// percent(value, max): linear, rounded, 0..100 (what the CLI prints).
function percent(value, max) {
    if (!(max > 0) || !(value >= 0))
        return 0;
    return Math.max(0, Math.min(100, Math.round(value * 100 / max)));
}

// fromFraction(x, max): the slider position (0..1) as the percent to ask
// for, snapped to the device's own levels, so a 3-level keyboard backlight
// jumps between 0, 33, 67 and 100 instead of pretending to be smooth.
function fromFraction(x, max) {
    const f = Math.max(0, Math.min(1, Number(x) || 0));
    if (!(max > 0))
        return Math.round(f * 100);
    if (max >= 100)
        return Math.round(f * 100);
    return percent(Math.round(f * max), max);
}

// setArgs(id, percent): the `haseen brightness` argv after the command.
function setArgs(id, pct) {
    return ["set", id, Math.max(0, Math.min(100, Math.round(pct))) + "%"];
}

// live(kind): true when the slider sends while it is dragged. DDC/CI writes
// take ~100 ms each and some monitors drop overlapping ones: release only.
function live(kind) {
    return kind !== "ddc";
}

// valueFor(device, pct): the raw value the CLI will set for pct, used to show
// a DDC monitor's new value without reading it back.
function valueFor(device, pct) {
    return Math.round(Math.max(0, Math.min(100, pct)) * device.max / 100);
}

// enqueue(queue, id, command): the writes waiting while one runs. A device
// keeps its place in line, and its newest value replaces the one waiting,
// so a drag sends where the slider is now, not every step on the way.
function enqueue(queue, id, command) {
    const out = (queue || []).slice();
    for (let i = 0; i < out.length; i++)
        if (out[i].id === id) {
            out[i] = { id: id, command: command };
            return out;
        }
    out.push({ id: id, command: command });
    return out;
}

// emptyText(count, ddcDone): the line shown once nothing turned up to slide.
function emptyText(count, ddcDone) {
    if (count > 0)
        return "";
    return ddcDone ? "No backlight and no monitor that answers over DDC/CI. External monitors: haseen setup ddc on." : "";
}
