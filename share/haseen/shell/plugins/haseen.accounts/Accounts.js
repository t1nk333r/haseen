// Agent accounts in the launcher for haseen.accounts (plan 132): the three
// `haseen agent account` calls the owner types in a terminal — add, use,
// list — as rows found by typing the words they mean (no prefix).
//
// `haseen agent account list --json` (plan 108) is the one source of what
// exists. It prints display fields only; nothing here reads a credential,
// and a row carries what the CLI printed. Pure functions, so
// tests/test-launcher-providers.sh runs them in the Qt JS engine.
//
// The provider runs the list once per open of the launcher; this file starts
// nothing.
.pragma library

// Interface strings stay English here and are translated where QML shows
// them: the provider passes I18n's tr as `tx` ({tr}); without it the text is
// English. N_ marks a string for tools/i18n.py (plan 109).
function N_(text) { return text; }

// %1..%9 replaced by args, in one pass.
function fill(text, args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => args[digit - 1] === undefined ? whole : String(args[digit - 1]));
}

const ENGLISH = {
    tr: (text, ...args) => fill(text, args)
};

const NAMES = {
    claude: "Claude",
    codex: "Codex",
    grok: "Grok"
};
// The menu's own glyphs for the three agents (default/menu.jsonc
// setup.default.agent.*).
const GLYPHS = {
    claude: "\uf06c4",
    codex: "\uf06a9",
    grok: "\uf06a9"
};
// An add row for each provider the CLI keeps accounts for, in its order, so
// a first sign-in is one Enter whether or not anything is signed in.
const PROVIDERS = ["claude", "codex", "grok"];

// parse(text) — the CLI's --json as its list of providers; [] for anything
// else (a run that failed prints nothing, and the add rows still stand).
function parse(text) {
    let data;
    try {
        data = JSON.parse(String(text || "[]"));
    } catch (e) {
        return [];
    }
    return Array.isArray(data) ? data.filter(p => p && typeof p === "object") : [];
}

// entries(list) — one entry per account a switch could mean: the accounts of
// a provider with a login or with more than one account (the agents panel's
// rule, plan 108), the one in use first. `main` is the login the CLI already
// has in ~/.claude, ~/.codex or ~/.grok.
function entries(list) {
    const out = [];
    for (const p of Array.isArray(list) ? list : []) {
        const provider = String((p && p.provider) || "");
        const accounts = (p && Array.isArray(p.accounts) ? p.accounts : []).filter(a => a && String(a.id || "") !== "");
        if (!accounts.some(a => a.signedIn === true) && accounts.length < 2)
            continue;
        // In use first; the rest keep the CLI's order.
        const ordered = accounts.slice().sort((a, b) => (b.active === true) - (a.active === true));
        for (const a of ordered) {
            out.push({
                provider: provider,
                name: String(p.name || NAMES[provider] || provider),
                id: String(a.id),
                label: String(a.label || a.id),
                plan: String(a.plan || ""),
                email: String(a.email || ""),
                active: a.active === true,
                signedIn: a.signedIn === true
            });
        }
    }
    return out;
}

// rows(list, text) — the launcher's rows for a query: the accounts, an add
// row per provider and the list, keeping the rows whose title or detail line
// holds every word. An empty query gives none: the launcher at rest stays the
// menu's ten app rows (plan 122). A row is {kind, provider, id, title,
// subtitle, glyph}; command() turns `kind` into argv.
function rows(list, text, tx) {
    const t = tx || ENGLISH;
    const q = String(text || "").trim().toLowerCase();
    if (q === "")
        return [];
    const words = q.split(/\s+/);
    const out = [];
    for (const a of entries(list)) {
        const state = a.active ? t.tr(N_("in use")) : (a.signedIn ? t.tr(N_("signed in")) : t.tr(N_("signed out")));
        out.push({
            kind: "use",
            provider: a.provider,
            id: a.id,
            title: a.label,
            subtitle: [t.tr(N_("%1 account"), a.name), a.email, a.plan, state].filter(s => s !== "").join("  ·  "),
            glyph: GLYPHS[a.provider] || GLYPHS.claude
        });
    }
    for (const p of PROVIDERS) {
        out.push({
            kind: "add",
            provider: p,
            id: "",
            title: t.tr(N_("Add a %1 account…"), NAMES[p]),
            subtitle: t.tr(N_("sign in through a browser, in a home of its own")),
            glyph: GLYPHS[p]
        });
    }
    out.push({
        kind: "list",
        provider: "",
        id: "",
        title: t.tr(N_("Agent accounts")),
        subtitle: t.tr(N_("list them: which account new sessions use; running ones stay")),
        glyph: GLYPHS.claude
    });
    return out.filter(r => words.every(w => (r.title + " " + r.subtitle).toLowerCase().indexOf(w) >= 0));
}

// command(row) — the haseen argv after the binary: the CLI's own verb, so a
// launcher row and a typed command do exactly the same thing.
function command(row) {
    switch (row && row.kind) {
    case "use":
        return ["agent", "account", "use", String(row.provider), String(row.id)];
    case "add":
        return ["agent", "account", "add", String(row.provider)];
    case "list":
        return ["agent", "account", "list"];
    }
    return [];
}
