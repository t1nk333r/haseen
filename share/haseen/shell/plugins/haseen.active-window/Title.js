// haseen.active-window (plan 095): the focused window's title cut to a
// character budget with a middle ellipsis, so the beginning and the end of a
// long title both stay readable. Adapted from the owner's
// t1nk33r.active-window, a fork of Omarchy's active-window widget
// (ActiveWindow.qml, MIT, Copyright (c) David Heinemeier Hansson).
//
// Characters, not UTF-16 code units: a title carrying an emoji holds a
// surrogate pair, and cutting one in half paints tofu.

// Index just past the first `count` characters of `text`, or its length
// when it holds fewer.
function charCut(text, count) {
    let seen = 0;
    for (let i = 0; i < text.length; i++) {
        const code = text.charCodeAt(i);
        if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length)
            i++;
        if (++seen === count)
            return i + 1;
    }
    return text.length;
}

// Start of the last `count` characters, never inside a surrogate pair.
function tailCut(text, count) {
    let seen = 0;
    for (let i = text.length; i > 0;) {
        const code = text.charCodeAt(--i);
        if (code >= 0xDC00 && code <= 0xDFFF && i > 0) {
            const previous = text.charCodeAt(i - 1);
            if (previous >= 0xD800 && previous <= 0xDBFF)
                i--;
        }
        if (++seen === count)
            return i;
    }
    return 0;
}

// The budget from the setting: at least 3 (one character each side of the
// ellipsis), 50 when unset or not a number.
function budget(value) {
    const n = Math.floor(Number(value));
    return Number.isFinite(n) && n > 0 ? Math.max(3, n) : 50;
}

// `title` when it fits in `maxChars` characters, else its head, "…" and its
// tail, `maxChars` characters in all.
function label(title, maxChars) {
    const text = String(title || "");
    const max = budget(maxChars);
    if (charCut(text, max) >= text.length)
        return text;
    const head = Math.ceil((max - 1) / 2);
    return text.substring(0, charCut(text, head)) + "…" + text.substring(tailCut(text, max - head - 1));
}

// What the bar shows for a toplevel: its title, else its app id.
function titleOf(toplevel) {
    if (!toplevel)
        return "";
    return String(toplevel.title || toplevel.appId || "");
}
