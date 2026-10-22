.pragma library

// Row logic for haseen.agents: the TSV agents-list.sh prints turned into the
// lines the panel draws. Pure, so tests run it headless.

// Interface strings stay English here and are translated where QML shows
// them: the panel passes I18n's tr and tn as `tx` ({tr, tn}); without it the
// text is English. N_ and N_n mark the strings for tools/i18n.py (plan 109).
function N_(text) { return text; }
function N_n(singular, plural) { return plural; }

// %1..%9 replaced by args, in one pass.
function fill(text, args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => args[digit - 1] === undefined ? whole : String(args[digit - 1]));
}

const ENGLISH = {
    tr: (text, ...args) => fill(text, args),
    tn: (singular, plural, count, ...args) => fill(count === 1 ? singular : plural, [count].concat(args))
};

// "pid \t name \t seconds \t cwd" per line. Longest-running first, so the
// session that has been working all afternoon is at the top.
function parse(text, home) {
    const rows = [];
    for (const line of String(text || "").split("\n")) {
        if (line.trim() === "")
            continue;
        const parts = line.split("\t");
        const pid = parseInt(parts[0], 10);
        const name = String(parts[1] || "").trim();
        if (!(pid > 0) || name === "")
            continue;
        const seconds = parseInt(parts[2], 10);
        const cwd = String(parts[3] || "").trim();
        rows.push({
            pid: pid,
            name: name,
            seconds: seconds > 0 ? seconds : 0,
            cwd: cwd,
            project: project(cwd),
            where: shorten(cwd, home)
        });
    }
    rows.sort((a, b) => b.seconds - a.seconds || a.pid - b.pid);
    return rows;
}

// The directory the agent works in, which is the project as far as the panel
// is concerned.
function project(cwd) {
    const parts = String(cwd || "").split("/").filter(p => p !== "");
    return parts.length > 0 ? parts[parts.length - 1] : "";
}

function shorten(cwd, home) {
    const path = String(cwd || "");
    const base = String(home || "");
    if (base !== "" && (path === base || path.startsWith(base + "/")))
        return "~" + path.slice(base.length);
    return path;
}

// "45s", "12m", "3h 07m", "2d 4h".
function duration(seconds, tx) {
    const t = tx || ENGLISH;
    const total = Math.max(0, Math.round(Number(seconds) || 0));
    if (total < 60)
        return t.tr(N_("%1s"), total);
    const minutes = Math.floor(total / 60);
    if (minutes < 60)
        return t.tr(N_("%1m"), minutes);
    const hours = Math.floor(minutes / 60);
    if (hours < 24)
        return t.tr(N_("%1h %2m"), hours, ("0" + (minutes % 60)).slice(-2));
    return t.tr(N_("%1d %2h"), Math.floor(hours / 24), hours % 24);
}

// The line under the title: what is running, in how many projects.
function summary(rows, tx) {
    const t = tx || ENGLISH;
    const list = Array.isArray(rows) ? rows : [];
    if (list.length === 0)
        return t.tr(N_("nothing running"));
    const projects = {};
    for (const row of list)
        projects[row.cwd || row.pid] = true;
    const count = Object.keys(projects).length;
    return t.tn("%1 agent", N_n("%1 agent", "%1 agents"), list.length) + " · " + t.tn("%1 project", N_n("%1 project", "%1 projects"), count);
}

// The accounts section (plan 108): `haseen agent account list --json` turned
// into one row per account, for the providers someone is signed in to or
// that have more than one account. Display fields only; the command never
// prints a credential.
function accounts(text) {
    let data = [];
    try {
        data = JSON.parse(String(text || "[]"));
    } catch (e) {
        return [];
    }
    const rows = [];
    for (const p of Array.isArray(data) ? data : []) {
        const list = Array.isArray(p && p.accounts) ? p.accounts : [];
        if (!list.some(a => a && a.signedIn === true) && list.length < 2)
            continue;
        for (const a of list) {
            if (!a || String(a.id || "") === "")
                continue;
            rows.push({
                provider: String(p.provider || ""),
                name: String(p.name || p.provider || ""),
                id: String(a.id),
                label: String(a.label || a.id),
                plan: String(a.plan || ""),
                email: String(a.email || ""),
                active: a.active === true,
                signedIn: a.signedIn === true
            });
        }
    }
    return rows;
}

// One usage record (omarchy-agent-usage-update writes them) as the line the
// usage section draws, or null when the record says nothing yet.
function usage(text, tx) {
    const t = tx || ENGLISH;
    let r;
    try {
        r = JSON.parse(String(text || ""));
    } catch (e) {
        return null;
    }
    if (!r || typeof r !== "object")
        return null;
    const limits = (Array.isArray(r.limits) ? r.limits : []).filter(l => l && typeof l.percent === "number").map(l => String(l.label || l.title || t.tr(N_("limit"))) + " " + Math.round(l.percent * 100) + "%");
    const status = String(r.usageStatusText || "");
    if (limits.length === 0 && status === "")
        return null;
    const account = r.account && r.account.label ? String(r.account.label) : "";
    return {
        name: String(r.name || r.id || "") + (account !== "" ? " · " + account : ""),
        detail: limits.length > 0 ? limits.join(" · ") : status
    };
}
