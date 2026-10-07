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

// xkb layout names -> their description, for the layout list: the
// top-level `<layout>` entries of xkeyboard-config 2.48's
// rules/evdev.xml (MIT).
const XKB_NAMES = {
    "al": "Albanian", "et": "Amharic", "am": "Armenian", "ara": "Arabic", "eg": "Arabic (Egypt)",
    "iq": "Arabic (Iraq)", "ma": "Arabic (Morocco)", "sy": "Arabic (Syria)", "az": "Azerbaijani", "ml": "Bambara",
    "bd": "Bangla", "by": "Belarusian", "be": "Belgian", "dz": "Berber (Algeria, Latin)", "ba": "Bosnian",
    "brai": "Braille", "bg": "Bulgarian", "mm": "Burmese", "cn": "Chinese", "hr": "Croatian", "cz": "Czech",
    "dk": "Danish", "af": "Dari", "mv": "Dhivehi", "nl": "Dutch", "bt": "Dzongkha", "au": "English (Australia)",
    "cm": "English (Cameroon)", "gh": "English (Ghana)", "nz": "English (New Zealand)", "ng": "English (Nigeria)",
    "za": "English (South Africa)", "gb": "English (UK)", "us": "English (US)", "epo": "Esperanto",
    "ee": "Estonian", "fo": "Faroese", "ph": "Filipino", "fi": "Finnish", "fr": "French", "ca": "French (Canada)",
    "cd": "French (Democratic Republic of the Congo)", "tg": "French (Togo)", "ge": "Georgian", "de": "German",
    "at": "German (Austria)", "ch": "German (Switzerland)", "gr": "Greek", "il": "Hebrew", "hu": "Hungarian",
    "is": "Icelandic", "in": "Indian", "id": "Indonesian (Latin)", "ie": "Irish", "it": "Italian", "jp": "Japanese",
    "kz": "Kazakh", "kh": "Khmer (Cambodia)", "kr": "Korean", "kg": "Kyrgyz", "la": "Lao", "lv": "Latvian",
    "lt": "Lithuanian", "mk": "Macedonian", "my": "Malay (Jawi, Arabic Keyboard)", "mt": "Maltese",
    "md": "Moldavian", "mn": "Mongolian", "me": "Montenegrin", "np": "Nepali", "gn": "N'Ko (AZERTY)",
    "no": "Norwegian", "ir": "Persian", "pl": "Polish", "pt": "Portuguese", "br": "Portuguese (Brazil)",
    "ro": "Romanian", "ru": "Russian", "rs": "Serbian", "lk": "Sinhala (phonetic)", "sk": "Slovak",
    "si": "Slovenian", "es": "Spanish", "latam": "Spanish (Latin American)", "ke": "Swahili (Kenya)",
    "tz": "Swahili (Tanzania)", "se": "Swedish", "tw": "Taiwanese", "tj": "Tajik", "th": "Thai", "bw": "Tswana",
    "tm": "Turkmen", "tr": "Turkish", "ua": "Ukrainian", "pk": "Urdu (Pakistan)", "uz": "Uzbek", "vn": "Vietnamese",
    "sn": "Wolof", "custom": "A user-defined custom Layout"
};

// "ara" -> "Arabic"; an unknown name is shown as it is.
function layoutName(layout) {
    const name = typeof layout === "string" ? layout.trim().toLowerCase() : "";
    return XKB_NAMES[name] || name;
}

// One `activelayout` payload: "KEYBOARD,LAYOUT". Descriptions can hold a
// comma ("Arabic (AZERTY, Eastern Arabic numerals)"), and so can a keyboard
// name: Hyprland only replaces its spaces ("logitech,-inc.-keyboard"). So the
// longest keyboard in `names` the payload starts with wins; the first comma
// is the split only for a keyboard not seen before.
function parseLayoutEvent(data, names) {
    const text = typeof data === "string" ? data : "";
    let keyboard = "";
    for (const name of Array.isArray(names) ? names : [])
        if (typeof name === "string" && name.length > keyboard.length && text.startsWith(name + ","))
            keyboard = name;
    if (keyboard === "") {
        const comma = text.indexOf(",");
        if (comma <= 0)
            return null;
        keyboard = text.slice(0, comma);
    }
    return {
        keyboard: keyboard,
        layout: text.slice(keyboard.length + 1)
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
    const next = Object.assign({}, known || {});
    const ev = parseLayoutEvent(data, Object.keys(next));
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

// Which of `layouts` (readDevices) a switch to the description `layout`
// went to: the one plain layout whose description it is; -1 for a variant
// or two matches, and the caller reads the devices again.
function indexOf(layouts, layout) {
    const list = Array.isArray(layouts) ? layouts : [];
    let hit = -1;
    for (let i = 0; i < list.length; i++) {
        if (list[i].variant !== "" || layoutName(list[i].layout) !== layout)
            continue;
        if (hit >= 0)
            return -1;
        hit = i;
    }
    return hit;
}
