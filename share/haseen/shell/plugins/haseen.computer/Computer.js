.pragma library

// The arithmetic behind haseen.computer's panel (plan 162): the history kept
// while the panel is open, where each sample lands on a graph, the smooth line
// through them, the temperature's word, the sizes and the uptime. No Qt or
// Quickshell types, so tests/test-computer.sh runs it headless under
// /usr/lib/qt6/bin/qml.
//
// Behaviour taken from pocket-dots' "Your computer" panel (GPL-3.0,
// reference only, nothing copied).

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// The span every graph shows, and how often the panel asks the sidecar for a
// sample while it is open: 30 samples make the 90 s line.
var WINDOW_MS = 90000;
var INTERVAL_MS = 3000;

// push(history, t, value) -> a new history with {t, v} appended and every
// sample older than the window before t dropped. A value that is not a
// finite number, or a negative one (the sidecar's -1, "unknown"), is not
// recorded, so a sensor that never answers leaves its history empty. A new
// array each time, so a QML binding on the property sees the change.
function push(history, t, value, windowMs) {
    const span = windowMs > 0 ? windowMs : WINDOW_MS;
    const kept = (history || []).filter(s => s && t - s.t <= span);
    if (typeof value === "number" && isFinite(value) && value >= 0)
        kept.push({ t: t, v: value });
    return kept;
}

// The top of a percentage graph: the smallest of 10, 25, 50 and 100 that the
// highest sample stays under. Four steps, so the scale does not change on
// every sample, and it never shrinks a busy line to the bottom of the card.
const CEILINGS = [10, 25, 50, 100];

function ceiling(history) {
    let top = 0;
    for (const s of history || [])
        top = Math.max(top, s.v);
    for (const c of CEILINGS)
        if (top <= c)
            return c;
    return 100;
}

// The temperature graph's range: whole tens around the samples, at least
// 20 °C tall, so a sensor that wanders by one degree draws a flat line, not a
// mountain range.
function tempRange(history) {
    let lo = Infinity;
    let hi = -Infinity;
    for (const s of history || []) {
        lo = Math.min(lo, s.v);
        hi = Math.max(hi, s.v);
    }
    if (!isFinite(lo))
        return { lo: 30, hi: 50 };
    lo = Math.floor((lo - 2) / 10) * 10;
    hi = Math.ceil((hi + 2) / 10) * 10;
    if (hi - lo < 20) {
        // Widen around the middle, still on whole tens.
        lo = Math.floor(((lo + hi) / 2 - 10) / 10) * 10;
        hi = lo + 20;
    }
    if (lo < 0) {
        hi -= lo;
        lo = 0;
    }
    return { lo: lo, hi: hi };
}

// points(history, width, height, lo, hi) -> [{x, y}] in item pixels. Time runs
// left to right, the newest sample on the right edge and the window's start
// on the left, so a panel that opened a moment ago draws a short line that
// grows leftwards. The line keeps a margin of `pad` pixels at the top and
// bottom so a sample at the ceiling or at zero is not cut by the card.
function points(history, width, height, lo, hi, windowMs, pad) {
    const list = history || [];
    if (list.length === 0 || !(width > 0) || !(height > 0))
        return [];
    const span = windowMs > 0 ? windowMs : WINDOW_MS;
    const inset = pad > 0 ? pad : 0;
    const usable = Math.max(1, height - 2 * inset);
    const range = hi > lo ? hi - lo : 1;
    const newest = list[list.length - 1].t;
    return list.map(s => {
        const f = Math.max(0, Math.min(1, (s.v - lo) / range));
        return {
            x: Math.max(0, Math.min(width, width - (newest - s.t) / span * width)),
            y: inset + (1 - f) * usable
        };
    });
}

function _n(v) {
    return (Math.round(v * 100) / 100).toString();
}

// The slopes of a monotone cubic through the points (Fritsch and Carlson), so
// the curve is smooth but never swings past its samples: a line at 0 % does
// not dip under the card's floor and a peak is not drawn higher than it was.
function _slopes(p) {
    const n = p.length;
    const d = [];
    for (let i = 0; i < n - 1; i++) {
        const dx = p[i + 1].x - p[i].x;
        d.push(dx > 0 ? (p[i + 1].y - p[i].y) / dx : 0);
    }
    const m = [d[0]];
    for (let i = 1; i < n - 1; i++)
        m.push(d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2);
    m.push(d[n - 2]);
    for (let i = 0; i < n - 1; i++) {
        if (d[i] === 0) {
            m[i] = 0;
            m[i + 1] = 0;
            continue;
        }
        const a = m[i] / d[i];
        const b = m[i + 1] / d[i];
        const h = a * a + b * b;
        if (h > 9) {
            const t = 3 / Math.sqrt(h);
            m[i] = t * a * d[i];
            m[i + 1] = t * b * d[i];
        }
    }
    return m;
}

