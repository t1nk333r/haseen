.pragma library

// Plugin requirements (architecture 5.2, plan 064). A manifest's `requires`
// names commands, tools, haseen layers and a minimum haseen version; the
// shell refuses to load a plugin while any of them is unmet.
// Haseen/Plugins.qml probes the facts in one `bash` run and evaluates them
// here; share/haseen/shell/lib/plugin.sh (plugin_unmet) is the CLI twin and
// prints the same messages, which tests/test-plugin-gates.sh compares.
//
// bins are strict: a command on PATH. tools are what DMS `dependencies` list,
// commands and package names from any distribution mixed: met by a command
// or an installed package of that name, and skipped when no repository knows
// the name (pulseaudio-utils is Debian's), since that cannot be checked here.

var commandPattern = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;
var layerPattern = /^[a-z0-9-]+$/;
var versionPattern = /^[0-9]+\.[0-9]+\.[0-9]+$/;

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

function strings(list, pattern) {
    return Array.isArray(list) && list.every(function (v) {
        return typeof v === "string" && pattern.test(v);
    });
}

// problems(r) -> shape errors of a manifest's `requires` (undefined = none).
function problems(r) {
    if (r === undefined)
        return [];
    if (!isObject(r))
        return ["requires must be an object"];
    var errs = [];
    for (var k in r)
        if (["bins", "tools", "layers", "haseen"].indexOf(k) < 0)
            errs.push("requires: unknown field '" + k + "'");
    if (r.bins !== undefined && !strings(r.bins, commandPattern))
        errs.push("requires.bins must be an array of command names");
    if (r.tools !== undefined && !strings(r.tools, commandPattern))
        errs.push("requires.tools must be an array of command or package names");
    if (r.layers !== undefined && !strings(r.layers, layerPattern))
        errs.push("requires.layers must be an array of layer names");
    if (r.haseen !== undefined && !(typeof r.haseen === "string" && versionPattern.test(r.haseen)))
        errs.push("requires.haseen must be a version (e.g. 0.2.0)");
    return errs;
}

// keys(r) -> the facts a valid `requires` needs: "bin:NAME", "tool:NAME",
// "layer:NAME", "version".
function keys(r) {
    if (!isObject(r))
        return [];
    var out = [];
    (r.bins || []).forEach(function (b) {
        out.push("bin:" + b);
    });
    (r.tools || []).forEach(function (t) {
        out.push("tool:" + t);
    });
    (r.layers || []).forEach(function (l) {
        out.push("layer:" + l);
    });
    if (r.haseen !== undefined)
        out.push("version");
    return out;
}

// atLeast("0.1.0-dev", "0.1.0") -> true. Only major.minor.patch count: the
// development build of a release already carries what a plugin written for
// it uses, and an unreadable version never satisfies a minimum.
function atLeast(installed, minimum) {
    var have = /^([0-9]+)\.([0-9]+)\.([0-9]+)/.exec(String(installed));
    if (!have)
        return false;
    var want = minimum.split(".");
    for (var i = 0; i < 3; i++) {
        var a = Number(have[i + 1]), b = Number(want[i]);
        if (a !== b)
            return a > b;
    }
    return true;
}

// unmet(r, facts) -> { pending, messages }. facts maps every key from keys()
// that was probed: bin/tool/layer keys to booleans, "version" to the installed
// version text. pending: a fact is not probed yet, so nothing is decided.
function unmet(r, facts) {
    if (!isObject(r))
        return {
            pending: false,
            messages: []
        };
    var ks = keys(r);
    var pending = ks.some(function (k) {
        return facts[k] === undefined;
    });
    var messages = [];
    if (pending)
        return {
            pending: true,
            messages: messages
        };
    (r.bins || []).forEach(function (b) {
        if (!facts["bin:" + b])
            messages.push("requires: command '" + b + "' is not on PATH");
    });
    (r.tools || []).forEach(function (t) {
        if (!facts["tool:" + t])
            messages.push("requires: '" + t + "' is neither a command on PATH nor an installed package");
    });
    (r.layers || []).forEach(function (l) {
        if (!facts["layer:" + l])
            messages.push("requires: layer '" + l + "' is not applied (haseen layer apply " + l + ")");
    });
    if (r.haseen !== undefined && !atLeast(facts.version, r.haseen))
        messages.push("requires: haseen " + r.haseen + " or newer (installed: " + (facts.version || "unknown") + ")");
    return {
        pending: false,
        messages: messages
    };
}
