// Emoji ranking for haseen.emojisearch (plan 081). The data and the match
// rule are haseen.emoji's (EmojiSearch.js: the query is a substring of the
// keywords); this adds an order for a list: keywords that start with the
// query as a word (the emoji's name: "cat pet cat face" for cat) first, then
// the query as a whole word elsewhere, then a word that starts with it, then
// any substring, each in the data's order (common emoji first).
.pragma library
.import "../haseen.emoji/EmojiSearch.js" as EmojiSearch

function tier(item, needle) {
    const k = String(item.k || "").toLowerCase();
    if (k === needle || k.indexOf(needle + " ") === 0)
        return 0;
    const words = k.split(/\s+/);
    if (words.indexOf(needle) >= 0)
        return 1;
    for (let i = 0; i < words.length; i++)
        if (words[i].indexOf(needle) === 0)
            return 2;
    return 3;
}

function rank(emojis, query, limit) {
    const needle = EmojiSearch.normalizedQuery(query);
    const max = Number(limit) > 0 ? Number(limit) : 50;
    const hits = EmojiSearch.filterEmojis(emojis, needle, needle === "" ? max : 100000);
    if (needle === "")
        return hits;
    return hits.map((item, i) => ({
                    item: item,
                    t: tier(item, needle),
                    i: i
                })).sort((a, b) => a.t - b.t || a.i - b.i).slice(0, max).map(x => x.item);
}

// Copy, never type: no key injection (plan 018).
function copyArgv(emoji) {
    return ["wl-copy", "--", String(emoji)];
}
