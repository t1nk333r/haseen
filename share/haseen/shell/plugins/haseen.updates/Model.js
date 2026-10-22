// haseen.updates (plan 095): pure helpers over `haseen update check`'s JSON,
// shared by the bar widget and the panel. Adapted from the owner's
// t1nk33r.updates widget (BarWidget.qml, MIT, Copyright (c) t1nk33r).

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// The check's answer, with every field forced to its type: a missing or
// unparsable answer becomes one error instead of a silent zero.
function parse(text) {
    let raw;
    try {
        raw = JSON.parse(String(text || ""));
    } catch (e) {
        raw = null;
    }
    if (raw === null || typeof raw !== "object" || Array.isArray(raw))
        return { repo: 0, aur: 0, lines: [], errors: [N_("haseen update check gave no JSON")] };
    const count = v => Number.isInteger(v) && v > 0 ? v : 0;
    const strings = v => Array.isArray(v) ? v.filter(s => typeof s === "string") : [];
    return { repo: count(raw.repo), aur: count(raw.aur), lines: strings(raw.lines), errors: strings(raw.errors) };
}

function total(state) {
    return state ? state.repo + state.aur : 0;
}

// The bar's number: "12", or "12+3" with splitAur while AUR updates wait;
// empty with nothing pending.
function countLabel(state, splitAur) {
    const n = total(state);
    if (n === 0)
        return "";
    return splitAur && state.aur > 0 ? state.repo + "+" + state.aur : String(n);
}

// The widget takes room while something is pending, a check failed (so an
// understated count is never mistaken for the truth) or alwaysShow is on.
function shown(state, alwaysShow) {
    return total(state) > 0 || (state !== null && state.errors.length > 0) || alwaysShow === true;
}

// The panel's heading line. The panel shows the counted line with I18n.tn
// itself (plan 109).
function summary(state, checking) {
    if (state === null)
        return checking ? N_("Checking for updates…") : N_("Not checked yet");
    const n = total(state);
    if (n === 0)
        return state.errors.length > 0 ? N_("Check incomplete") : N_("System up to date");
    return n + (n === 1 ? " update" : " updates") + " · repo " + state.repo + " · AUR " + state.aur;
}

// At most `limit` package lines, then one line for the rest. tr: I18n.tr
// for the interface's language; English without it.
function listed(state, limit, tr) {
    const lines = state ? state.lines : [];
    const n = Math.max(0, Math.floor(Number(limit) || 0));
    if (lines.length <= n)
        return lines.slice();
    const rest = N_("… and %1 more");
    const more = typeof tr === "function" ? tr(rest, lines.length - n) : rest.replace("%1", String(lines.length - n));
    return lines.slice(0, n).concat([more]);
}

// Minutes between checks: the setting, never below 2 (a mistyped setting
// must not turn a network fetch into a busy loop).
function intervalMinutes(value) {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) && n >= 2 ? Math.min(n, 1440) : n > 0 ? 2 : 30;
}
