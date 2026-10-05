.pragma library

// Initial properties must exist before Component.onCompleted, including required
// properties. Inspect only the root declarations, not children with coincident
// names (Syncthing owns an unrelated SettingsController named settings).
var declarations = {};

// Components outlive their load() call: a created instance keeps bindings into
// the component's creation context. Count the ones still held, so a host that
// never releases them is visible instead of quietly growing.
var live = 0;
function liveComponents() { return live; }

function firstError(text, url) {
    var dir = String(url).replace(/[^/]*$/, "");
    var lines = String(text || "").split("\n").filter(function (l) { return l.trim() !== ""; });
    return (lines.length ? lines[0].trim() : "unknown error").split(dir).join("");
}

function rootDeclarations(text) {
    var clean = String(text).replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|`(?:\\.|[^`\\])*`/g,
        function (s) { return s.replace(/[^\n]/g, " "); });
    var root = /\b([A-Za-z_][\w.]*)\s*\{/.exec(clean);
    if (!root) throw new Error("entry has no QML root object");
    var body = clean.slice(root.index + root[0].length), depth = 1, top = "";
    for (var i = 0; i < body.length && depth > 0; i++) {
        var c = body[i];
        if (c === "{") depth++;
        if (depth === 1 && c !== "}") top += c; else top += c === "\n" ? "\n" : " ";
        if (c === "}") depth--;
    }
    var props = {}, re = /\b(readonly\s+)?(?:required\s+)?property\s+([\w.<>]+)\s+(\w+)/g, match;
    while ((match = re.exec(top))) props[match[3]] = { writable: !match[1], type: match[2] };
    return { type: root[1], properties: props };
}

function source(url, parent) {
    // Quickshell FileView avoids Qt's disabled-by-default local XHR access.
    // Read each small entry once at construction; no watcher/poll survives it.
    var reader = Qt.createQmlObject('import Quickshell.Io; FileView { blockLoading: true; printErrors: false }', parent, "CompatSourceReader");
    var text = "";
    try {
        reader.path = decodeURIComponent(String(url).replace(/^file:\/\//, ""));
        text = reader.text();
    } finally { reader.destroy(); }
    if (!text) throw new Error("cannot read entry declarations");
    return text;
}

function propertiesFor(url, seen, parent) {
    if (declarations[url]) return declarations[url];
    seen = Object.assign({}, seen || {});
    if (seen[url]) throw new Error("cyclic QML root inheritance");
    seen[url] = true;
    var text = source(url, parent), root = rootDeclarations(text), props = {}, bases = [];
    var name = root.type.split(".").pop(), alias = root.type.indexOf(".") >= 0 ? root.type.split(".")[0] : "";
    var builtin = ["Item", "QtObject", "Scope", "Singleton", "Rectangle", "Loader", "PopupWindow", "PanelWindow", "ShellRoot"].indexOf(name) >= 0;
    var imports = /^\s*import\s+("[^"]+"|[\w.]+)(?:\s+[\d.]+)?(?:\s+as\s+(\w+))?/gm, match;
    while ((match = imports.exec(text))) {
        if (alias && match[2] !== alias) continue;
        if (!alias && match[2]) continue;
        if (!builtin && match[1] === "qs.Ui")
            bases.push(String(Qt.resolvedUrl("Omarchy/Ui/" + name + ".qml")));
        else if (!builtin && match[1][0] === '"')
            bases.push(url.replace(/[^/]*$/, "") + match[1].slice(1, -1) + "/" + name + ".qml");
    }
    if (!builtin && !alias)
        bases.push(url.replace(/[^/]*$/, "") + name + ".qml");
    if (!builtin) {
        var found = false, errors = [];
        for (var base of bases) {
            if (String(base) === String(url)) continue;
            try {
                props = Object.assign({}, propertiesFor(String(base), seen, parent));
                found = true;
                break;
            } catch (e) { errors.push(String(e)); }
        }
        if (!found)
            throw new Error("cannot resolve root " + root.type + ": " + errors.join("; "));
    }
    for (var k in root.properties) props[k] = root.properties[k];
    declarations[url] = props;
    return props;
}

function initialProperties(url, candidates, parent) {
    var declared = propertiesFor(String(url), null, parent), out = {};
    for (var k in candidates) {
        var p = declared[k];
        if (!p || !p.writable) continue;
        if (k === "settings" && p.type !== "var" && p.type !== "variant") continue;
        out[k] = candidates[k];
    }
    return out;
}

// Backwards-compatible three-argument loading is used by the DMS adapter.
// Return a cancellation function; disconnect before calling done or destroying
// the parent, so an asynchronous compilation can never create a stale child.
function load(url, parent, done, candidates) {
    // QML functions and bindings retain their creation context. Keep a
    // successful Component owned by the host until its plugin is destroyed;
    // destroying it here can silently invalidate completion callbacks. The
    // returned function releases it, so callers destroy their instance first.
    var component = Qt.createComponent(url, 0 /* PreferSynchronous */, parent), finished = false, connected = false;
    live++;
    function release() {
        if (!component) return;
        component.destroy();
        component = null;
        live--;
    }
    function disconnect() {
        if (connected) { component.statusChanged.disconnect(changed); connected = false; }
    }
    function finish() {
        if (finished || component.status === 2) return;
        finished = true;
        disconnect();
        var item = null, error = "";
        if (component.status !== 1) error = firstError(component.errorString(), url);
        else {
            try { item = component.createObject(parent, candidates ? initialProperties(url, candidates, parent) : {}); }
            catch (e) { error = String(e); }
            if (!item && !error) error = "could not create entry: " + firstError(component.errorString(), url);
        }
        if (!item)
            release();
        done({ item: item, error: error });
    }
    function changed() { finish(); }
    if (component.status === 2) { component.statusChanged.connect(changed); connected = true; }
    else finish();
    return function () {
        finished = true;
        disconnect();
        release();
    };
}

function object(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }

function changes(before, after, path) {
    path = path || [];
    if (JSON.stringify(before) === JSON.stringify(after)) return [];
    if (!object(before) || !object(after)) return [{ path: path, value: after, remove: after === undefined }];
    var out = [], keys = Object.keys(before).concat(Object.keys(after).filter(function (k) { return !(k in before); }));
    for (var i = 0; i < keys.length; i++) out = out.concat(changes(before[keys[i]], after[keys[i]], path.concat([keys[i]])));
    return out;
}

function allowedChange(id, path) {
    if (path.some(function (k) { return ["__proto__", "constructor", "prototype"].indexOf(k) >= 0; })) return false;
    if (path[0] === "plugins") return path.length >= 3 && path[1] === id && path[2] === "settings";
    if (path[0] === "idle") return path.length === 2 && path[1] === "screensaver";
    return path[0] === "bar" && path.length === 2 && ["position", "height", "transparent", "left", "center", "right"].indexOf(path[1]) >= 0;
}
