// Menu commands in the launcher for haseen.commands (plan 081): the leaves
// of haseen.menu's tree (default/menu.jsonc merged with the user overlay by
// MenuModel.js), their order for a query and the argv that runs one. Pure
// functions, so tests/test-launcher-providers.sh runs them in the Qt JS
// engine. MenuModel.js is a `.pragma library`: the menu and this provider
// share one instance per shell, and so its guard answers (memory.guards).
.pragma library
.import "../haseen.menu/MenuModel.js" as Model

// A leaf may run only when every `when` on it and on its submenus has
// answered true, and its `disabled` guard (if any) has answered false. An
// unknown answer hides the row: a guarded command never runs on a guess.
function allowed(items, entry, guards) {
    const w = guards && guards.w ? guards.w : {};
    const d = guards && guards.d ? guards.d : {};
    if (entry.disabled && d[entry.id] !== false)
        return false;
    let current = entry;
    for (let depth = 0; depth < 32; depth++) {
        if (current.when && w[current.id] !== true)
            return false;
        if (current.parent === "root")
            return true;
        current = items[current.parent];
        if (!current)
            return false;
    }
    return false;
}

// [{ id, label, path, action }] in menu order: action leaves a user could
// reach in the menu, with the guards known so far.
function leaves(items, itemOrder, guards) {
    const out = [];
    const c = guards && guards.c ? guards.c : {};
    for (let i = 0; i < itemOrder.length; i++) {
        const entry = items[itemOrder[i]];
        if (!entry || entry.kind !== "action" || !entry.action || !allowed(items, entry, guards))
            continue;
        out.push({
            id: entry.id,
            label: Model.labelFor(entry, c, {}),
            path: Model.parentPathFor(items, entry.id),
            action: entry.action,
            entry: entry
        });
    }
    return out;
}

// Empty query: menu order. Otherwise the menu's own search: every word in
// the label, id or aliases (or a whole word of the description), best
// MenuModel.searchScore first.
function rank(items, rows, query) {
    const q = String(query || "").trim();
    if (q === "")
        return rows.slice();
    return rows.filter(r => Model.matchesQuery(r.entry, q)).map(r => ({
                    r: r,
                    s: Model.searchScore(items, r.entry, q)
                })).sort((a, b) => a.s - b.s).map(x => x.r);
}

// What Enter does with a leaf's action, as the menu runs it: a bare
// `haseen shell ipc panel toggle <id>` toggles that panel in this shell;
// anything else runs in bash with haseen's bin/ first on PATH, started
// through Apps.launch (plan 074).
function command(action, binDir) {
    const panel = Model.panelAction(action);
    if (panel !== "")
        return {
            panel: panel,
            argv: []
        };
    return {
        panel: "",
        argv: ["bash", "-c", "PATH=\"$1:$PATH\"; eval \"$2\"", "bash", String(binDir), String(action)]
    };
}

// New guard answers merged over the cached ones, so answers the menu
// learnt for rows outside this tree (catalog rows) survive.
function mergeGuards(prior, next) {
    const out = {
        w: {},
        c: {},
        d: {}
    };
    for (const k of ["w", "c", "d"]) {
        Object.assign(out[k], prior && prior[k] ? prior[k] : {});
        Object.assign(out[k], next && next[k] ? next[k] : {});
    }
    return out;
}
