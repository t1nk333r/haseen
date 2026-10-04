.pragma library

// Pure helpers for haseen.media; tests run them headless.

// players: [{ isPlaying, stopped }] -> index of the one to show, -1 for none.
// A playing player wins, then a paused one, then the first.
function pickIndex(players) {
    if (!players || players.length === 0)
        return -1;
    let i = players.findIndex(p => p.isPlaying);
    if (i < 0)
        i = players.findIndex(p => !p.stopped);
    return i < 0 ? 0 : i;
}

// "Artist - Title", or the title alone; the player identity when untitled.
function label(title, artist, identity, showArtist) {
    const t = String(title || "").trim();
    const a = String(artist || "").trim();
    if (t === "")
        return String(identity || "").trim();
    return showArtist && a !== "" ? a + " - " + t : t;
}

// Cut to max characters with "…". Counted by code point (surrogate pairs
// kept whole, so emoji are never split); Qt's JS engine iterates strings by
// UTF-16 unit, so Array.from() would split them.
function truncate(text, max) {
    const chars = String(text || "").match(/[\uD800-\uDBFF][\uDC00-\uDFFF]|[\s\S]/g) || [];
    const n = Math.round(Number(max));
    if (!(n > 0) || chars.length <= n)
        return chars.join("");
    return chars.slice(0, Math.max(1, n - 1)).join("").replace(/\s+$/, "") + "…";
}
