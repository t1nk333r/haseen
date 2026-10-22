// Model.js: pure formatting for the haseen.battery widget and panel
// (plan 076). Devices are UPowerDevice-shaped objects; no QML types here, so
// tests/test-battery.sh runs it under the real Qt JS engine.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// %1..%9 filled from the further arguments: the English stand-in for
// I18n.tr. The formatters that build a sentence take an optional `tr`, so
// the tests get English and the panel passes I18n.tr for its language.
function fill(text, ...args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => {
        const value = args[Number(digit) - 1];
        return value === undefined || value === null ? whole : String(value);
    });
}

// The translator to use: `tr` when the caller passed one (a map() index is
// not one), else English.
function translator(tr) {
    return typeof tr === "function" ? tr : fill;
}

// Battery glyphs (Nerd Font, Material Design): empty to full in tenths, and
// the charging one.
const LEVEL_GLYPHS = ["\u{F008E}", "\u{F007A}", "\u{F007B}", "\u{F007C}", "\u{F007D}", "\u{F007E}", "\u{F007F}", "\u{F0080}", "\u{F0081}", "\u{F0082}", "\u{F0079}"];
const CHARGING_GLYPH = "\u{F0084}";

function glyph(percent, charging) {
    if (charging)
        return CHARGING_GLYPH;
    const p = Number(percent) || 0;
    return LEVEL_GLYPHS[Math.max(0, Math.min(10, Math.round(p / 10)))];
}

// UPowerDeviceState (Quickshell 0.3.1) by number.
function stateKey(state) {
    return ["unknown", "charging", "discharging", "empty", "full", "pending-charge", "pending-discharge"][state] || "unknown";
}

function isCharging(state) {
    const k = stateKey(state);
    return k === "charging" || k === "full" || k === "pending-charge";
}

// holding: haseen-battery-status says the charge limit keeps the plugged-in
// battery from charging; window: its "75-80%".
function stateLabel(state, holding, window, tr) {
    const t = translator(tr);
    if (holding)
        return window ? t(N_("Plugged in, holding at %1"), window) : t(N_("Plugged in, not charging"));
    return t({
        "charging": N_("Charging"),
        "discharging": N_("On battery"),
        "empty": N_("Empty"),
        "full": N_("Fully charged"),
        "pending-charge": N_("Plugged in, not charging"),
        "pending-discharge": N_("On battery"),
        "unknown": N_("Unknown")
    }[stateKey(state)]);
}

// "1 h 05 min", "12 min", "" for an unknown time (seconds <= 0).
function duration(seconds, tr) {
    const t = translator(tr);
    const s = Number(seconds);
    if (!isFinite(s) || s <= 0)
        return "";
    const m = Math.max(1, Math.round(s / 60));
    if (m < 60)
        return t(N_("%1 min"), m);
    const h = Math.floor(m / 60);
    const rest = m % 60;
    return rest === 0 ? t(N_("%1 h"), h) : t(N_("%1 h %2 min"), h, (rest < 10 ? "0" : "") + rest);
}

// "2 h 10 min left" on battery, "45 min to full" while charging, else "".
function timeLine(state, timeToEmpty, timeToFull, tr) {
    const t = translator(tr);
    const k = stateKey(state);
    if (k === "charging") {
        const d = duration(timeToFull, tr);
        return d ? t(N_("%1 to full"), d) : "";
    }
    if (k === "discharging" || k === "pending-discharge") {
        const d = duration(timeToEmpty, tr);
        return d ? t(N_("%1 left"), d) : "";
    }
    return "";
}

function trim1(x) {
    return (Math.round(x * 10) / 10).toFixed(1).replace(/\.0$/, "");
}

// UPower's EnergyRate in W, positive both ways; "" when it reports none.
function rate(watts) {
    const w = Math.abs(Number(watts) || 0);
    return w > 0 ? trim1(w) + " W" : "";
}

// "41.2 / 50 Wh"; "" without a capacity.
function energy(now, full) {
    const f = Number(full) || 0;
    return f > 0 ? trim1(Math.max(0, Number(now) || 0)) + " / " + trim1(f) + " Wh" : "";
}

// UPowerDevice.healthPercentage is UPower's Capacity, 0-100 (measured in
// plan 076's nested run); "" when the device does not report it.
function health(value, supported) {
    const v = Number(value) || 0;
    if (!supported || v <= 0)
        return "";
    return Math.round(Math.min(v, 100)) + "%";
}

// PowerProfile (Quickshell 0.3.1) by number -> power-profiles-daemon's name.
function profileName(profile) {
    return ["power-saver", "balanced", "performance"][profile] || "";
}

function profileLabel(name) {
    return { "power-saver": N_("Power saver"), "balanced": N_("Balanced"), "performance": N_("Performance") }[name] || String(name || "");
}

// `haseen powerprofile list`: one known profile per line, weakest first.
function profiles(text) {
    const order = ["power-saver", "balanced", "performance"];
    const seen = String(text || "").split("\n").map(l => l.trim().split("\t")[0]).filter(n => order.indexOf(n) >= 0);
    return order.filter(n => seen.indexOf(n) >= 0);
}

// `haseen battery status --shell`: tab-separated key/value lines.
function parseStatus(text) {
    const out = {};
    for (const line of String(text || "").split("\n")) {
        const tab = line.indexOf("\t");
        if (tab > 0)
            out[line.slice(0, tab)] = line.slice(tab + 1).trim();
    }
    return out;
}

// The end of the charge-limit window ("75-80%" or "80%") as a number; -1
// when the battery has no charge_control thresholds.
function limitEnd(threshold) {
    const m = /^(?:\d{1,3}-)?(\d{1,3})%$/.exec(String(threshold || "").trim());
    return m ? Number(m[1]) : -1;
}

// The limits offered as pills, ascending: 60, 80 and 100 (no limit), plus the
// one in force when it is none of them. Empty without thresholds.
function limitChoices(end) {
    if (end < 0)
        return [];
    const c = [60, 80, 100];
    if (c.indexOf(end) < 0)
        c.push(end);
    return c.sort((a, b) => a - b);
}

function limitLabel(end) {
    return end >= 100 ? N_("Full") : end + "%";
}

// `haseen battery limit` arguments for a pill.
function limitArgs(end) {
    return end >= 100 ? ["off"] : ["set", String(end)];
}
