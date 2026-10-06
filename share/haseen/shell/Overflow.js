.pragma library

// Which bar widgets leave the bar for the overflow panel (Bar.qml,
// BarOverflowPanel.qml). Pure: no Qt types, so tests/test-bar-overflow.sh runs
// it headless.
//
// The bar has three sections along its length: left (from the start),
// centre (centred) and right (to the end), and the overflow button sits after
// the right section, at the very end. "Does not fit" means a side section
// would come closer than `gap` to the centre one (or, with no centre, the two
// side sections to each other).

// The tray anchors the right section: it is always first there, whatever the
// order in shell.json, and never overflows (owner rule, architecture 5.3).
const TRAY = "haseen.tray";

// Each id once across the bar, first occurrence wins in left, centre, right
// order: overflow is keyed by id, so one id cannot sit in two places. The
// tray moves to the front of the right section.
function sections(left, center, right) {
    const seen = {};
    const once = list => (Array.isArray(list) ? list : []).filter(id => {
            if (typeof id !== "string" || seen[id])
                return false;
            seen[id] = true;
            return true;
        });
    const l = once(left), c = once(center), r = once(right);
    const t = r.indexOf(TRAY);
    if (t > 0)
        r.unshift(r.splice(t, 1)[0]);
    return { left: l, center: c, right: r };
}

// Length of a section: the positive sizes plus `spacing` between them.
// Zero-size widgets (hidden ones) take no room and get no spacing, as in a
// Qt positioner.
function sectionLength(sizes, spacing) {
    let total = 0, n = 0;
    for (const s of sizes)
        if (s > 0) {
            total += s;
            n++;
        }
    return n > 0 ? total + spacing * (n - 1) : 0;
}

// The smallest k in 0..n with fits(k), or n when none fits. With a previous
// count above that, widgets come back only once they fit with `slack` room
// to spare (fitsSlack), so a width that wobbles by a pixel (a clock, a
// counter) does not flip a widget in and out.
function choose(n, fits, fitsSlack, previous) {
    let k = 0;
    while (k < n && !fits(k))
        k++;
    const prev = typeof previous === "number" ? Math.min(previous, n) : -1;
    if (prev <= k)
        return k;
    let s = k;
    while (s < n && !fitsSlack(s))
        s++;
    return Math.min(prev, s);
}

