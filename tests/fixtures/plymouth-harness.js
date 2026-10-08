// A fake Plymouth for haseen.script: runs the rendered theme script in node
// against a recording Window/Image/Sprite/Plymouth API and drives its
// callbacks the way plymouthd does (refresh 50 times a second, the password
// prompt, back to normal, quit). Prints one JSON report on stdout.
//
//   node plymouth-harness.js RENDERED.script
//
// Plymouth's script language is close enough to JavaScript that three
// rewrites make it run: `fun` declares a function, `#` starts a comment, and
// an indexed assignment (`scan[i] = …`) creates the hash it indexes. Scoping
// is the one real difference: a name first assigned inside a Plymouth
// function is local to that call (script-execute.c script_evaluate_var),
// while sloppy JavaScript makes it global. Each callback therefore runs with
// the globals of the loaded script only, and any name it leaves behind is
// removed, so a callback that relied on another call's local fails here as it
// would there.
//
// Images are rectangles with a text or a scale source; text is a fixed cell
// (11 x 22 px, a 14 pt monospace at 96 dpi), enough for layout, not pixels.
"use strict";
const fs = require("fs");
const vm = require("vm");

const CELL_W = 11, CELL_H = 22;
const WIDTH = 1920, HEIGHT = 1080;
function translate(src) {
    const js = src.split("\n").map(line => {
        let out = "", inString = false;
        for (let i = 0; i < line.length; i++) {
            const c = line[i];
            if (c === '"' && line[i - 1] !== "\\") inString = !inString;
            if (c === "#" && !inString) return out + "//" + line.slice(i + 1);
            out += c;
        }
        return out;
    }).join("\n").replace(/\bfun\s+([A-Za-z_]\w*)\s*\(/g, "function $1(");
    const hashes = new Set([...js.matchAll(/^\s*([A-Za-z_]\w*)\[[^\]]*\]\s*=[^=]/gm)].map(m => m[1]));
    return [...hashes].map(h => `${h} = {};`).join(" ") + "\n" + js;
}

const sprites = [];
const callbacks = {};
const textCalls = [];

function makeImage(desc) {
    return Object.assign(Object.create(imageProto), desc);
}
const imageProto = {
    GetWidth() { return this.w; },
    GetHeight() { return this.h; },
    Scale(w, h) { return makeImage({ kind: "scaled", src: this.text ?? this.src, color: this.color, w, h }); },
};
function Image(file) { return null; } // no logo.png beside the script here
Image.Text = (text, r, g, b, a, font) => {
    const t = String(text);
    textCalls.push({ text: t, color: [r, g, b], font: font ?? null });
    return makeImage({ kind: "text", text: t, color: [r, g, b], font: font ?? null, w: [...t].length * CELL_W, h: CELL_H });
};
function Sprite(image) {
    const s = { image: image ?? null, x: 0, y: 0, z: 0, opacity: 1,
        SetImage(i) { this.image = i; }, SetX(v) { this.x = v; }, SetY(v) { this.y = v; },
        SetZ(v) { this.z = v; }, SetOpacity(v) { this.opacity = v; },
        GetX() { return this.x; }, GetY() { return this.y; }, GetZ() { return this.z; } };
    sprites.push(s);
    return s;
}
const Window = { GetWidth: () => WIDTH, GetHeight: () => HEIGHT,
    SetBackgroundTopColor() {}, SetBackgroundBottomColor() {} };
const Plymouth = new Proxy({}, { get: (_, name) => fn => { callbacks[name] = fn; } });

const ctx = vm.createContext({ Image, Sprite, Window, Plymouth });
vm.runInContext(translate(fs.readFileSync(process.argv[2], "utf8")), ctx, { filename: process.argv[2] });
const loaded = new Set(Object.keys(ctx));

function call(name, ...args) {
    const fn = callbacks[name];
    if (!fn) throw new Error(`the script registered no ${name}`);
    fn(...args);
    for (const k of Object.keys(ctx)) if (!loaded.has(k)) delete ctx[k];
}

function snapshot() {
    return sprites.map(s => ({
        kind: s.image ? s.image.kind : "empty",
        text: s.image ? (s.image.text ?? null) : null,
        src: s.image ? (s.image.src ?? null) : null,
        color: s.image ? s.image.color : null,
        x: s.x, y: s.y, z: s.z, w: s.image ? s.image.w : 0, h: s.image ? s.image.h : 0,
        opacity: +s.opacity.toFixed(4),
    }));
}

const report = { registered: Object.keys(callbacks).sort(), screen: [WIDTH, HEIGHT] };
for (let i = 0; i < 10; i++) call("SetRefreshFunction");
report.boot = snapshot();
call("SetDisplayPasswordFunction", "", 0);
report.empty = snapshot();
report.blink = [];
for (let i = 0; i < 100; i++) {
    call("SetRefreshFunction");
    const caret = sprites.find(s => s.image && s.image.text === "█");
    report.blink.push(caret ? +caret.opacity.toFixed(4) : null);
}
call("SetDisplayPasswordFunction", "", 3);
report.typed = snapshot();
call("SetRefreshFunction");
report.typedNextFrame = snapshot();
call("SetDisplayPasswordFunction", "", 120);
report.long = snapshot();
call("SetDisplayNormalFunction");
report.normal = snapshot();
call("SetDisplayPasswordFunction", "", 1);
call("SetQuitFunction");
report.quit = snapshot();
report.textCalls = textCalls;
process.stdout.write(JSON.stringify(report) + "\n");
