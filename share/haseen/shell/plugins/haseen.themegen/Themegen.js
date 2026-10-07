.pragma library

// Model for haseen.themegen: the scheme list, the default theme name, the
// argv of each `haseen theme generate` run and the reading of its --json
// preview. Pure, so tests run it headless under the Qt JS engine
// (tests/test-themegen.sh). The colour work itself is the CLI's: the panel
// shows what the command would write and never computes a colour.

// matugen's scheme types, as bin/haseen-theme-generate names them (SCHEMES).
var SCHEMES = ["tonal-spot", "content", "expressive", "fidelity", "fruit-salad", "monochrome", "neutral", "rainbow", "vibrant"];
var MODES = ["dark", "light"];

// The keys a preview must carry, in swatch order: the surfaces and text, the
// accent and selection, then the six hues and their bright variants.
var ANCHORS = ["background", "lighter_background", "foreground", "dark_foreground", "muted", "accent", "selection"];
var HUES = ["red", "yellow", "green", "cyan", "blue", "magenta"];

var HEX = /^#[0-9a-fA-F]{6}$/;
var NAME = /^[a-z0-9][a-z0-9._-]*$/;

// "tonal-spot" -> "Tonal spot".
function schemeLabel(scheme) {
    var s = String(scheme || "").replace(/-/g, " ");
    return s.charAt(0).toUpperCase() + s.slice(1);
}

// The default theme name for an image: bin/haseen-theme-generate's slug(),
// the file name without its extension, lowercased, every run of other
// characters one dash, at most 48 characters.
function defaultName(path) {
    var s = String(path || "").split("/").pop().replace(/\.[^.]*$/, "").toLowerCase();
    s = s.replace(/[^a-z0-9]+/g, "-").replace(/^-/, "").slice(0, 48).replace(/-$/, "");
    return s === "" ? "generated" : s;
}

function validName(name) {
    return NAME.test(String(name || ""));
}

// The next entry of `list` after `current`, `delta` steps on, wrapping; the
// first entry when `current` is not in it.
function cycle(list, current, delta) {
    var i = list.indexOf(current);
    if (i < 0)
        return list[0];
    var n = list.length;
    return list[((i + delta) % n + n) % n];
}

function baseArgv(cli, image, scheme, mode, name) {
    var argv = [cli, "theme", "generate", image, "--scheme", scheme, "--mode", mode];
    if (validName(name))
        argv.push("--name", name);
    return argv;
}

// The preview run: prints JSON, writes nothing.
function previewArgv(cli, image, scheme, mode, name) {
    return baseArgv(cli, image, scheme, mode, name).concat(["--json"]);
}

// Save writes the theme; Apply writes it and switches to it.
function writeArgv(cli, image, scheme, mode, name, apply) {
    var argv = baseArgv(cli, image, scheme, mode, name);
    if (!apply)
        argv.push("--no-apply");
    return argv;
}

function failed(error) {
    return {
        ok: false,
        error: error,
        colors: ({}),
        clamped: [],
        target: "",
        name: "",
        source: ""
    };
}

// parsePreview(text) -> {ok, error, colors, clamped, target, name, source}.
// Anything short of a complete palette is an error: the mock is never drawn
// from half a theme.
function parsePreview(text) {
    var data;
    try {
        data = JSON.parse(String(text || ""));
    } catch (e) {
        return failed("no preview");
    }
    if (data === null || typeof data !== "object" || data.colors === null || typeof data.colors !== "object")
        return failed("no preview");
    var keys = ANCHORS.concat(HUES, HUES.map(function (h) {
        return "bright_" + h;
    }));
    for (var i = 0; i < keys.length; i++)
        if (!HEX.test(String(data.colors[keys[i]] || "")))
            return failed("preview is missing " + keys[i]);
    return {
        ok: true,
        error: "",
        colors: data.colors,
        clamped: Array.isArray(data.clamped) ? data.clamped.map(String) : [],
        target: String(data.target || ""),
        name: String(data.name || ""),
        source: HEX.test(String(data.source || "")) ? data.source : ""
    };
}

// Swatch rows for the preview: anchors, hues, bright hues.
function swatchRows(colors) {
    function row(keys) {
        return keys.map(function (k) {
            return {
                key: k,
                color: colors[k]
            };
        });
    }
    return [row(ANCHORS), row(HUES), row(HUES.map(function (h) {
        return "bright_" + h;
    }))];
}

// A swatch caption that fits under a swatch: a hue's first three letters,
// "+" for its bright variant ("bright_yellow" -> "yel+").
var LABELS = {
    background: "bg",
    lighter_background: "surface",
    foreground: "fg",
    dark_foreground: "dim fg",
    muted: "muted",
    accent: "accent",
    selection: "select"
};

function swatchLabel(key) {
    var k = String(key || "");
    if (LABELS[k])
        return LABELS[k];
    var bright = k.indexOf("bright_") === 0;
    return (bright ? k.slice(7) : k).slice(0, 3) + (bright ? "+" : "");
}

// What Save would do to the name, before it is pressed.
function targetNote(target, name) {
    switch (target) {
    case "generated":
        return "replaces your generated theme " + name;
    case "stock":
        return name + " is a stock theme: pick another name";
    case "taken":
        return name + " is a theme of yours: pick another name";
    default:
        return "";
    }
}

function canWrite(target) {
    return target === "new" || target === "generated";
}

// The last non-empty line of a failed run's stderr, without the "Error: "
// prefix common.sh's die() adds.
function errorLine(text, fallback) {
    var lines = String(text || "").split("\n").filter(function (l) {
        return l.trim() !== "";
    });
    return lines.length > 0 ? lines[lines.length - 1].replace(/^Error: /, "").trim() : fallback;
}
