// IdleLogic.js: the pure decisions of haseen.idle (plan 019), kept out of
// QML so tests/test-ambient.sh can run them under node. No QML or Quickshell
// types here.

// The longest timeout an IdleMonitor can take. Quickshell 0.3.1 turns
// seconds into ms with static_cast<int>(timeout * 1000) clamped at 0
// (src/wayland/idle_notify/monitor.cpp), so anything above INT_MAX ms
// (2147483 s, about 24.8 days) becomes a 0 ms timeout: idle at once.
const MAX_SECONDS = 2147483;

// A non-negative whole number of seconds, else the fallback. A larger
// value means "practically never" and is held at MAX_SECONDS rather than
// let through to wrap into an immediate timeout.
function seconds(v, fallback) {
    return (typeof v === "number" && isFinite(v) && v >= 0) ? Math.min(Math.round(v), MAX_SECONDS) : fallback;
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
// "lock", "dpms", "suspend", or "presence" (the input-only monitor of a
// screensaver cycle, see monitors()). state: { dpmsOff (the service turned
// displays off), idleOff (Stay Awake, set by `haseen toggle idle` and the
// game/present contexts), cycle (a screensaver cycle is running), removed
// (the monitor is going away while idle: its non-idle edge without input) }.
// Returns action names: screensaver.start, screensaver.dismiss, lock,
// dpms.off, dpms.on, suspend, cycle.start, cycle.end.
function actions(monitor, isIdle, state) {
    const st = state || {};
    // In a screensaver cycle, an inhibitor-aware monitor going back to
    // active is not someone coming back: Hyprland 0.56 re-checks idle
    // inhibitors on every window map, focus change and fullscreen change,
    // and each re-check restarts every inhibitor-aware count, even when
    // nothing inhibits (plan 140). The screensaver's own window is such a
    // map. The cycle's presence monitor counts input only and ends it.
    if (st.cycle && !isIdle && !st.removed && monitor !== "presence")
        return [];
    switch (monitor) {
    case "screensaver":
        // A screensaver monitor replaced during a cycle (a new
        // screensaverAfter) fires again: the cycle already runs, and starting
        // it again would restart the lock's count (monitors()).
        if (isIdle)
            return st.cycle ? ["screensaver.start"] : ["screensaver.start", "cycle.start"];
        // Input ends the screensaver by itself, and the cycle's end
        // dismisses it as well; outside a cycle only a monitor removed
        // while idle takes it down.
        return st.removed && !st.cycle ? ["screensaver.dismiss"] : [];
    case "presence":
        // Only input ends the cycle. The presence monitor also goes away
        // when the cycle ends without input (the screensaver monitor
        // removed) and when the plugin unloads; neither is someone back.
        return isIdle || st.removed ? [] : ["cycle.end"];
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

// The end of a screensaver cycle: someone is back (input: the presence
// monitor saw it), or the screensaver monitor went away (idle-off,
// screensaver-off, the role gone, a plug event that drops it). The monitors'
// own non-idle edges were dropped during the cycle, so this does what they
// would have. Only input wakes the displays the service turned off: without
// it nobody is there, and a dpms monitor removed while idle (Stay Awake)
// turns them on through its own removal. state: { dpmsOff, input }.
function cycleEnd(state) {
    const st = state || {};
    return st.dpmsOff && st.input ? ["screensaver.dismiss", "dpms.on"] : ["screensaver.dismiss"];
}

// One key per monitor to run, "name:seconds:respect" (respect 1 or 0), so a
// model of plain strings recreates exactly the monitors whose parameters
// changed. Suspend always honours idle inhibitors, whatever
// respectInhibitors says: the machine never sleeps under a playing video.
//
// cycle: the timeouts in force when a screensaver cycle started (plan 140),
// or null outside one; true stands for t itself. A cycle runs from the
// screensaver monitor going idle until someone is back. Hyprland restarts
// every inhibitor-aware count when the screensaver's window maps, and again
// when it closes for the lock, so the lock and dpms monitors still counting
// are replaced by input-only ones for the time left (lock - screensaver,
// dpms - screensaver, at least 1 s): they fire at lockAfter and dpmsAfter
// as configured, and only input restarts them. The time left comes from the
// cycle's timeouts, not the current ones, so a settings change or a plug
// event during the cycle leaves those keys, and their counts, alone; one
// that turns a monitor off still removes it, and one turned on during the
// cycle counts its full time on input only. A playing video that starts
// during the screensaver does not hold them off; one playing before keeps
// the screensaver from starting at all. An input-only "presence" monitor of
// 1 s sees the person come back. A monitor already past the screensaver
// (dpms before it) keeps its key. Suspend keeps its key and honours
// inhibitors: its count restarts at those window changes, the last one when
// the screensaver closes for the lock, so it comes up to lockAfter late.
function monitors(t, respectInhibitors, cycle) {
    const out = [];
    const c = cycle === true ? t : cycle;
    const inCycle = !!(t && c && t.screensaver > 0 && c.screensaver > 0);
    for (const name of ["screensaver", "lock", "dpms", "suspend"]) {
        if (!(t && t[name] > 0))
            continue;
        const counting = inCycle && (name === "lock" || name === "dpms") && !(c[name] > 0 && c[name] < c.screensaver);
        if (counting)
            out.push(name + ":" + (c[name] > 0 ? Math.max(1, c[name] - c.screensaver) : t[name]) + ":0");
        else
            out.push(name + ":" + t[name] + ":" + (respectInhibitors || name === "suspend" ? 1 : 0));
    }
    if (inCycle)
        out.push("presence:1:0");
    return out;
}

function parseMonitor(key) {
    const p = String(key).split(":");
    return { name: p[0], timeout: Number(p[1]) || 1, respectInhibitors: p[2] !== "0" };
}

// A monitor going away while idle undoes its idle state (dpms.on,
// screensaver.dismiss) only when it is removed (idle-off, Stay Awake, set
// to 0). When another key of the same name replaces it (a plug event or a
// settings change gave it a new timeout), the person is still away: lighting
// the displays or dropping the screensaver then would be the opposite of
// what they configured. keys: the monitors now wanted (monitors()).
function replaced(key, keys) {
    const name = parseMonitor(key).name;
    return (keys || []).some(k => k !== key && parseMonitor(k).name === name);
}

if (typeof module !== "undefined")
    module.exports = { MAX_SECONDS: MAX_SECONDS, seconds: seconds, effective: effective, timeouts: timeouts, actions: actions, cycleEnd: cycleEnd, monitors: monitors, parseMonitor: parseMonitor, replaced: replaced };
