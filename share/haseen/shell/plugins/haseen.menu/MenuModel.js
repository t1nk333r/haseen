// Menu model for haseen.menu: JSONC parsing, the default+overlay merge,
// routing, visibility, search, the batched guard script and the view's rows.
// Pure functions (syncRows takes any ListModel-shaped object), so
// tests/test-menu.sh runs the same code under node/bun and the Qt JS engine.
//
// Adapted from Omarchy shell/plugins/menu/MenuModel.js (MIT, Copyright (c)
// David Heinemeier Hansson). Changes: haseen guard helpers and readers,
// `hidden` for overlays, `when` hides a row until its guard answers true,
// the catalog row builder, disabled rows, in-place row sync and the memory
// kept across opens, no dmenu/summon paths.
.pragma library

// Full-line `//` comments and trailing commas. A `//` inside a string value
// (an URL in an action) is never at the start of a line, so it survives.
function stripJsonc(raw) {
    return String(raw || "").replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1");
}

function normalizeAliases(value) {
    if (Array.isArray(value))
        return value.filter(function (v) {
            return typeof v === "string" && v;
        });
    if (typeof value === "string" && value)
        return [value];
    return [];
}

// Only the keys the raw entry sets, so an overlay entry that names one field
// (`{"label": "Power"}`) changes that field and inherits the rest.
var FIELDS = ["icon", "label", "title", "target", "description", "action", "provider", "when", "checked", "disabled", "parent"];

function partialItem(id, raw) {
    var out = {
        id: id
    };
    for (var i = 0; i < FIELDS.length; i++) {
        var k = FIELDS[i];
        if (typeof raw[k] === "string")
            out[k] = raw[k];
    }
    if (raw.aliases !== undefined)
        out.aliases = normalizeAliases(raw.aliases);
    if (typeof raw.hidden === "boolean")
        out.hidden = raw.hidden;
    return out;
}

function parseMenuJsonc(raw) {
    var stripped = stripJsonc(raw);
    if (!stripped.trim())
        return [];
    var parsed;
    try {
        parsed = JSON.parse(stripped);
    } catch (e) {
        return null;
    }
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
        return null;
    var source = (parsed.items && typeof parsed.items === "object" && !Array.isArray(parsed.items)) ? parsed.items : parsed;
    var out = [];
    for (var id in source) {
        var entry = source[id];
        if (!entry || typeof entry !== "object" || Array.isArray(entry))
            continue;
        out.push(partialItem(id, entry));
    }
    return out;
}

function finishItem(p) {
    var id = p.id;
    var parent = p.parent;
    if (parent === undefined)
        parent = id.indexOf(".") >= 0 ? id.split(".").slice(0, -1).join(".") : "root";
    if (id === "root")
        parent = "";
    var action = p.action || "";
    var target = p.target || "";
    return {
        id: id,
        parent: parent,
        kind: action ? "action" : (target ? "link" : "menu"),
        icon: p.icon || "",
        label: p.label || id,
        title: p.title || "",
        target: target,
        description: p.description || "",
        action: action,
        provider: p.provider || "",
        aliases: p.aliases || [],
        when: p.when || "",
        checked: p.checked || "",
        disabled: p.disabled || "",
        hidden: p.hidden === true,
        order: 0
    };
}

// Default items, then the overlay merged key by key per item. Overlay-only ids
// append after the defaults, so a user entry lands at the end of its submenu.
function mergeMenuSources(defaultItems, userItems) {
    var partial = {};
    var order = [];
    var sources = [defaultItems || [], userItems || []];
    for (var s = 0; s < sources.length; s++) {
        for (var i = 0; i < sources[s].length; i++) {
            var entry = sources[s][i];
            if (!entry || !entry.id)
                continue;
            if (!partial[entry.id])
                order.push(entry.id);
            var merged = {};
            var prior = partial[entry.id] || {};
            for (var k in prior)
                merged[k] = prior[k];
            for (var k2 in entry)
                merged[k2] = entry[k2];
            partial[entry.id] = merged;
        }
    }
    var items = {};
    var itemOrder = [];
    if (!partial.root) {
        partial.root = {
            id: "root",
            label: "Menu"
        };
        order.unshift("root");
    }
    for (var j = 0; j < order.length; j++) {
        var item = finishItem(partial[order[j]]);
        if (item.hidden)
            continue;
        item.order = itemOrder.length;
        items[item.id] = item;
        itemOrder.push(item.id);
    }
    return {
        items: items,
        itemOrder: itemOrder
    };
}

