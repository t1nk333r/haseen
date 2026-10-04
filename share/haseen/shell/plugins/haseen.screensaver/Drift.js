// Drift.js: where the native screensaver's card sits at a given tick (plan
// 019). The card moves a few pixels per tick and bounces off the screen
// edges, so no pixel shows the same thing for long, and nothing animates
// between ticks: one repaint every tick, no frame loop. Pure functions,
// unit-tested under node in tests/test-ambient.sh.

// Triangle wave: 0 → range → 0 → …, for t >= 0. range <= 0 pins it at 0.
function bounce(t, range) {
    if (!(range > 0))
        return 0;
    const m = t % (2 * range);
    return m <= range ? m : 2 * range - m;
}

// Top-left corner of a cw x ch card inside a w x h screen at tick `tick`,
// `margin` px from every edge. `phase` (any non-negative integer) offsets
// the start so each show begins somewhere else. step: px per tick.
function position(tick, phase, w, h, cw, ch, margin, step) {
    const rx = Math.floor(w - cw - 2 * margin);
    const ry = Math.floor(h - ch - 2 * margin);
    const t = (tick + phase) * step;
    // Different speeds on the two axes, so the path is not a diagonal.
    return {
        x: margin + bounce(t, rx),
        y: margin + bounce(Math.floor(t * 2 / 3), ry)
    };
}

if (typeof module !== "undefined")
    module.exports = { bounce: bounce, position: position };