// linePath(points) -> an SVG path through the points for a Shapes PathSvg:
// "" for none, a dot's worth of line for one, cubic segments otherwise.
function linePath(p) {
    if (!p || p.length === 0)
        return "";
    if (p.length === 1)
        return "M " + _n(p[0].x) + " " + _n(p[0].y) + " L " + _n(p[0].x) + " " + _n(p[0].y);
    const m = _slopes(p);
    let path = "M " + _n(p[0].x) + " " + _n(p[0].y);
    for (let i = 0; i < p.length - 1; i++) {
        const dx = (p[i + 1].x - p[i].x) / 3;
        path += " C " + _n(p[i].x + dx) + " " + _n(p[i].y + m[i] * dx) + " " + _n(p[i + 1].x - dx) + " " + _n(p[i + 1].y - m[i + 1] * dx) + " " + _n(p[i + 1].x) + " " + _n(p[i + 1].y);
    }
    return path;
}

// areaPath(points, floor) -> the line closed down to `floor`, for the faint
// fill under it; "" until there are two points.
function areaPath(p, floor) {
    if (!p || p.length < 2)
        return "";
    return linePath(p) + " L " + _n(p[p.length - 1].x) + " " + _n(floor) + " L " + _n(p[0].x) + " " + _n(floor) + " Z";
}

// The word under the temperature. Laptop and desktop processors idle between
// 35 and 55 °C and run in the 60s and 70s under sustained load; Intel parts
// throttle at 100 °C and AMD's at 95 °C (Tctl), with fans at full speed from
// about 80 °C. So: under 60 is Cool, 60 to 79 Warm, 80 and over Hot.
const WARM_AT = 60;
const HOT_AT = 80;

function tempLevel(c) {
    if (typeof c !== "number" || !isFinite(c) || c < 0)
        return -1;
    return c >= HOT_AT ? 2 : c >= WARM_AT ? 1 : 0;
}

function tempWord(c) {
    return [N_("Cool"), N_("Warm"), N_("Hot")][tempLevel(c)] || "";
}

// KiB -> GiB as a number, rounded to one decimal place the way the panel
// shows it ("6.5 of 15.4 GiB").
function gib(kib) {
    if (typeof kib !== "number" || !isFinite(kib) || kib < 0)
        return -1;
    return Math.round(kib / 1048576 * 10) / 10;
}

// /proc/uptime ("64012.34 250000.10") -> {days, hours, minutes}, or null.
// Under an hour shows minutes, under a day hours and minutes, else days and
// hours; the panel picks the words (I18n.tr) from which fields are set.
function uptime(text) {
    const seconds = parseFloat(String(text || "").trim().split(/\s+/)[0]);
    if (!isFinite(seconds) || seconds < 0)
        return null;
    const minutes = Math.floor(seconds / 60);
    return {
        days: Math.floor(minutes / 1440),
        hours: Math.floor(minutes / 60) % 24,
        minutes: minutes % 60,
        totalMinutes: minutes
    };
}

// /proc/loadavg ("1.35 0.98 0.80 2/1234 5678") -> the one-minute load, or -1.
function loadAverage(text) {
    const v = parseFloat(String(text || "").trim().split(/\s+/)[0]);
    return isFinite(v) && v >= 0 ? v : -1;
}

// /sys/devices/system/cpu/online ("0-7", "0-3,5,7-8") -> how many logical
// CPUs (threads) are online, or 0 when the file says nothing usable.
function cpuCount(text) {
    let n = 0;
    for (const part of String(text || "").trim().split(",")) {
        const m = /^(\d+)(?:-(\d+))?$/.exec(part.trim());
        if (!m)
            continue;
        const a = parseInt(m[1], 10);
        const b = m[2] === undefined ? a : parseInt(m[2], 10);
        if (b >= a)
            n += b - a + 1;
    }
    return n;
}

// The disk the storage card shows: the one mounted at `mount` (the plugin's
// setting, "/" by default), else the root filesystem, else none. The sidecar
// lists each block device once, at its shortest mountpoint, so a btrfs root is
// found at "/" whatever subvolumes it also carries.
function pickDisk(disks, mount) {
    const list = Array.isArray(disks) ? disks : [];
    const want = typeof mount === "string" && mount !== "" ? mount : "/";
    return list.find(d => d && d.mount === want) || list.find(d => d && d.mount === "/") || null;
}

if (typeof module !== "undefined")
    module.exports = { WINDOW_MS, INTERVAL_MS, push, ceiling, tempRange, points, linePath, areaPath, tempLevel, tempWord, gib, uptime, loadAverage, cpuCount, pickDisk };