// Swaps the rows one provider contributed (tagged with providerMenu), leaving
// every other item untouched. Returns fresh objects: QML `var` maps must never
// be written in place (an in-place write can be dropped by the engine).
function swapProviderRows(items, itemOrder, menuId, rows) {
    var nextItems = {};
    var nextOrder = [];
    for (var i = 0; i < itemOrder.length; i++) {
        var existing = items[itemOrder[i]];
        if (!existing || existing.providerMenu === menuId)
            continue;
        nextItems[existing.id] = existing;
        nextOrder.push(existing.id);
    }
    for (var j = 0; j < rows.length; j++) {
        var row = rows[j];
        if (!row || !row.id || nextItems[row.id])
            continue;
        row.providerMenu = menuId;
        row.order = nextOrder.length;
        nextItems[row.id] = row;
        nextOrder.push(row.id);
    }
    return {
        items: nextItems,
        itemOrder: nextOrder
    };
}

function slugify(value) {
    return String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "") || "item";
}

// A provider row: an action leaf under menuId.
function providerRow(menuId, key, fields) {
    var row = finishItem({
        id: menuId + "." + slugify(key),
        parent: menuId,
        label: fields.label,
        icon: fields.icon || "",
        description: fields.description || "",
        action: fields.action || ""
    });
    row.disabledNow = fields.disabledNow === true;
    row.checkedNow = fields.checkedNow === true;
    return row;
}

