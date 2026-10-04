// NightlightLogic.js: the pure parts of haseen.nightlight (plan 019),
// unit-tested under node in tests/test-ambient.sh.

// "HH:MM" or "H:MM" -> minutes after midnight; -1 for anything else.
function parseTime(s) {
    const m = /^\s*([01]?\d|2[0-3]):([0-5]\d)\s*$/.exec(typeof s === "string" ? s : "");
    return m ? Number(m[1]) * 60 + Number(m[2]) : -1;
}

// Whether the schedule says "night" at nowMinutes; null without a schedule
// (either time missing or both equal). sunset < sunrise also works (a
// window after midnight, e.g. 01:00-06:00).
function scheduled(nowMinutes, sunset, sunrise) {
    const on = parseTime(sunset);
    const off = parseTime(sunrise);
    if (on < 0 || off < 0 || on === off)
        return null;
    if (on > off)
        return nowMinutes >= on || nowMinutes < off;
    return nowMinutes >= on && nowMinutes < off;
}

// Colour temperature in K: an integer in hyprsunset's useful range, else
// the 4000 K default.
function temperature(v) {
    return (typeof v === "number" && isFinite(v) && v >= 1000 && v <= 20000) ? Math.round(v) : 4000;
}

if (typeof module !== "undefined")
    module.exports = { parseTime: parseTime, scheduled: scheduled, temperature: temperature };
