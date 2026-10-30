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

// The limits of one account, or of a record, as a detail line: each window's
// percent, then the status the collector gave.
function limitsLine(limits, status, t) {
    const parts = (Array.isArray(limits) ? limits : []).filter(l => l && typeof l.percent === "number").map(l => String(l.label || l.title || t.tr(N_("limit"))) + " " + Math.round(l.percent * 100) + "%");
    const text = String(status || "");
    return parts.concat(text === "" ? [] : [text]);
}

// One usage record (omarchy-agent-usage-update writes them) as the line the
// usage section draws, or null when the record says nothing yet. A record
// that lists several accounts (plan 146: the Claude collector probes each)
// draws one line per account instead, the one in use first; numbers kept
// past a failed check say how old they are. `nowMs` defaults to the clock.
function usage(text, tx, nowMs) {
    const t = tx || ENGLISH;
    let r;
    try {
        r = JSON.parse(String(text || ""));
    } catch (e) {
        return null;
    }
    if (!r || typeof r !== "object")
        return null;
    const name = String(r.name || r.id || "");
    const list = Array.isArray(r.accounts) ? r.accounts.filter(a => a && typeof a === "object" && String(a.id || "") !== "") : [];
    if (list.length >= 2) {
        const now = typeof nowMs === "number" ? nowMs : Date.now();
        const ordered = list.filter(a => a.active === true).concat(list.filter(a => a.active !== true));
        return {
            name: name,
            detail: "",
            accounts: ordered.map(a => {
                const parts = limitsLine(a.limits, a.usageStatusText, t);
                const fetched = Number(a.fetchedAt) || 0;
                if (a.stale === true && fetched > 0)
                    parts.push(t.tr(N_("checked %1 ago"), duration((now - fetched) / 1000, t)));
                return {
                    label: String(a.label || a.id),
                    active: a.active === true,
                    detail: parts.length > 0 ? parts.join(" · ") : t.tr(N_("Not checked yet"))
                };
            })
        };
    }
    // Both are facts about the same account ("1.5k requests · 9.4M tokens ·
    // $4.75" beside its fullest quota windows), so neither hides the other;
    // the row elides what does not fit.
    const detail = limitsLine(r.limits, r.usageStatusText, t).join(" · ");
    if (detail === "")
        return null;
    const account = r.account && r.account.label ? String(r.account.label) : "";
    return {
        name: name + (account !== "" ? " · " + account : ""),
        detail: detail,
        accounts: []
    };
}

// The providers an account can be added for, in the CLI's order.
const PROVIDERS = [["claude", "Claude"], ["codex", "Codex"], ["grok", "Grok"]];

// section(rows) — the accounts section's rows (plan 146): each listed
// provider's accounts, then a row that adds one more; with none listed, an
// add row per provider, so a first sign-in is one click too. A row is an
// account row from accounts() with kind "account", or {kind: "add",
// provider, name}.
function section(rows) {
    const list = Array.isArray(rows) ? rows : [];
    const out = [];
    const seen = [];
    for (const row of list) {
        if (seen.indexOf(row.provider) < 0)
            seen.push(row.provider);
    }
    if (seen.length === 0)
        return PROVIDERS.map(p => ({kind: "add", provider: p[0], name: p[1]}));
    for (const provider of seen) {
        let name = provider;
        for (const row of list) {
            if (row.provider !== provider)
                continue;
            name = row.name;
            out.push(Object.assign({kind: "account"}, row));
        }
        out.push({kind: "add", provider: provider, name: name});
    }
    return out;
}

// addCommand(cli, provider) — the CLI's own add in haseen's floating
// terminal, as the launcher's add row runs it (plan 132): the name prompt
// and the browser hand-off are the CLI's.
function addCommand(cli, provider) {
    return [String(cli), "config", "terminal", "--", String(cli), "agent", "account", "add", String(provider)];
}

// renameCommand(cli, row, name) — the rename a typed name asks for, or []
// when it asks for nothing (blank, or the label it already has).
function renameCommand(cli, row, name) {
    const label = String(name || "").trim();
    if (!row || label === "" || label === String(row.label || ""))
        return [];
    return [String(cli), "agent", "account", "rename", String(row.provider), String(row.id), label];
}