function shellQuote(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

// Install/Remove from Catalog's share/haseen/default/catalog.json: one submenu
// per category, one row per entry. Install rows of installed entries stay
// listed but disabled (✓); Remove lists installed entries only.
function catalogRows(menuId, catalog, installed, mode) {
    var rows = [];
    if (!catalog || !Array.isArray(catalog.entries))
        return rows;
    var cats = Array.isArray(catalog.categories) ? catalog.categories : [];
    var have = {};
    for (var i = 0; i < installed.length; i++)
        have[installed[i]] = true;
    for (var c = 0; c < cats.length; c++) {
        var cat = cats[c];
        if (!cat || !cat.id)
            continue;
        var catId = menuId + "." + slugify(cat.id);
        var children = [];
        for (var e = 0; e < catalog.entries.length; e++) {
            var entry = catalog.entries[e];
            if (!entry || entry.category !== cat.id || !entry.id)
                continue;
            if (mode === "remove" && !have[entry.id])
                continue;
            var row = providerRow(catId, entry.id, {
                label: entry.label || entry.id,
                icon: entry.icon || cat.icon || "",
                description: entry.description || "",
                action: "haseen " + mode + " app " + shellQuote(entry.id),
                disabledNow: mode === "install" && have[entry.id] === true
            });
            if (entry.when)
                row.when = entry.when;
            children.push(row);
        }
        if (children.length === 0)
            continue;
        var sub = finishItem({
            id: catId,
            parent: menuId,
            label: cat.label || cat.id,
            icon: cat.icon || "",
            title: (mode === "install" ? "Install " : "Remove ") + (cat.label || cat.id)
        });
        rows.push(sub);
        rows = rows.concat(children);
    }
    return rows;
}

function item(items, id) {
    return items && items[id] ? items[id] : null;
}

// An exact id beats any alias; unknown input falls through as the literal id.
function resolveRoute(items, itemOrder, input) {
    var raw = String(input || "").toLowerCase().replace(/_/g, "-").trim();
    if (!raw || raw === "root" || raw === "menu")
        return "root";
    if (item(items, raw))
        return raw;
    for (var i = 0; i < itemOrder.length; i++) {
        var entry = item(items, itemOrder[i]);
        if (!entry || entry.kind === "app")
            continue;
        for (var j = 0; j < entry.aliases.length; j++)
            if (String(entry.aliases[j]).toLowerCase().replace(/_/g, "-") === raw)
                return entry.id;
    }
    return raw;
}

function depthFor(items, id) {
    var depth = 0;
    var current = item(items, id);
    while (current && current.parent && current.parent !== "root" && depth < 32) {
        depth += 1;
        current = item(items, current.parent);
    }
    return depth;
}

function pathFor(items, id) {
    var labels = [];
    var current = item(items, id);
    var guard = 0;
    while (current && current.id !== "root" && guard < 32) {
        labels.unshift(current.label);
        current = item(items, current.parent);
        guard += 1;
    }
    return labels.join(" › ");
}

function parentPathFor(items, id) {
    var entry = item(items, id);
    if (!entry || !entry.parent || entry.parent === "root")
        return "";
    return pathFor(items, entry.parent);
}

function isDescendantOf(items, id, ancestorId) {
    if (ancestorId === "root")
        return id !== "root";
    var current = item(items, id);
    var guard = 0;
    while (current && current.parent && guard < 32) {
        if (current.parent === ancestorId)
            return true;
        current = item(items, current.parent);
        guard += 1;
    }
    return false;
}

// `when` hides a row until its guard has answered true: a "Stop recording"
// row must never flash up while the batch is still running.
function whenAllows(whenResults, entry) {
    return !entry.when || (whenResults && whenResults[entry.id] === true);
}

// A submenu shows when it has a visible child or a provider (which fills it
// on entry). Leaves show when their guard allows.
function isVisible(items, itemOrder, whenResults, entry, depth) {
    if (!entry || !whenAllows(whenResults, entry))
        return false;
    if (entry.kind !== "menu" && entry.kind !== "link")
        return true;
    if (entry.provider)
        return true;
    var guard = depth || 0;
    if (guard >= 32)
        return false;
    var target = entry.kind === "link" ? entry.target : entry.id;
    for (var i = 0; i < itemOrder.length; i++) {
        var child = item(items, itemOrder[i]);
        if (child && child.parent === target && isVisible(items, itemOrder, whenResults, child, guard + 1))
            return true;
    }
    return false;
}

function isDisabled(disabledResults, entry) {
    if (!entry)
        return false;
    if (entry.disabledNow)
        return true;
    return !!(entry.disabled && disabledResults && disabledResults[entry.id]);
}

function isChecked(checkedResults, entry) {
    return !!(entry && (entry.checkedNow || (entry.checked && checkedResults && checkedResults[entry.id])));
}

// A disabled row is software already present: the same ✓ as a checked one.
function labelFor(entry, checkedResults, disabledResults) {
    if (!entry)
        return "";
    return (isChecked(checkedResults, entry) || isDisabled(disabledResults, entry)) ? entry.label + " ✓" : entry.label;
}

function searchableToken(value) {
    return String(value || "").replace(/[._-]+/g, " ");
}

function leafIdFor(id) {
    var parts = String(id || "").split(".");
    return parts[parts.length - 1];
}

function nameSearchText(entry) {
    var aliases = [];
    for (var i = 0; i < entry.aliases.length; i++)
        aliases.push(searchableToken(entry.aliases[i]));
    return [entry.label, searchableToken(leafIdFor(entry.id)), aliases.join(" ")].join(" ").toLowerCase();
}

function termInSearchWords(term, text) {
    return String(text || "").toLowerCase().split(/\s+/).indexOf(term) >= 0;
}

function matchesQuery(entry, query) {
    if (!entry || entry.id === "root")
        return false;
    var nameText = nameSearchText(entry);
    var description = String(entry.description || "").toLowerCase();
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);
    for (var i = 0; i < terms.length; i++) {
        if (!terms[i] || nameText.indexOf(terms[i]) >= 0 || termInSearchWords(terms[i], description))
            continue;
        return false;
    }
    return true;
}

function descriptionTextMatches(query, text) {
    var terms = String(query || "").toLowerCase().trim().split(/\s+/);
    for (var i = 0; i < terms.length; i++) {
        if (terms[i] && !termInSearchWords(terms[i], text))
            return false;
    }
    return true;
}

