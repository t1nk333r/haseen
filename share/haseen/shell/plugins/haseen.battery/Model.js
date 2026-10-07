// Model.js: pure formatting for the haseen.battery widget and panel
// (plan 076). Devices are UPowerDevice-shaped objects; no QML types here, so
// tests/test-battery.sh runs it under the real Qt JS engine.

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
function stateLabel(state, holding, window) {
    if (holding)
        return window ? "Plugged in, holding at " + window : "Plugged in, not charging";
    return {
        "charging": "Charging",
        "discharging": "On battery",
        "empty": "Empty",
        "full": "Fully charged",
        "pending-charge": "Plugged in, not charging",
        "pending-discharge": "On battery",
        "unknown": "Unknown"
    }[stateKey(state)];
}

// "1 h 05 min", "12 min", "" for an unknown time (seconds <= 0).
function duration(seconds) {
    const s = Number(seconds);
    if (!isFinite(s) || s <= 0)
        return "";
    const m = Math.max(1, Math.round(s / 60));
    if (m < 60)
        return m + " min";
    const h = Math.floor(m / 60);
    const rest = m % 60;
    return rest === 0 ? h + " h" : h + " h " + (rest < 10 ? "0" : "") + rest + " min";
}

// "2 h 10 min left" on battery, "45 min to full" while charging, else "".
function timeLine(state, timeToEmpty, timeToFull) {
    const k = stateKey(state);
    if (k === "charging") {
        const d = duration(timeToFull);
        return d ? d + " to full" : "";
    }
    if (k === "discharging" || k === "pending-discharge") {
        const d = duration(timeToEmpty);
        return d ? d + " left" : "";
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
    return { "power-saver": "Power saver", "balanced": "Balanced", "performance": "Performance" }[name] || String(name || "");
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
    return end >= 100 ? "Full" : end + "%";
}

// `haseen battery limit` arguments for a pill.
function limitArgs(end) {
    return end >= 100 ? ["off"] : ["set", String(end)];
}
