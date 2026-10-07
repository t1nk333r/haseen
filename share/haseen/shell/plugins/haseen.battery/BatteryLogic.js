.import "Model.js" as Model

// BatteryLogic.js: the pure decisions of the haseen.battery service
// (plan 075): low and critical warnings and the critical action's
// countdown. No QML or Quickshell types here, so tests/test-battery.sh runs
// it under the real Qt JS engine with plain objects.

// Seconds between the critical notification and the critical action.
const COUNTDOWN_SECONDS = 60;
// A threshold re-arms once the charge climbs this many points above it
// without a charger (a recalibrated reading, a swapped battery), so a reading
// that wobbles around the threshold never warns twice.
const HYSTERESIS = 3;
// The countdown's timer firing later than this after its deadline means the
// machine slept through it: the old notification no longer counts.
const LATE_MS = 30000;
// How soon a countdown that ended on an Unknown power state looks again.
const RETRY_MS = 2000;
// What each criticalAction runs: `haseen system <verb>`.
const ACTION_VERBS = { suspend: "suspend", hibernate: "hibernate", poweroff: "shutdown" };

function whole(v, fallback, lo, hi) {
    if (typeof v !== "number" || !isFinite(v))
        return fallback;
    return Math.max(lo, Math.min(hi, Math.round(v)));
}

// The settings in force: warnAt 1-100 (default 20), criticalAt 0-warnAt
// (default 10; 0 turns the critical level off), criticalAction none (the
// default, also for anything unknown), suspend, hibernate or poweroff.
function config(settings) {
    const s = settings || {};
    const warnAt = whole(s.warnAt, 20, 1, 100);
    const criticalAt = Math.min(whole(s.criticalAt, 10, 0, 100), warnAt);
    const action = Object.prototype.hasOwnProperty.call(ACTION_VERBS, s.criticalAction) ? s.criticalAction : "none";
    return { warnAt: warnAt, criticalAt: criticalAt, criticalAction: action, countdown: COUNTDOWN_SECONDS };
}

// Charging, Fully charged and Plugged-in-not-charging count as charging;
// Discharging, Empty and Pending discharge as discharging. Unknown is "no
// news": UPower reports it briefly around plug events.
function power(state) {
    if (Model.isCharging(state))
        return "charging";
    const k = Model.stateKey(state);
    return k === "discharging" || k === "empty" || k === "pending-discharge" ? "discharging" : "unknown";
}

// One reading of the display device: { present, percent (0-100), power }.
// device: { ready, isLaptopBattery, isPresent, percentage (0-1), state }.
function reading(device) {
    const d = device || null;
    const present = d !== null && d.ready === true && d.isLaptopBattery === true && d.isPresent === true;
    return {
        present: present,
        percent: present ? Math.round((Number(d.percentage) || 0) * 100) : 0,
        power: present ? power(d.state) : "unknown"
    };
}

// cancelled: the countdown was called off (Cancel) or could not be offered
// (its notification was not shown); it does not come back until the charge
// recovers. low: the charge at the last discharging reading (-1: none yet).
function initial() {
    return { warned: false, critical: false, armed: false, cancelled: false, deadline: 0, low: -1 };
}

function copy(state) {
    return Object.assign(initial(), state || {});
}

// The next state and the events one reading causes:
//   "warn"     notify once: the charge reached warnAt while discharging
//   "critical" notify once (urgency critical): it reached criticalAt
//   "arm"      start the countdown (with "critical", when an action is set;
//              alone when back on battery below criticalAt, or the action
//              was turned on there, and it was not cancelled)
//   "disarm"   stop the countdown: a charger came, the charge recovered,
//              the battery went away or criticalAction became none
// A charger resets both levels and a Cancel once the charge has risen on it
// (above `low`): a charger that comes and goes without charging (a loose
// cable) neither repeats the notifications nor forgets a Cancel. Without a
// charger a level resets once the charge is HYSTERESIS points above it (a
// recalibrated reading, a swapped battery). Unknown and no battery change
// nothing else (no battery also disarms). Reaching both levels in one
// reading (a start at 5%) notifies once, as critical.
function step(state, r, cfg, nowMs) {
    const next = copy(state);
    const events = [];
    const disarm = () => {
        if (next.armed)
            events.push("disarm");
        next.armed = false;
        next.deadline = 0;
    };
    const arm = () => {
        next.armed = true;
        next.deadline = nowMs + cfg.countdown * 1000;
        events.push("arm");
    };
    if (!r || !r.present) {
        disarm();
        return { state: next, events: events };
    }
    if (cfg.criticalAction === "none")
        disarm();
    if (r.power === "charging") {
        disarm();
        if (next.low < 0 || r.percent > next.low)
            return { state: initial(), events: events };
        return { state: next, events: events };
    }
    if (r.power !== "discharging")
        return { state: next, events: events };
    next.low = r.percent;

    if (next.critical && r.percent >= cfg.criticalAt + HYSTERESIS) {
        disarm();
        next.critical = false;
        next.cancelled = false;
    }
    if (next.warned && !next.critical && r.percent >= cfg.warnAt + HYSTERESIS)
        next.warned = false;

    const action = cfg.criticalAction !== "none";
    if (!next.critical && cfg.criticalAt > 0 && r.percent <= cfg.criticalAt) {
        next.critical = true;
        next.warned = true;
        events.push("critical");
        if (action)
            arm();
    } else if (next.critical && action && !next.armed && !next.cancelled && r.percent <= cfg.criticalAt) {
        arm();
    } else if (!next.warned && r.percent <= cfg.warnAt) {
        next.warned = true;
        events.push("warn");
    }
    return { state: next, events: events };
}

