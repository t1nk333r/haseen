// IdleLogic.js: the pure decisions of haseen.idle (plan 019), kept out of
// QML so tests/test-ambient.sh can run them under node. No QML or Quickshell
// types here.

// A non-negative whole number of seconds, else the fallback.
function seconds(v, fallback) {
    return (typeof v === "number" && isFinite(v) && v >= 0) ? Math.round(v) : fallback;
}

// Timeouts in seconds for the screensaver, lock and dpms monitors; 0 turns
// a monitor off. flags: { idleOff, screensaverOff }. haveScreensaver: a
// running plugin answers the `screensaver` role.
function timeouts(settings, flags, haveScreensaver) {
    const s = settings || {};
    const f = flags || {};
    if (f.idleOff)
        return { screensaver: 0, lock: 0, dpms: 0 };
    const lock = seconds(s.lockAfter, 300);
    const dpms = seconds(s.dpmsAfter, 330);
    let screensaver = seconds(s.screensaverAfter, 150);
    if (f.screensaverOff || !haveScreensaver)
        screensaver = 0;
    // A screensaver due at or after the lock would never be seen.
    if (lock > 0 && screensaver >= lock)
        screensaver = 0;
    return { screensaver: screensaver, lock: lock, dpms: dpms };
}

// What to do when one monitor's isIdle changes. monitor: "screensaver",
// "lock" or "dpms". state: { dpmsOff } (the service turned displays off).
// Returns action names: screensaver.start, screensaver.dismiss, lock,
// dpms.off, dpms.on.
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
    }
    return [];
}

// One key per monitor to run, "name:seconds:respect" (respect 1 or 0), so a
// model of plain strings recreates exactly the monitors whose parameters
// changed.
function monitors(t, respectInhibitors) {
    const out = [];
    for (const name of ["screensaver", "lock", "dpms"]) {
        if (t && t[name] > 0)
            out.push(name + ":" + t[name] + ":" + (respectInhibitors ? 1 : 0));
    }
    return out;
}

function parseMonitor(key) {
    const p = String(key).split(":");
    return { name: p[0], timeout: Number(p[1]) || 1, respectInhibitors: p[2] !== "0" };
}

if (typeof module !== "undefined")
    module.exports = { seconds: seconds, timeouts: timeouts, actions: actions, monitors: monitors, parseMonitor: parseMonitor };
