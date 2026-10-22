// Adapted from Omarchy shell/Commons/Plural.js and Numbers.js (v4.5.0-rc1).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: only the two languages haseen ships (en, ar) keep their rules;
// unknown codes fall back to English's; `fill` replaces %1..%9 in one pass
// (plan 109).

// CLDR cardinal plural category for a count: "zero", "one", "two", "few",
// "many" or "other". A plural catalog entry is an object keyed by these
// ({"one": "%1 file", "other": "%1 files"}); Arabic reaches all six. A
// fraction ("1.5 hours") is "other" in both languages.
function category(code, count) {
    const n = Math.abs(Number(count) || 0);
    if (n !== Math.trunc(n))
        return "other";
    const n100 = n % 100;
    if (String(code || "") === "ar") {
        if (n <= 2)
            return ["zero", "one", "two"][n];
        if (n100 >= 3 && n100 <= 10)
            return "few";
        if (n100 >= 11 && n100 <= 99)
            return "many";
        return "other";
    }
    return n === 1 ? "one" : "other";
}

// The categories a translation of a plural entry must carry.
function categories(code) {
    return String(code || "") === "ar" ? ["zero", "one", "two", "few", "many", "other"] : ["one", "other"];
}

// The form for count from a plural entry, or the entry itself when it is a
// plain string. A translation missing a category falls back to "other".
function pick(entry, code, count) {
    if (typeof entry === "string")
        return entry;
    if (!entry || typeof entry !== "object")
        return undefined;
    const form = entry[category(code, count)];
    if (typeof form === "string" && form.length > 0)
        return form;
    return typeof entry.other === "string" ? entry.other : undefined;
}

// %1..%9 replaced by args[0..8], in one pass, so an argument that itself
// contains "%2" is never expanded again (Qt's chained .arg() would).
function fill(text, args) {
    const list = args || [];
    return String(text).replace(/%([1-9])/g, function (whole, digit) {
        const value = list[Number(digit) - 1];
        return value === undefined || value === null ? whole : String(value);
    });
}

// A number with the language's decimal separator and digits, ungrouped:
// format(13.14, 1, ".", "0") is "13.1". Without decimals the value is
// written as it is.
function formatNumber(value, decimals, decimal, zeroDigit) {
    const number = Number(value);
    if (!isFinite(number))
        return String(value);
    let text = decimals === undefined ? String(number) : number.toFixed(decimals);
    if (decimal && decimal !== ".")
        text = text.replace(".", decimal);
    if (zeroDigit && zeroDigit !== "0") {
        const zero = zeroDigit.charCodeAt(0);
        text = text.replace(/[0-9]/g, d => String.fromCharCode(zero + d.charCodeAt(0) - 48));
    }
    return text;
}

if (typeof module !== "undefined")
    module.exports = { category, categories, pick, fill, formatNumber };