function searchScore(items, entry, query) {
    var needle = String(query || "").toLowerCase().trim();
    var label = entry.label.toLowerCase();
    var score = 80;
    if (label === needle)
        score = entry.parent === "root" ? 2 : 0;
    // An installed app whose name holds the query as a whole word ("zen" for
    // Zen Browser) beats exact-labelled menu rows like Install › Zen.
    else if (entry.kind === "app" && label.split(/\s+/).indexOf(needle) >= 0)
        score = 0;
    else if (label.indexOf(needle) === 0)
        score = 10;
    else if (label.indexOf(needle) >= 0)
        score = 30;
    else if (nameSearchText(entry).indexOf(needle) >= 0)
        score = 40;
    else if (descriptionTextMatches(needle, String(entry.description || "").toLowerCase()))
        score = 60;
    if (entry.kind === "menu" || entry.kind === "link")
        score -= 2;
    // Apps sort after the menu rows and lose ties to them; outrank those
    // within the tier so a better match still wins.
    if (entry.kind === "app")
        score -= 5;
    return score * 1000 + depthFor(items, entry.id) * 25 + entry.order;
}

function childCount(items, itemOrder, id) {
    var count = 0;
    for (var i = 0; i < itemOrder.length; i++) {
        var entry = item(items, itemOrder[i]);
        if (entry && entry.parent === id)
            count += 1;
    }
    return count;
}

// One row of the view's ListModel. Every role always has the same type, as a
// ListModel requires.
function displayRow(items, itemOrder, checkedResults, disabledResults, entry, detail, section) {
    var target = entry.kind === "link" ? entry.target : entry.id;
    return {
        itemId: entry.id,
        kind: entry.kind,
        icon: entry.icon || "",
        appIcon: entry.appIcon || "",
        appId: entry.appId || "",
        label: labelFor(entry, checkedResults, disabledResults),
        target: target || "",
        detail: detail || "",
        path: pathFor(items, entry.id),
        action: entry.action || "",
        childCount: (entry.kind === "menu" || entry.kind === "link") ? childCount(items, itemOrder, target) : 0,
        disabled: isDisabled(disabledResults, entry),
        section: section || ""
    };
}

function rowIndex(rows, itemId) {
    for (var i = 0; i < rows.length; i++) {
        if (rows[i].itemId === itemId)
            return i;
    }
    return -1;
}

// Where the cursor goes when the rows change under it: onto the row it was
// on (keepId) wherever that row now is, else the same position, clamped.
function selectionAfter(rows, keepId, index) {
    var at = keepId ? rowIndex(rows, keepId) : -1;
    return at >= 0 ? at : Math.max(0, Math.min(index, rows.length - 1));
}

var ROLES = ["itemId", "kind", "icon", "appIcon", "appId", "label", "target", "detail", "path", "action", "childCount", "disabled", "section"];

// Brings a ListModel to `rows` in place, keyed by itemId: a row that is still
// wanted keeps its model entry (and so its delegate), moved into place if
// rows before it came or went; a changed one is updated role by role; new
// rows are inserted and rows no longer wanted removed. Replacing the whole
// model (a new JS array, or Omarchy's clear and refill) rebuilt every
// delegate on each guard or provider answer. Returns the number of model
// operations, 0 when nothing changed.
function syncRows(model, rows) {
    var ops = 0;
    var ids = [];
    for (var n = 0; n < model.count; n++)
        ids.push(model.get(n).itemId);
    for (var i = 0; i < rows.length; i++) {
        var want = rows[i];
        var at = ids.indexOf(want.itemId, i);
        if (at < 0) {
            model.insert(i, want);
            ids.splice(i, 0, want.itemId);
            ops += 1;
            continue;
        }
        if (at > i) {
            model.move(at, i, 1);
            ids.splice(i, 0, ids.splice(at, 1)[0]);
            ops += 1;
        }
        var have = model.get(i);
        for (var k = 0; k < ROLES.length; k++) {
            if (have[ROLES[k]] !== want[ROLES[k]]) {
                model.setProperty(i, ROLES[k], want[ROLES[k]]);
                ops += 1;
            }
        }
    }
    if (model.count > rows.length) {
        model.remove(rows.length, model.count - rows.length);
        ops += 1;
    }
    return ops;
}

