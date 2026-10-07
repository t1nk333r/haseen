.pragma library

// haseen.osd's kinds and cards (plan 079), apart from the QML so the tests
// run them in a plain Qt JS engine.

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

const LOCKS = {
    caps: { glyph: "\u{F0632}", name: "Caps Lock" },
    num: { glyph: "\u{F03A0}", name: "Num Lock" }
};

function lockCard(change) {
    const lock = LOCKS[change && change.key] || LOCKS.caps;
    const on = change && change.on === true;
    return {
        glyph: lock.glyph,
        text: "",
        label: lock.name + (on ? " on" : " off"),
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
