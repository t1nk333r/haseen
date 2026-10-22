.import "Model.js" as Model

// BatteryLogic.js: the pure decisions of the haseen.battery service
// (plan 075): low and critical warnings and the critical action's
// countdown. No QML or Quickshell types here, so tests/test-battery.sh runs
// it under the real Qt JS engine with plain objects.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

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

// cancelled: the countdown was called off (Cancel, or a charger came) or
// could not be offered (its notification was not shown). acted: the action
// ran. Either way this crossing's countdown is spent: it does not come back
// until the charge recovers. low: the charge at the last discharging reading
// (-1: none yet).
function initial() {
    return { warned: false, critical: false, armed: false, cancelled: false, acted: false, deadline: 0, low: -1 };
}

function copy(state) {
    return Object.assign(initial(), state || {});
}

// The next state and the events one reading causes:
//   "warn"     notify once: the charge reached warnAt while discharging
//   "critical" notify once (urgency critical): it reached criticalAt
//   "arm"      start the countdown (with "critical", when an action is set;
//              alone when the action was turned on below criticalAt and
//              this crossing's countdown is not spent)
//   "disarm"   stop the countdown: a charger came, the charge recovered,
//              the battery went away or criticalAction became none
// One critical notification per crossing: a countdown that was cancelled,
// called off by a charger or not shown, or whose action ran, stays spent
// until the level resets. A charger resets both levels once the charge has
// risen on it (above `low`): a charger that comes and goes without charging
// (a loose cable) neither repeats the notifications nor brings a countdown
// back. Without a charger a level resets once the charge is HYSTERESIS
// points above it (a recalibrated reading, a swapped battery). Unknown and
// no battery change nothing else (no battery also disarms). Reaching both
// levels in one reading (a start at 5%) notifies once, as critical.
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
        if (next.low < 0 || r.percent > next.low) {
            disarm();
            return { state: initial(), events: events };
        }
        // Called off, and it stays called off: coming back would take a
        // second Cancel notification for the same crossing.
        if (next.armed)
            next.cancelled = true;
        disarm();
        return { state: next, events: events };
    }
    if (r.power !== "discharging")
        return { state: next, events: events };
    next.low = r.percent;

    if (next.critical && r.percent >= cfg.criticalAt + HYSTERESIS) {
        disarm();
        next.critical = false;
        next.cancelled = false;
        next.acted = false;
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
    } else if (next.critical && action && !next.armed && !next.cancelled && !next.acted && r.percent <= cfg.criticalAt) {
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
// A charger, Cancel or a missing battery leaves nothing to run. Running
// spends the countdown (acted): the next reading below criticalAt, after a
// resume, does not start another one.
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
    next.acted = true;
    next.deadline = 0;
    return { run: true, rearm: false, retry: false, verb: verb, state: next };
}

// The command the action runs, relative to haseen's bin directory.
function actionCommand(binDir, verb) {
    return verb ? [binDir + "/haseen-system", verb] : [];
}

// The countdown sentence for an action, %1 the seconds left.
function actionSentence(action) {
    return {
        suspend: N_("Suspending in %1 s: plug in or press Cancel."),
        hibernate: N_("Hibernating in %1 s: plug in or press Cancel."),
        poweroff: N_("Shutting down in %1 s: plug in or press Cancel.")
    }[action] || "";
}

// The notification for one event: { summary, body, urgency }; null for
// events that notify nothing. info: { percent, timeToEmpty (s) }. tr: the
// service passes I18n.tr for the interface's language; English without it.
// The body is one or two whole sentences, each translated on its own.
function message(event, info, cfg, tr) {
    const t = Model.translator(tr);
    const i = info || {};
    const left = Model.duration(i.timeToEmpty, tr);
    const level = left ? t(N_("%1% left, about %2."), i.percent || 0, left) : t(N_("%1% left."), i.percent || 0);
    switch (event) {
    case "warn":
        return { summary: t(N_("Battery low")), body: level, urgency: "normal" };
    case "critical":
        if (cfg.criticalAction !== "none")
            return {
                summary: t(N_("Battery critical")),
                body: level + " " + t(actionSentence(cfg.criticalAction), cfg.countdown),
                urgency: "critical"
            };
        return { summary: t(N_("Battery critical")), body: level + " " + t(N_("Plug in now.")), urgency: "critical" };
    case "disarm": {
        const body = {
            suspend: N_("The suspend is called off."),
            hibernate: N_("The hibernation is called off."),
            poweroff: N_("The shutdown is called off.")
        }[cfg.criticalAction];
        return body ? { summary: t(N_("Battery")), body: t(body), urgency: "low" } : null;
    }
    default:
        return null;
    }
}
