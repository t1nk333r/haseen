.pragma library

// haseen.background's wallpaper transition (plan 161): which effect a change
// gets, when it is skipped, how an image covers a screen, and the steps of
// one change. Pure functions, apart from the QML, so the tests run them in a
// plain Qt JS engine.

const EFFECTS = ["contagion", "outline", "fade", "none"];
const DEFAULT_MS = 1800;
const MIN_MS = 400;
const MAX_MS = 5000;

// The `transition` setting: auto, contagion, outline, fade or none. Anything
// else is auto.
function setting(value) {
    return EFFECTS.indexOf(value) >= 0 ? value : "auto";
}

// The `transitionDuration` setting in milliseconds, held to 0.4-5 s.
function durationMs(value) {
    const n = Number(value);
    if (!isFinite(n) || n <= 0)
        return DEFAULT_MS;
    return Math.round(Math.min(MAX_MS, Math.max(MIN_MS, n)));
}

// The effect for one change. auto takes turns between the two drawn
// effects; its first change picks one with rand (0..1).
function pick(value, previous, rand) {
    const s = setting(value);
    if (s !== "auto")
        return s;
    if (previous === "contagion")
        return "outline";
    if (previous === "outline")
        return "contagion";
    return rand < 0.5 ? "contagion" : "outline";
}

// Whether the effect is drawn by the shader. Only contagion and outline are,
// and only on a GPU scene graph; fade, and every effect on the software
// renderer, is the plain crossfade.
function drawsWithShader(effect, software) {
    return !software && (effect === "contagion" || effect === "outline");
}

// Why a change shows no transition, or "" when it shows one. The wallpaper
// changes either way: the CLI restarts swaybg whatever this says.
//   o.effect       the picked effect
//   o.oldPath      the image swaybg shows now
//   o.newPath      the image it is about to show
//   o.reduceMotion Hyprland's animations:enabled is off (Theme.reduceMotion)
//   o.context      the runtime context (Flags.context): "game" skips
function skipReason(o) {
    const s = o || {};
    if (s.effect === "none")
        return "off";
    if (!s.oldPath)
        return "no old image";
    if (!s.newPath)
        return "no new image";
    if (s.oldPath === s.newPath)
        return "same image";
    if (s.reduceMotion)
        return "animations off";
    if (s.context === "game")
        return "game";
    return "";
}

// How much of an image's texture a screen shows, as swaybg's `fill` mode
// shows it: scaled to cover the screen, centred, the overflow cut off. The
// answer scales texture coordinates around their centre: u' = 0.5 +
// (u - 0.5) * x. Screen W x H, image w x h, any unit.
function coverScale(W, H, w, h) {
    if (!(W > 0 && H > 0 && w > 0 && h > 0))
        return { x: 1, y: 1 };
    const s = Math.max(W / w, H / h);
    return { x: W / (w * s), y: H / (h * s) };
}

// The size of a contagion cell in device pixels: 4 logical pixels.
function cellPx(dpr) {
    return Math.max(2, Math.round(4 * (dpr > 0 ? dpr : 1)));
}

// The steps of one change. A state is { name, played, settled }:
//   idle     nothing loaded
//   loading  the windows exist and decode both images
//   playing  every screen shows the old image; the effect runs
//   holding  the effect has ended on the new image; waiting for swaybg
//   leaving  swaybg shows the new image; the cover fades out
// played: the effect has reached the new image. settled: swaybg was
// restarted with the new image and has had time to paint it.
//
// Events: begin, ready (every screen has drawn the old image), timeout (the
// images did not load in time), played, shown (the CLI restarted swaybg),
// settled (the hold after shown has passed, or the safety bound did), left
// (the fade-out ended), abort.
function initial() {
    return { name: "idle", played: false, settled: false };
}

function covered(state) {
    const n = state && state.name;
    return n === "playing" || n === "holding" || n === "leaving";
}

function reduce(state, event) {
    const s = state || initial();
    const next = (name, played, settled) => ({ name: name, played: played, settled: settled });
    switch (event) {
    case "begin":
        // A change during a change starts over from the new one.
        return next("loading", false, false);
    case "abort":
        return initial();
    case "timeout":
        return s.name === "loading" ? initial() : s;
    case "ready":
        return s.name === "loading" ? next("playing", false, s.settled) : s;
    case "played":
        if (s.name !== "playing")
            return s;
        return s.settled ? next("leaving", true, true) : next("holding", true, false);
    case "shown":
        // swaybg restarted before anything covered it: the new image is
        // already there, and covering it now would show the old one again.
        return s.name === "loading" ? initial() : s;
    case "settled":
        if (s.name === "holding")
            return next("leaving", true, true);
        if (s.name === "playing")
            return next("playing", s.played, true);
        return s;
    case "left":
        return s.name === "leaving" ? initial() : s;
    }
    return s;
}
