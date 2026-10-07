// Colour arithmetic for derived text colours (Theme.subtle, Theme.over).
// Pure: colours are { r, g, b } in 0..1, which a QML color already is, so
// the tests run this file under the Qt JS engine with the rendered tokens of
// every stock theme and get the numbers the shell draws.
.pragma library

// Secondary text (descriptions, subtitles): the foreground at this alpha,
// Omarchy's menu description opacity (plugins/menu/Menu.qml, 0.52).
var SUBTLE = 0.52;
// Lowest contrast secondary text may have on its row, WCAG's large-text and
// UI-component floor. Theme.subtle raises the alpha until it is met.
var MIN_RATIO = 3;

// fg at alpha composited over an opaque bg.
function over(fg, alpha, bg) {
    var a = Math.max(0, Math.min(1, alpha));
    return {
        r: fg.r * a + bg.r * (1 - a),
        g: fg.g * a + bg.g * (1 - a),
        b: fg.b * a + bg.b * (1 - a)
    };
}

function channel(v) {
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
}

// WCAG 2 relative luminance.
function luminance(c) {
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}

// WCAG 2 contrast ratio of two opaque colours, 1..21.
function ratio(a, b) {
    var la = luminance(a), lb = luminance(b);
    return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

// The smallest alpha from `alpha` up (in steps of 0.01) at which fg over bg
// reaches minRatio against bg, or 1 when even the opaque fg does not.
function readableAlpha(fg, bg, alpha, minRatio) {
    var a = Math.max(0, Math.min(1, alpha));
    while (a < 1 && ratio(over(fg, a, bg), bg) < minRatio)
        a = Math.min(1, Math.round((a + 0.01) * 100) / 100);
    return a;
}
