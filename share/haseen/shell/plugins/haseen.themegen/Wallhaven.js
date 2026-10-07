.pragma library

// Model for haseen.themegen's Wallhaven source (plan 072): the argv of each
// `haseen wallhaven search` / `get` run, the reading of their output and the
// grid's key movement (plan 083).
// Pure, so tests/test-wallhaven.sh runs it under the Qt JS engine against the
// CLI's own --json. The network, the SFW rule, the thumbnail cache and the
// image checks are the CLI's; the panel only lists and picks.

// bin/haseen-wallhaven-search's WH_SORTS, with the chip labels.
var SORTS = ["toplist", "date_added", "random", "relevance", "views", "favorites"];
var SORT_LABELS = {
    toplist: "Top",
    date_added: "Latest",
    random: "Random",
    relevance: "Relevance",
    views: "Views",
    favorites: "Favourites"
};
var ID = /^[a-z0-9]{1,16}$/;
var SEED = /^[a-zA-Z0-9]{6}$/;

function sortLabel(sort) {
    return SORT_LABELS[sort] || String(sort || "");
}

// One page of a search. A random search passes the seed of its first page
// on, so later pages do not repeat it.
function searchArgv(cli, query, sort, page, seed) {
    var argv = [cli, "wallhaven", "search"];
    var q = String(query || "").trim();
    if (q !== "")
        argv.push("--query", q);
    argv.push("--sort", SORTS.indexOf(sort) >= 0 ? sort : SORTS[0], "--page", String(Math.max(1, Math.round(page || 1))));
    if (sort === "random" && SEED.test(String(seed || "")))
        argv.push("--seed", seed);
    argv.push("--json");
    return argv;
}

function getArgv(cli, id) {
    return [cli, "wallhaven", "get", id];
}

function failed(error) {
    return {
        ok: false,
        error: error,
        page: 0,
        lastPage: 0,
        total: 0,
        seed: "",
        items: []
    };
}

// parseSearch(text) -> {ok, error, page, lastPage, total, seed, items}; an
// item is {id, thumb, label, url}, the label its resolution.
function parseSearch(text) {
    var data;
    try {
        data = JSON.parse(String(text || ""));
    } catch (e) {
        return failed("no results");
    }
    if (data === null || typeof data !== "object" || !Array.isArray(data.results))
        return failed("no results");
    var items = [];
    for (var i = 0; i < data.results.length; i++) {
        var r = data.results[i] || {};
        if (!ID.test(String(r.id || "")))
            continue;
        items.push({
            id: r.id,
            thumb: String(r.thumb || ""),
            label: String(r.resolution || r.id),
            url: String(r.url || "")
        });
    }
    var page = Number(data.page) || 1;
    return {
        ok: true,
        error: "",
        page: page,
        lastPage: Math.max(page, Number(data.last_page) || page),
        total: Number(data.total) || 0,
        seed: SEED.test(String(data.seed || "")) ? data.seed : "",
        items: items
    };
}

// The entries of another page that the grid does not list yet (a toplist can
// shift between two calls). `seen` (id -> true) is updated in place, so the
// grid's model is only ever appended to and keeps its scroll position and
// its current cell (plan 083).
function fresh(seen, more) {
    var out = [];
    more.forEach(function (item) {
        if (!seen[item.id]) {
            seen[item.id] = true;
            out.push(item);
        }
    });
    return out;
}

// The cell a key moves to in a grid of `count` cells, `columns` to a row
// (plan 083): dx steps by one cell, dy by a row. A step above the first row
// stays put; a step down into a shorter last row lands on the last cell, and
// one down from the last row stays put. No cell yet: the first one.
function gridStep(index, count, columns, dx, dy) {
    if (count <= 0)
        return -1;
    if (index < 0 || index >= count)
        return 0;
    var cols = Math.max(1, columns);
    if (dy !== 0) {
        var target = index + dy * cols;
        if (target < 0)
            return index;
        if (target >= count)
            return Math.floor((count - 1) / cols) > Math.floor(index / cols) ? count - 1 : index;
        return target;
    }
    return Math.max(0, Math.min(count - 1, index + dx));
}

function hasMore(page, lastPage) {
    return page > 0 && page < lastPage;
}

// "progress 42" from `haseen wallhaven get`'s stderr -> 42; anything else -1.
function progressOf(line) {
    var m = /^progress (\d{1,3})$/.exec(String(line || "").trim());
    return m && Number(m[1]) <= 100 ? Number(m[1]) : -1;
}

// The downloaded image's path: the last line `get` prints on stdout.
function pathOf(text) {
    var lines = String(text || "").split("\n").filter(function (l) {
        return l.trim() !== "";
    });
    var last = lines.length > 0 ? lines[lines.length - 1].trim() : "";
    return last.charAt(0) === "/" ? last : "";
}

// The theme name a Wallhaven picture suggests.
function themeName(id) {
    return "wallhaven-" + id;
}
