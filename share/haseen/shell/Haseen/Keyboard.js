.pragma library

// Keyboard layouts and lock keys from Hyprland (plans 079, 080). Pure
// functions over what `hyprctl -j devices` prints and what the socket2
// `activelayout` event says, so the Keyboard singleton, haseen.osd and
// haseen.kblayout share one reading and tests run them in a plain Qt JS engine.

// xkb layout descriptions start with a language ("Arabic (Buckwalter)",
// "English (US)"). The codes are the language part of xkb's own indicator,
// `<shortDescription>` in /usr/share/X11/xkb/rules/evdev.xml, upper-cased.
const LANGUAGES = {
    "Albanian": "SQ",
    "Amharic": "AM",
    "Arabic": "AR",
    "Armenian": "HY",
    "Azerbaijani": "AZ",
    "Bangla": "BN",
    "Belarusian": "BE",
    "Belgian": "BE",
    "Bosnian": "BS",
    "Bulgarian": "BG",
    "Chinese": "ZH",
    "Croatian": "HR",
    "Czech": "CS",
    "Danish": "DA",
    "Dari": "FA",
    "Dutch": "NL",
    "English": "EN",
    "Esperanto": "EO",
    "Estonian": "ET",
    "Finnish": "FI",
    "French": "FR",
    "Georgian": "KA",
    "German": "DE",
    "Greek": "EL",
    "Hebrew": "HE",
    "Hindi": "HI",
    "Hungarian": "HU",
    "Icelandic": "IS",
    "Indonesian": "ID",
    "Irish": "GA",
    "Italian": "IT",
    "Japanese": "JA",
    "Kazakh": "KK",
    "Korean": "KO",
    "Kurdish": "KU",
    "Latvian": "LV",
    "Lithuanian": "LT",
    "Macedonian": "MK",
    "Malay": "MS",
    "Norwegian": "NO",
    "Pashto": "PS",
    "Persian": "FA",
    "Polish": "PL",
    "Portuguese": "PT",
    "Romanian": "RO",
    "Russian": "RU",
    "Serbian": "SR",
    "Slovak": "SK",
    "Slovenian": "SL",
    "Spanish": "ES",
    "Swedish": "SV",
    "Tamil": "TA",
    "Thai": "TH",
    "Turkish": "TR",
    "Ukrainian": "UK",
    "Urdu": "UR",
    "Uyghur": "UG",
    "Uzbek": "UZ",
    "Vietnamese": "VI"
};

// xkb layout names (the `layout` field, "us,ara") whose language differs from
// the name, for the layout list. The rest upper-case their first two letters.
const XKB = {
    "us": "EN", "gb": "EN", "au": "EN", "nz": "EN", "za": "EN", "ng": "EN", "gh": "EN", "ie": "EN",
    "ara": "AR", "eg": "AR", "iq": "AR", "ma": "AR", "sy": "AR", "dz": "AR",
    "ir": "FA", "af": "FA", "il": "HE", "pk": "UR", "cn": "ZH", "jp": "JA", "kr": "KO",
    "cz": "CS", "dk": "DA", "se": "SV", "ee": "ET", "gr": "EL", "ua": "UK", "by": "BE",
    "at": "DE", "ch": "DE", "ca": "FR", "br": "PT", "latam": "ES", "rs": "SR", "si": "SL",
    "ge": "KA", "am": "HY", "kz": "KK", "al": "SQ", "ba": "BS", "et": "AM", "vn": "VI",
    "epo": "EO", "in": "HI"
};

// "Arabic (QWERTY, Eastern Arabic numerals)" -> "AR".
function codeFromName(name) {
    const text = typeof name === "string" ? name.trim() : "";
    if (text === "")
        return "";
    const language = text.replace(/\s*\(.*$/, "").trim();
    if (LANGUAGES[language])
        return LANGUAGES[language];
    const letters = language.replace(/[^A-Za-z]/g, "");
    return letters.slice(0, 2).toUpperCase();
}

// "ara" -> "AR", "us" -> "EN", "de" -> "DE".
function codeFromXkb(layout) {
    const name = typeof layout === "string" ? layout.trim().toLowerCase() : "";
    if (name === "")
        return "";
    return XKB[name] || name.replace(/[^a-z]/g, "").slice(0, 2).toUpperCase();
}

// One `activelayout` payload: "KEYBOARD,LAYOUT". Keyboard names never hold a
// comma; descriptions can ("Arabic (AZERTY, Eastern Arabic numerals)").
function parseLayoutEvent(data) {
    const text = typeof data === "string" ? data : "";
    const comma = text.indexOf(",");
    if (comma <= 0)
        return null;
    return {
        keyboard: text.slice(0, comma),
        layout: text.slice(comma + 1)
    };
}

function _keyboards(devicesJson) {
    let parsed = devicesJson;
    if (typeof devicesJson === "string") {
        try {
            parsed = JSON.parse(devicesJson);
        } catch (e) {
            return [];
        }
    }
    return parsed && Array.isArray(parsed.keyboards) ? parsed.keyboards : [];
}

// The keyboard Hyprland marks main (the one typed on last), else the first.
function mainKeyboard(devicesJson) {
    const keyboards = _keyboards(devicesJson);
    for (const k of keyboards)
        if (k && k.main === true)
            return k;
    return keyboards.length > 0 ? keyboards[0] : null;
}

// `hyprctl -j devices` -> what the bar and the OSD need: the main keyboard,
// its layouts, the active one, and every keyboard's current layout name (the
// baseline that tells a real switch from a config reload).
function readDevices(devicesJson) {
    const keyboards = _keyboards(devicesJson);
    const main = mainKeyboard(devicesJson);
    const known = {};
    for (const k of keyboards)
        if (k && typeof k.name === "string")
            known[k.name] = typeof k.active_keymap === "string" ? k.active_keymap : "";
    if (!main)
        return { main: "", layouts: [], index: -1, layout: "", known: known };
    const names = String(main.layout || "").split(",");
    const variants = String(main.variant || "").split(",");
    const layouts = [];
    for (let i = 0; i < names.length; i++) {
        const name = names[i].trim();
        if (name === "")
            continue;
        const variant = (variants[i] || "").trim();
        layouts.push({ layout: name, variant: variant, code: codeFromXkb(name) });
    }
    const index = typeof main.active_layout_index === "number" ? main.active_layout_index : -1;
    return {
        main: String(main.name || ""),
        layouts: layouts,
        index: index,
        layout: typeof main.active_keymap === "string" ? main.active_keymap : "",
        known: known
    };
}

// The lock-key reader: Caps and Num Lock of the main keyboard, or null when
// the output has no keyboard.
function lockState(devicesJson) {
    const main = mainKeyboard(devicesJson);
    if (!main)
        return null;
    return { caps: main.capsLock === true, num: main.numLock === true };
}

// An `activelayout` event against the baseline: `switched` only when a
// keyboard we already know moves to another layout. Hyprland also sends the
// event for every keyboard on a config reload and for a new keyboard; those
// only update the baseline.
function layoutEvent(known, data) {
    const ev = parseLayoutEvent(data);
    const next = Object.assign({}, known || {});
    if (!ev)
        return { known: next, switched: false, keyboard: "", layout: "" };
    const before = next[ev.keyboard];
    next[ev.keyboard] = ev.layout;
    return {
        known: next,
        switched: before !== undefined && before !== ev.layout,
        keyboard: ev.keyboard,
        layout: ev.layout
    };
}
