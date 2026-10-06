// Indicators.js: the pure decisions of haseen.indicators, kept out of QML so
// tests/test-indicators.sh can run them. No QML or Quickshell types here.
//
// Adapted from Omarchy shell/plugins/bar/widgets/Indicators.qml and
// shell/plugins/bar/indicators/*.qml (MIT, Copyright (c) David Heinemeier
// Hansson): the entry list and its `items` setting, the ids, glyphs and
// tooltips, and the split into an always-shown active block and an inactive
// block revealed on hover. The state comes from haseen's flags instead of
// Omarchy's services.

// Omarchy's Dictation and Reminder entries are not here: haseen has no
// dictation, and its reminders are systemd timers with no watchable state
// (showing them would mean polling systemctl).
const SPECS = {
    ScreenRecording: {
        flag: "recording",
        glyph: "\u{F0EC2}",
        activeTip: "Stop recording",
        inactiveTip: "Screen recording",
        on: ["haseen", "capture", "screenrecord"],
        off: ["haseen", "capture", "screenrecord", "--stop"]
    },
    NightLight: {
        flag: "nightlight",
        glyph: "\u{F050E}",
        activeTip: "Day light",
        inactiveTip: "Night light",
        on: ["haseen", "toggle", "nightlight", "on"],
        off: ["haseen", "toggle", "nightlight", "off"]
    },
    Dnd: {
        flag: "dnd",
        glyph: "\u{F009B}",
        activeTip: "Allow notifications",
        inactiveTip: "Silence notifications",
        on: ["haseen", "toggle", "dnd", "on"],
        off: ["haseen", "toggle", "dnd", "off"]
    },
    StayAwake: {
        flag: "idle-off",
        glyph: "\u{F0176}",
        activeTip: "Allow idle lock & screensaver",
        inactiveTip: "Stay awake",
        // `haseen toggle idle on` allows idle again; the flag means "off".
        on: ["haseen", "toggle", "idle", "off"],
        off: ["haseen", "toggle", "idle", "on"]
    },
    // haseen's own: the screensaver alone held back (the lock still comes).
    Screensaver: {
        flag: "screensaver-off",
        glyph: "\u{F1104}",
        activeTip: "Allow the screensaver",
        inactiveTip: "Hold the screensaver",
        // `haseen toggle screensaver on` allows it; the flag means "off".
        on: ["haseen", "toggle", "screensaver", "off"],
        off: ["haseen", "toggle", "screensaver", "on"]
    }
};

const DEFAULT_ITEMS = ["ScreenRecording", "NightLight", "Dnd", "StayAwake", "Screensaver"];

// A bar widget that already shows the same state, and whose presence in the
// bar makes the entry a duplicate: the pager bell turns into bell-off under
// Do Not Disturb, haseen.idle is the Stay Awake cup, haseen.privacy's red
// dot is the recording.
const SHOWN_BY = {
    Dnd: "haseen.pager",
    StayAwake: "haseen.idle",
    ScreenRecording: "haseen.privacy"
};

function entryId(entry) {
    if (typeof entry === "string")
        return entry;
    if (entry && typeof entry === "object" && entry.id !== undefined && entry.id !== null)
        return String(entry.id);
    return "";
}

// The ids this instance shows, in order: settings.items (Omarchy's key;
// `indicators` is its older name), else all; unknown ids and repeats are
// dropped, as is an entry another widget in the bar (barIds) already shows.
function entries(settings, barIds) {
    const s = settings || {};
    let source = DEFAULT_ITEMS;
    if (Array.isArray(s.items) && s.items.length > 0)
        source = s.items;
    else if (Array.isArray(s.indicators) && s.indicators.length > 0)
        source = s.indicators;
    const bar = Array.isArray(barIds) ? barIds : [];
    const out = [];
    for (let i = 0; i < source.length; i++) {
        const id = entryId(source[i]);
        if (!SPECS[id] || out.indexOf(id) >= 0)
            continue;
        if (SHOWN_BY[id] && bar.indexOf(SHOWN_BY[id]) >= 0)
            continue;
        out.push(id);
    }
    return out;
}

// flags: { "<flag name>": bool }. Returns { active: [...], inactive: [...] }
// in entry order. Omarchy keeps the active block next to the clock (after
// the inactive one in a left-to-right bar).
function split(ids, flags) {
    const f = flags || {};
    const active = [];
    const inactive = [];
    for (let i = 0; i < ids.length; i++) {
        const spec = SPECS[ids[i]];
        if (!spec)
            continue;
        (f[spec.flag] === true ? active : inactive).push(ids[i]);
    }
    return { active: active, inactive: inactive };
}

// What the cell looks like and does: { glyph, tooltip, command }; command is
// the argv a click runs (it turns the state the other way).
function cell(id, active) {
    const spec = SPECS[id];
    if (!spec)
        return null;
    return {
        glyph: spec.glyph,
        tooltip: active ? spec.activeTip : spec.inactiveTip,
        command: (active ? spec.off : spec.on).slice()
    };
}

function flagOf(id) {
    return SPECS[id] ? SPECS[id].flag : "";
}