// The user pressed Cancel on the countdown notification, or the
// notification could not be shown at all (no Cancel to offer, so no action:
// fail closed). The critical level stays reached and the countdown does not
// come back, not even after a charger comes and goes, until the charge has
// risen on a charger or climbed HYSTERESIS points above criticalAt.
function cancel(state) {
    const next = copy(state);
    next.armed = false;
    next.cancelled = true;
    next.deadline = 0;
    return next;
}

// The countdown notification is on screen: the countdown it announces runs
// from now (a slow notification server does not shorten it).
function shown(state, cfg, nowMs) {
    const next = copy(state);
    if (next.armed)
        next.deadline = nowMs + cfg.countdown * 1000;
    return next;
}

// Whole seconds left on the countdown (0 when not armed).
function remaining(state, nowMs) {
    if (!state || !state.armed)
        return 0;
    return Math.max(0, Math.ceil((state.deadline - nowMs) / 1000));
}

// The countdown timer fired. { run, rearm, retry, verb, state }:
//   run   execute `haseen system <verb>` now: armed, at the deadline, and
//         UPower says discharging;
//   rearm the deadline passed long ago (the machine slept through it), so a
//         fresh notification and countdown start instead of acting at once;
//   retry UPower's state is Unknown (it is, briefly, around plug events):
//         look again in `delay` ms (RETRY_MS) rather than act on no news.
// A charger, Cancel or a missing battery leaves nothing to run.
function fire(state, r, cfg, nowMs) {
    const next = copy(state);
    const verb = ACTION_VERBS[cfg.criticalAction] || "";
    const none = { run: false, rearm: false, retry: false, verb: "", state: next };
    if (!next.armed || verb === "" || !r || !r.present || r.power === "charging")
        return none;
    if (nowMs + 1000 < next.deadline)
        return none;
    if (nowMs - next.deadline > LATE_MS) {
        next.deadline = nowMs + cfg.countdown * 1000;
        return { run: false, rearm: true, retry: false, verb: "", state: next };
    }
    if (r.power !== "discharging")
        return { run: false, rearm: false, retry: true, delay: RETRY_MS, verb: "", state: next };
    next.armed = false;
    next.deadline = 0;
    return { run: true, rearm: false, retry: false, verb: verb, state: next };
}

// The command the action runs, relative to haseen's bin directory.
function actionCommand(binDir, verb) {
    return verb ? [binDir + "/haseen-system", verb] : [];
}

function actionNoun(action) {
    return { suspend: "Suspending", hibernate: "Hibernating", poweroff: "Shutting down" }[action] || "";
}

// The notification for one event: { summary, body, urgency }; null for
// events that notify nothing. info: { percent, timeToEmpty (s) }.
function message(event, info, cfg) {
    const i = info || {};
    const left = Model.duration(i.timeToEmpty);
    const level = (i.percent || 0) + "% left" + (left ? ", about " + left : "");
    switch (event) {
    case "warn":
        return { summary: "Battery low", body: level + ".", urgency: "normal" };
    case "critical":
        if (cfg.criticalAction !== "none")
            return {
                summary: "Battery critical",
                body: level + ". " + actionNoun(cfg.criticalAction) + " in " + cfg.countdown + " s: plug in or press Cancel.",
                urgency: "critical"
            };
        return { summary: "Battery critical", body: level + ". Plug in now.", urgency: "critical" };
    case "disarm": {
        const name = { suspend: "suspend", hibernate: "hibernation", poweroff: "shutdown" }[cfg.criticalAction];
        return name ? { summary: "Battery", body: "The " + name + " is called off.", urgency: "low" } : null;
    }
    default:
        return null;
    }
}
