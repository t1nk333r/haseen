// Window switcher model for haseen.windows (plan 081): ranking of open
// windows and the focus argv. Pure functions over plain objects
// ({ address, title, wmClass, workspace, focus }), so
// tests/test-launcher-providers.sh runs them in the Qt JS engine without a
// Hyprland.
.pragma library
.import "../haseen.launcher/Fuzzy.js" as Fuzzy

// Hyprland window addresses are hex. Anything else never reaches hyprctl:
// the address ends up inside a Lua string in a Lua session.
function validAddress(address) {
    return /^0x[0-9a-fA-F]+$/.test(String(address || ""));
}

// Quickshell's HyprlandToplevel.address comes without the 0x that
// lastIpcObject.address and hyprctl use.
function normalAddress(address) {
    const a = String(address || "");
    if (a === "")
        return "";
    return a.indexOf("0x") === 0 ? a : "0x" + a;
}

// Empty query: every window, most recently focused first. Otherwise the
// launcher's fuzzy score over the title, the class (×0.9) and the workspace
// name (×0.5); ties go to the more recently focused window, then the title.
function rank(windows, query) {
    const q = String(query || "").trim().toLowerCase();
    const scored = [];
    const list = Array.isArray(windows) ? windows : [];
    for (let i = 0; i < list.length; i++) {
        const w = list[i];
        if (!w || !validAddress(w.address))
            continue;
        let s = 0;
        if (q !== "") {
            s = Fuzzy.score(q, String(w.title || "").toLowerCase());
            const c = Fuzzy.score(q, String(w.wmClass || "").toLowerCase());
            if (c >= 0)
                s = Math.max(s, Math.round(c * 0.9));
            const ws = Fuzzy.score(q, String(w.workspace || "").toLowerCase());
            if (ws >= 0)
                s = Math.max(s, Math.round(ws * 0.5));
            if (s < 0)
                continue;
        }
        scored.push({
            w: w,
            s: s
        });
    }
    scored.sort((a, b) => b.s - a.s || focusOrder(a.w) - focusOrder(b.w) || String(a.w.title || "").localeCompare(String(b.w.title || "")));
    return scored.map(x => x.w);
}

function focusOrder(w) {
    const f = Number(w.focus);
    return isFinite(f) && f >= 0 ? f : 9999;
}

// "<class> · workspace <name>"
function subtitle(w) {
    const parts = [];
    if (w.wmClass)
        parts.push(String(w.wmClass));
    if (w.workspace !== undefined && w.workspace !== null && String(w.workspace) !== "")
        parts.push("workspace " + String(w.workspace));
    return parts.join("  ·  ");
}

// The generic icon for a window whose class names no icon.
const GENERIC_ICON = "application-x-executable";

// The icon-theme name to try for a window class with no desktop entry. The
// class is whatever the client set (Wayland app_id, X11 WM_CLASS): the
// launcher loads anything with "://" or a leading "/" as is, so a class like
// "http://host/x.png" or "/tmp/x/y.svg" would make the shell fetch a URL or
// read a file a client chose. Only a plain icon name (letters, digits, . _ -)
// is passed on, and only to the icon theme; anything else gets the generic
// icon.
function themeIcon(wmClass) {
    const name = String(wmClass || "").toLowerCase();
    return /^[a-z0-9][a-z0-9._-]*$/.test(name) ? name : GENERIC_ICON;
}

// hyprctl dispatch focuswindow, in the dispatcher syntax of the running
// Hyprland: a Lua config (haseen's) takes hl.dsp.focus, as haseen.pager
// does; a hyprlang config takes `focuswindow address:…`. [] for a bad
// address.
function focusArgv(address, usingLua) {
    if (!validAddress(address))
        return [];
    if (usingLua)
        return ["hyprctl", "dispatch", 'hl.dsp.focus({window = hl.get_window("address:' + address + '")})'];
    return ["hyprctl", "dispatch", "focuswindow", "address:" + address];
}