// What the menu learnt in this shell's lifetime, kept across opens: the panel
// is destroyed on close, but a `.pragma library` script lives as long as the
// engine. A reopened menu starts from the last guard answers and provider
// rows instead of an empty set the batch (about a second on io) fills in.
var memory = {
    defaultText: null,
    userText: null,
    guards: null,
    providerRows: {}
};

// Commands whose answer several `checked:` rows compare against. The batch
// runs each once and substitutes the captured value, so Defaults > Browser
// asks `haseen setup default browser` once rather than once per row. Eager:
// a lazy memo set inside one `$(...)` would die with that subshell.
var GUARD_READERS = ["haseen setup dns", "haseen setup default browser", "haseen setup default terminal", "haseen setup default editor", "haseen setup default agent", "haseen font current", "haseen context status"];

// Package and command presence asked one at a time are almost all fork; the
// helpers answer them inside the guard process. `pacman -Qi` provides are
// included so a provider package (gvim for vim) counts as present. Without
// pacman (NixOS) every package reads as missing.
function guardHelpers() {
    return 'declare -A __haseen_pkgs=()\n'
        + 'if command -v pacman >/dev/null; then mapfile -t __haseen_pkg_names < <({ pacman -Qq; LC_ALL=C pacman -Qi'
        + " | awk '/^[A-Za-z]/ { provides = ($0 ~ /^Provides/); sub(/^[^:]*: /, \"\") }"
        + ' provides && $0 != "None" { n = split($0, p, " ");'
        + ' for (i = 1; i <= n; i++) { sub(/[<>=].*/, "", p[i]); print p[i] } }\'; } 2>/dev/null)\n'
        + 'for __haseen_pkg in "${__haseen_pkg_names[@]}"; do __haseen_pkgs[$__haseen_pkg]=1; done; fi\n'
        + 'haseen-pkg-present() { local p; for p in "$@"; do [[ -n ${__haseen_pkgs[$p]-} ]] || return 1; done; return 0; }\n'
        + 'haseen-cmd-present() { local c; for c in "$@"; do command -v "$c" &>/dev/null || return 1; done; return 0; }\n'
        + 'haseen-flag() { [[ -e ${HASEEN_USER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/haseen}/flags/$1 ]]; }\n';
}

function guardReaderSlot(index) {
    return "${__haseen_read_" + index + "}";
}

function substituteGuardReaders(expression) {
    for (var i = 0; i < GUARD_READERS.length; i++)
        expression = expression.split("$(" + GUARD_READERS[i] + ")").join(guardReaderSlot(i));
    return expression;
}

function guardLine(id, tag, expression) {
    return "if { " + substituteGuardReaders(expression) + "; } >/dev/null 2>&1 </dev/null; then echo " + id + ":" + tag + ":1; else echo " + id + ":" + tag + ":0; fi\n";
}

// One bash script for every `when:`, `checked:` and `disabled:`, printing
// `<id>:<w|c|d>:<0|1>` per line. Empty when nothing asks.
function guardScript(items) {
    var guards = "";
    for (var id in items) {
        var entry = items[id];
        if (!entry)
            continue;
        if (entry.when)
            guards += guardLine(id, "w", entry.when);
        if (entry.checked)
            guards += guardLine(id, "c", entry.checked);
        if (entry.disabled)
            guards += guardLine(id, "d", entry.disabled);
    }
    if (!guards)
        return "";
    var prelude = guardHelpers();
    for (var i = 0; i < GUARD_READERS.length; i++) {
        if (guards.indexOf(guardReaderSlot(i)) < 0)
            continue;
        prelude += "__haseen_read_" + i + "=$(" + GUARD_READERS[i] + " 2>/dev/null </dev/null) || :\n";
    }
    return prelude + guards;
}

// Parses guardScript output into { w: {}, c: {}, d: {} }.
function parseGuardOutput(text) {
    var out = {
        w: {},
        c: {},
        d: {}
    };
    var lines = String(text || "").split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = /^(.+):([wcd]):([01])$/.exec(lines[i].trim());
        if (m)
            out[m[2]][m[1]] = m[3] === "1";
    }
    return out;
}

// An action that only toggles one of this shell's panels runs in-process.
function panelAction(action) {
    var m = /^haseen shell ipc panel toggle ([a-z0-9.-]+)$/.exec(String(action || "").trim());
    return m ? m[1] : "";
}
