// IdleLogic.js: the pure decisions of haseen.idle (plan 019), kept out of
// QML so tests/test-ambient.sh can run them under node. No QML or Quickshell
// types here.

// A non-negative whole number of seconds, else the fallback.
function seconds(v, fallback) {
    return (typeof v === "number" && isFinite(v) && v >= 0) ? Math.round(v) : fallback;
}

// The timeout settings an onBattery override may replace (plan 082).
const TIMEOUT_KEYS = ["screensaverAfter", "lockAfter", "dpmsAfter", "suspendAfter"];

// The settings in force: on battery, each valid number in
// settings.onBattery replaces the AC value; a missing, null or invalid key
// keeps it. On AC (or without an override object) the settings as they are.
function effective(settings, onBattery) {
    const s = Object.assign({}, settings || {});
    const b = s.onBattery;
    if (onBattery === true && b !== null && typeof b === "object" && !Array.isArray(b)) {
        for (const k of TIMEOUT_KEYS) {
            if (seconds(b[k], -1) >= 0)
                s[k] = b[k];
        }
    }
    return s;
}

// Timeouts in seconds for the screensaver, lock, dpms and suspend monitors;
// 0 turns a monitor off. flags: { idleOff, screensaverOff, onBattery }.
// haveScreensaver: a running plugin answers the `screensaver` role.
function timeouts(settings, flags, haveScreensaver) {
    const f = flags || {};
    const s = effective(settings, f.onBattery);
    if (f.idleOff)
        return { screensaver: 0, lock: 0, dpms: 0, suspend: 0 };
    const lock = seconds(s.lockAfter, 300);
    const dpms = seconds(s.dpmsAfter, 330);
    const suspend = seconds(s.suspendAfter, 0);
    let screensaver = seconds(s.screensaverAfter, 150);
    if (f.screensaverOff || !haveScreensaver)
        screensaver = 0;
    // A screensaver due at or after the lock would never be seen.
    if (lock > 0 && screensaver >= lock)
        screensaver = 0;
    return { screensaver: screensaver, lock: lock, dpms: dpms, suspend: suspend };
}

// What to do when one monitor's isIdle changes. monitor: "screensaver",
// "lock", "dpms" or "suspend". state: { dpmsOff (the service turned
// displays off), idleOff (Stay Awake, set by `haseen toggle idle` and the
// game/present contexts) }. Returns action names: screensaver.start,
// screensaver.dismiss, lock, dpms.off, dpms.on, suspend.
function actions(monitor, isIdle, state) {
    const st = state || {};
    switch (monitor) {
    case "screensaver":
        return isIdle ? ["screensaver.start"] : ["screensaver.dismiss"];
    case "lock":
        // The lock covers everything; dropping the screensaver first means
        // nothing is left behind after unlocking.
        return isIdle ? ["screensaver.dismiss", "lock"] : [];
    case "dpms":
        if (isIdle)
            return ["dpms.off"];
        return st.dpmsOff ? ["dpms.on"] : [];
    case "suspend":
        // idle-off removes the monitor; this guards the moment between the
        // flag landing and the monitor going away.
        return isIdle && !st.idleOff ? ["suspend"] : [];
    }
    return [];
}

// One key per monitor to run, "name:seconds:respect" (respect 1 or 0), so a
// model of plain strings recreates exactly the monitors whose parameters
// changed. Suspend always honours idle inhibitors, whatever
// respectInhibitors says: the machine never sleeps under a playing video.
function monitors(t, respectInhibitors) {
    const out = [];
    for (const name of ["screensaver", "lock", "dpms", "suspend"]) {
        if (t && t[name] > 0)
            out.push(name + ":" + t[name] + ":" + (respectInhibitors || name === "suspend" ? 1 : 0));
    }
    return out;
}

function parseMonitor(key) {
    const p = String(key).split(":");
    return { name: p[0], timeout: Number(p[1]) || 1, respectInhibitors: p[2] !== "0" };
}

if (typeof module !== "undefined")
    module.exports = { seconds: seconds, effective: effective, timeouts: timeouts, actions: actions, monitors: monitors, parseMonitor: parseMonitor };
