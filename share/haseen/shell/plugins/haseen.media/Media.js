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

// --- panel model ---------------------------------------------------------

// The panel's player: the one the user picked (by D-Bus name) while it is
// still there, else the same pick as the bar.
function selectIndex(players, chosen) {
    if (!players || players.length === 0)
        return -1;
    if (chosen) {
        const i = players.findIndex(p => p.dbusName === chosen);
        if (i >= 0)
            return i;
    }
    return pickIndex(players);
}

// Seconds -> "m:ss", "h:mm:ss" from an hour on; "0:00" for junk.
function formatTime(seconds) {
    let s = Math.floor(Number(seconds));
    if (!(s > 0))
        s = 0;
    const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
    const pad = n => (n < 10 ? "0" : "") + n;
    return h > 0 ? h + ":" + pad(m) + ":" + pad(r) : m + ":" + pad(r);
}

// Position as a 0..1 fraction of the length; 0 without a length.
function fraction(position, length) {
    const p = Number(position), l = Number(length);
    if (!(l > 0) || !(p > 0))
        return 0;
    return Math.min(1, p / l);
}

// Cover art source under plan 010's remote-image rule: what the player
// hands over locally (file:// or a path, an inline data:image/ URI) always
// shows; an https URL only with allowRemote (the remoteArt setting, off by
// default: the fetch tells the art server what is playing, and when, from
// this IP). Plain http never (anyone on the path sees it); anything else
// (empty, unknown schemes) is "", the themed placeholder.
function artSource(url, allowRemote) {
    const u = String(url || "").trim();
    if (/^file:\/\//i.test(u) || /^data:image\//i.test(u))
        return u;
    if (u.startsWith("/"))
        return "file://" + u;
    if (allowRemote === true && /^https:\/\/[^\s/]/i.test(u))
        return u;
    return "";
}

// Which controls to show; an unsupported control is hidden, not disabled.
// p: { canControl, canGoPrevious, canGoNext, canTogglePlaying, canSeek,
//      lengthSupported, positionSupported, length, shuffleSupported,
//      loopSupported, volumeSupported }
function controls(p) {
    if (!p)
        return { previous: false, playPause: false, next: false, seek: false, time: false, shuffle: false, loop: false, volume: false };
    const ctl = p.canControl === true;
    const time = p.positionSupported === true && p.lengthSupported === true && Number(p.length) > 0;
    return {
        previous: p.canGoPrevious === true,
        playPause: p.canTogglePlaying === true,
        next: p.canGoNext === true,
        seek: time && p.canSeek === true,
        time: time,
        shuffle: ctl && p.shuffleSupported === true,
        loop: ctl && p.loopSupported === true,
        volume: ctl && p.volumeSupported === true
    };
}

// Loop cycle None -> Playlist -> Track -> None (MprisLoopState: 0 None,
// 1 Track, 2 Playlist).
function nextLoop(state) {
    return state === 0 ? 2 : state === 2 ? 1 : 0;
}

// Loop button glyph (Nerd Font, Material Design: repeat-off, repeat-once,
// repeat).
function loopGlyph(state) {
    return state === 1 ? "\udb81\udc58" : state === 2 ? "\udb81\udc56" : "\udb81\udc57";
}

// Player volume glyph, as the audio widget draws the sink's.
function volumeGlyph(volume) {
    const v = Number(volume);
    return !(v > 0) ? "\ueee8" : v >= 0.67 ? "\uf028" : v >= 0.34 ? "\uf027" : "\uf026";
}

// Switcher labels: the identity ("Spotify"), else the bus name without
// org.mpris.MediaPlayer2.; a repeated name gets " 2", " 3" in list order.
// players: [{ identity, dbusName }]
function playerLabels(players) {
    const seen = {};
    return (players || []).map(p => {
        let name = String(p.identity || "").trim();
        if (name === "")
            name = String(p.dbusName || "").replace(/^org\.mpris\.MediaPlayer2\./, "") || "Player";
        seen[name] = (seen[name] || 0) + 1;
        return seen[name] > 1 ? name + " " + seen[name] : name;
    });
}
