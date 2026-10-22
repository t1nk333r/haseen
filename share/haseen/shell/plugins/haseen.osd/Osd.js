.pragma library

// haseen.osd's kinds and cards (plan 079), apart from the QML so the tests
// run them in a plain Qt JS engine.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

// Each kind is a setting. volume, brightness, mic and layout are on unless
// set to false; lockKeys is off unless set to true.
function kinds(settings) {
    const s = settings || {};
    return {
        volume: s.volume !== false,
        brightness: s.brightness !== false,
        mic: s.mic !== false,
        layout: s.layout !== false,
        lockKeys: s.lockKeys === true
    };
}

function volumeGlyph(v, muted) {
    return muted || v <= 0 ? "\ueee8" : v >= 0.67 ? "\uf028" : v >= 0.34 ? "\uf027" : "\uf026";
}

function micGlyph(muted) {
    return muted ? "\uf131" : "\uf130";
}

// A card is {glyph, text, label, value, dim}: a bar with a percent when
// `label` is empty, else one line of text. `text` fills the glyph cell with
// letters instead of an icon (the layout code).
function levelCard(glyph, value, muted) {
    return {
        glyph: glyph,
        text: "",
        label: "",
        value: Math.max(0, Math.min(1, Number(value) || 0)),
        dim: muted === true
    };
}

function layoutCard(name, code) {
    return {
        glyph: code ? "" : "\uf11c",
        text: code || "",
        label: name || "",
        value: 0,
        dim: false
    };
}

// One whole line per state, so a translation never joins two pieces.
const LOCKS = {
    caps: { glyph: "\u{F0632}", on: N_("Caps Lock on"), off: N_("Caps Lock off") },
    num: { glyph: "\u{F03A0}", on: N_("Num Lock on"), off: N_("Num Lock off") }
};

function lockCard(change) {
    const lock = LOCKS[change && change.key] || LOCKS.caps;
    const on = change && change.on === true;
    return {
        glyph: lock.glyph,
        text: "",
        label: on ? lock.on : lock.off,
        value: 0,
        dim: !on
    };
}

// What changed between two lock readings ({caps, num}), Caps first. With no
// baseline yet the reading after a key press still says what Caps Lock is.
function lockChanges(previous, now) {
    if (!now)
        return [];
    if (!previous)
        return [{ key: "caps", on: now.caps }];
    const out = [];
    if (previous.caps !== now.caps)
        out.push({ key: "caps", on: now.caps });
    if (previous.num !== now.num)
        out.push({ key: "num", on: now.num });
    return out;
}
