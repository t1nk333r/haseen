.pragma library

// Moon phase for the calendar panel, from the owner's waybar clock module
// (waydots .config/waybar/scripts/clock-moon.sh, retired in waydots 780cc23):
// the mean synodic age from a reference new moon (JD 2451550.1, 2000-01-06)
// with the synodic month S = 29.53058867 days; illumination is
// (1 - cos(2π·phase)) / 2. Accurate to about a day, which is right for a
// calendar line and wrong for an ephemeris. Emoji are northern-hemisphere.

const SYNODIC = 29.53058867;
const REFERENCE_NEW_MOON_JD = 2451550.1;

const PHASES = [
    { until: 0.0625, emoji: "🌑", name: "New Moon" },
    { until: 0.1875, emoji: "🌒", name: "Waxing Crescent" },
    { until: 0.3125, emoji: "🌓", name: "First Quarter" },
    { until: 0.4375, emoji: "🌔", name: "Waxing Gibbous" },
    { until: 0.5625, emoji: "🌕", name: "Full Moon" },
    { until: 0.6875, emoji: "🌖", name: "Waning Gibbous" },
    { until: 0.8125, emoji: "🌗", name: "Last Quarter" },
    { until: 0.9375, emoji: "🌘", name: "Waning Crescent" },
    { until: 1.0001, emoji: "🌑", name: "New Moon" }
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

// The two lines the waybar tooltip showed under the date.
function lines(ms) {
    const p = phase(ms);
    return {
        title: p.emoji + "  " + p.name,
        detail: p.illumination + "% lit · " + p.age.toFixed(1) + " days old"
    };
}
