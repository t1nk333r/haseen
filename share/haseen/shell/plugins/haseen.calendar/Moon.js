.pragma library

// Moon phase for the calendar panel, from the owner's waybar clock module
// (waydots .config/waybar/scripts/clock-moon.sh, retired in waydots 780cc23):
// the mean synodic age from a reference new moon (JD 2451550.1, 2000-01-06)
// with the synodic month S = 29.53058867 days; illumination is
// (1 - cos(2π·phase)) / 2. Accurate to about a day, which is right for a
// calendar line and wrong for an ephemeris. Emoji are northern-hemisphere.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// %1..%9 filled from the further arguments: the English stand-in for
// I18n.tr, which the panel passes to lines() for its language.
function fill(text, ...args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => {
        const value = args[Number(digit) - 1];
        return value === undefined || value === null ? whole : String(value);
    });
}

const SYNODIC = 29.53058867;
const REFERENCE_NEW_MOON_JD = 2451550.1;

const PHASES = [
    { until: 0.0625, emoji: "🌑", name: N_("New Moon") },
    { until: 0.1875, emoji: "🌒", name: N_("Waxing Crescent") },
    { until: 0.3125, emoji: "🌓", name: N_("First Quarter") },
    { until: 0.4375, emoji: "🌔", name: N_("Waxing Gibbous") },
    { until: 0.5625, emoji: "🌕", name: N_("Full Moon") },
    { until: 0.6875, emoji: "🌖", name: N_("Waning Gibbous") },
    { until: 0.8125, emoji: "🌗", name: N_("Last Quarter") },
    { until: 0.9375, emoji: "🌘", name: N_("Waning Crescent") },
    { until: 1.0001, emoji: "🌑", name: N_("New Moon") }
];

// phase(ms) -> {fraction, emoji, name, illumination (0-100), age (days)}.
function phase(ms) {
    const jd = ms / 86400000 + 2440587.5;
    let f = (jd - REFERENCE_NEW_MOON_JD) / SYNODIC;
    f = f - Math.floor(f);
    const entry = PHASES.find(p => f < p.until);
    return {
        fraction: f,
        emoji: entry.emoji,
        name: entry.name,
        illumination: Math.round((1 - Math.cos(2 * Math.PI * f)) / 2 * 100),
        age: Math.round(f * SYNODIC * 10) / 10
    };
}

// The two lines the waybar tooltip showed under the date. tr: I18n.tr for
// the interface's language; English without it.
function lines(ms, tr) {
    const t = typeof tr === "function" ? tr : fill;
    const p = phase(ms);
    return {
        title: p.emoji + "  " + t(p.name),
        detail: t(N_("%1% lit · %2 days old"), p.illumination, p.age.toFixed(1))
    };
}