// spec: {
//   length,      the bar's length along its edge (px)
//   spacing,     between widgets in a section
//   gap,         the least room between two sections
//   button,      the overflow button's length (shown only when needed)
//   hysteresis,  extra room a widget needs before it comes back (default 0)
//   left, center, right: [{ id, size }] in bar order, size along the bar
//   overflow,    bar.overflow: ids always in the panel
//   pinned,      bar.pinned: ids never moved automatically
//   never,       ids that never overflow, even when listed (the tray)
// }
// previous: the last result (for hysteresis) or null.
//
// Returns { ids, shown, autoRight, autoLeft, button, fits }: `ids` every
// overflowed id in panel order (bar.overflow order, then the automatic ones
// in the order they left), `shown` those with a size (the panel shows only
// them, and the button only appears for them), `button` whether the overflow
// button shows, `fits` whether the bar now fits.
//
// Automatic order: the right section from its innermost widget (the first
// after the tray) outwards, then, if the left section still reaches the
// centre, the left section from its innermost (last) widget. The centre
// section never overflows on its own; ids in bar.overflow may come from any
// section.
function fit(spec, previous) {
    const L = Number(spec.length) || 0;
    const sp = Number(spec.spacing) || 0;
    const gap = Number(spec.gap) || 0;
    const B = Number(spec.button) || 0;
    const H = Number(spec.hysteresis) || 0;
    const never = (spec.never || []).concat([TRAY]);
    const pinned = spec.pinned || [];
    const entries = s => (Array.isArray(s) ? s : []).map(e => ({ id: e.id, size: Number(e.size) > 0 ? Number(e.size) : 0 }));
    const leftAll = entries(spec.left), centerAll = entries(spec.center), rightAll = entries(spec.right);
    const size = {};
    for (const e of leftAll.concat(centerAll, rightAll))
        size[e.id] = e.size;

    const forced = [];
    for (const id of spec.overflow || [])
        if (id in size && never.indexOf(id) < 0 && forced.indexOf(id) < 0)
            forced.push(id);
    const stay = s => s.filter(e => forced.indexOf(e.id) < 0);
    const left = stay(leftAll), center = stay(centerAll), right = stay(rightAll);
    const movable = e => e.size > 0 && never.indexOf(e.id) < 0 && pinned.indexOf(e.id) < 0;
    const rightCands = right.filter(movable).map(e => e.id);
    const leftCands = left.filter(movable).map(e => e.id).reverse();
    const forcedShown = forced.some(id => size[id] > 0);

    const lenOf = (s, gone) => sectionLength(s.filter(e => gone.indexOf(e.id) < 0).map(e => e.size), sp);
    const leftLen = kL => lenOf(left, leftCands.slice(0, kL));
    // The right section's occupied length, the button included when anything
    // is in overflow.
    const rightLen = (kR, kL) => {
        const r = lenOf(right, rightCands.slice(0, kR));
        const button = forcedShown || kR > 0 || kL > 0;
        return button ? r + B + (r > 0 ? sp : 0) : r;
    };
    const c = sectionLength(center.map(e => e.size), sp);

    let kR = 0, kL = 0, fits;
    if (c > 0) {
        const cStart = (L - c) / 2, cEnd = (L + c) / 2;
        const leftFits = (k, extra) => {
            const l = leftLen(k);
            return l === 0 || l + gap + extra <= cStart;
        };
        const rightFits = (k, extra) => {
            const r = rightLen(k, kL);
            return r === 0 || L - r >= cEnd + gap + extra;
        };
        const prev = previous || {};
        kL = choose(leftCands.length, k => leftFits(k, 0), k => leftFits(k, H), prev.autoLeft);
        kR = choose(rightCands.length, k => rightFits(k, 0), k => rightFits(k, H), prev.autoRight);
        fits = leftFits(kL, 0) && rightFits(kR, 0);
    } else {
        const bothFit = (r, l, extra) => {
            const lr = rightLen(r, l), ll = leftLen(l);
            return ll + lr + (ll > 0 && lr > 0 ? gap + extra : 0) <= L;
        };
        const prev = previous || {};
        kR = choose(rightCands.length, k => bothFit(k, 0, 0), k => bothFit(k, 0, H), prev.autoRight);
        if (kR === rightCands.length)
            kL = choose(leftCands.length, k => bothFit(kR, k, 0), k => bothFit(kR, k, H), prev.autoLeft);
        fits = bothFit(kR, kL, 0);
    }

    const ids = forced.concat(rightCands.slice(0, kR), leftCands.slice(0, kL));
    const shown = ids.filter(id => size[id] > 0);
    return {
        ids: ids,
        shown: shown,
        autoRight: kR,
        autoLeft: kL,
        button: shown.length > 0,
        fits: fits
    };
}

// bar.overflow / bar.pinned after one edit, the rule `haseen bar overflow`
// applies too: `add` puts an id in the panel for good (and unpins it),
// `remove` lets it return when it fits, `pin` keeps it in the bar ("Keep in
// bar": out of bar.overflow, into bar.pinned), `unpin` lets it overflow again
// on its own. The tray is refused for add. Returns null for an unknown verb.
function edit(overflow, pinned, verb, id) {
    const o = (Array.isArray(overflow) ? overflow : []).filter(x => x !== id);
    const p = (Array.isArray(pinned) ? pinned : []).filter(x => x !== id);
    const had = Array.isArray(overflow) && overflow.indexOf(id) >= 0;
    const wasPinned = Array.isArray(pinned) && pinned.indexOf(id) >= 0;
    if (verb === "add") {
        if (id === TRAY)
            return null;
        return { overflow: had ? overflow.slice() : o.concat([id]), pinned: p };
    }
    if (verb === "remove")
        return { overflow: o, pinned: wasPinned ? pinned.slice() : p };
    if (verb === "pin")
        return { overflow: o, pinned: wasPinned ? pinned.slice() : p.concat([id]) };
    if (verb === "unpin")
        return { overflow: had ? overflow.slice() : o, pinned: p };
    return null;
}
