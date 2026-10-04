.pragma library

// Compat manifest adapter (architecture 5.4). Turns an Omarchy manifest.json
// (`kinds` + `entryPoints`) or a DankMaterialShell plugin.json into the
// native manifest shape, so Haseen/Plugins.qml validates and registers it
// like any other plugin. share/haseen/shell/lib/plugin.sh (plugin_manifest)
// repeats these rules in jq for the CLI; tests/test-compat.sh runs both over
// the same fixtures.
//
// Field names follow the upstream manifest formats:
//   Omarchy (MIT, Copyright (c) David Heinemeier Hansson), shell/plugins/*/manifest.json
//   DankMaterialShell (MIT, Copyright (c) 2025 Avenge Media LLC),
//     quickshell/PLUGINS/plugin-schema.json and Services/PluginService.qml
//     (_deriveLegacySurface: which surface a single `component` is)
//
// Only the bar widget is adapted. Every other surface is listed in
// `unsupported` and never loaded; a plugin without a bar widget is refused.

var supportedKinds = ["bar-widget"];

// Omarchy kind -> its entryPoints key.
var omarchyEntryKeys = {
    "bar-widget": "barWidget",
    "service": "service",
    "panel": "panel",
    "overlay": "overlay",
    "menu": "menu",
    "bar": "bar"
};

var dmsIdPattern = /^[a-zA-Z][a-zA-Z0-9]*$/;
var settingTypes = ["string", "number", "integer", "boolean", "array", "object"];

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

// exampleEmojiPlugin -> example-emoji-plugin
function kebab(name) {
    return String(name).replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/([A-Z])([A-Z][a-z])/g, "$1-$2").toLowerCase().replace(/[^a-z0-9-]+/g, "-").replace(/^-+|-+$/g, "");
}

// Registry id of a DMS plugin: DMS ids are camelCase without a namespace.
function dmsId(name) {
    return "dms." + (kebab(name) || "unnamed");
}

// "./Widget.qml" -> "Widget.qml"
function stripDotSlash(p) {
    return typeof p === "string" && p.indexOf("./") === 0 ? p.slice(2) : p;
}

function settingType(type, value) {
    if (settingTypes.indexOf(type) >= 0)
        return type;
    if (Array.isArray(value))
        return "array";
    if (typeof value === "boolean" || typeof value === "number" || typeof value === "object")
        return value === null ? "string" : typeof value;
    return "string";
}

// Omarchy barWidget.defaults + barWidget.schema -> native settings.
function omarchySettings(bw) {
    var out = {};
    if (!isObject(bw))
        return out;
    var defaults = isObject(bw.defaults) ? bw.defaults : {};
    var schema = Array.isArray(bw.schema) ? bw.schema : [];
    for (var i = 0; i < schema.length; i++) {
        var s = schema[i];
        if (!isObject(s) || typeof s.key !== "string" || s.key === "")
            continue;
        var value = defaults[s.key] !== undefined ? defaults[s.key] : s.defaultValue;
        var entry = {
            type: settingType(s.type, value)
        };
        if (value !== undefined)
            entry["default"] = value;
        if (typeof s.description === "string")
            entry.description = s.description;
        else if (typeof s.label === "string")
            entry.description = s.label;
        out[s.key] = entry;
    }
    for (var k in defaults)
        if (out[k] === undefined)
            out[k] = {
                type: settingType("", defaults[k]),
                "default": defaults[k]
            };
    return out;
}

function omarchy(dirName, m) {
    var problems = [];
    var kinds = Array.isArray(m.kinds) ? m.kinds.filter(function (k) {
        return typeof k === "string";
    }) : [];
    var ep = isObject(m.entryPoints) ? m.entryPoints : {};
    var supported = kinds.filter(function (k) {
        return supportedKinds.indexOf(k) >= 0;
    });
    var unsupported = kinds.filter(function (k) {
        return supportedKinds.indexOf(k) < 0;
    });
    if (kinds.length === 0)
        problems.push("omarchy: kinds must be a non-empty array");
    else if (supported.length === 0)
        problems.push("omarchy: no supported kind (has " + kinds.join(", ") + "; the compat adapter loads bar-widget only)");
    var entry = {};
    for (var i = 0; i < supported.length; i++)
        entry[supported[i]] = ep[omarchyEntryKeys[supported[i]]];
    return {
        compat: "omarchy",
        upstreamId: typeof m.id === "string" ? m.id : "",
        id: dirName,
        problems: problems,
        unsupported: unsupported,
        manifest: {
            schemaVersion: m.schemaVersion,
            id: m.id,
            name: m.name,
            version: m.version,
            description: typeof m.description === "string" ? m.description : "",
            kinds: supported,
            entry: entry,
            settings: omarchySettings(m.barWidget),
            permissions: [],
            provides: []
        }
    };
}

// DMS surfaces: `components` maps surface -> file; a single `component`
// is the surface its `type` implies (PluginService._deriveLegacySurface).
function dmsSurfaces(m) {
    var out = {};
    if (isObject(m.components)) {
        for (var s in m.components)
            if (m.components[s])
                out[s] = m.components[s];
        return out;
    }
    if (m.component) {
        var caps = Array.isArray(m.capabilities) ? m.capabilities : [];
        var surface = "widget";
        if (m.type === "daemon")
            surface = "daemon";
        else if (m.type === "launcher" || caps.indexOf("launcher") >= 0)
            surface = "launcher";
        else if (m.type === "desktop" || m.type === "dash" || m.type === "dashCard")
            surface = m.type;
        out[surface] = m.component;
    }
    return out;
}

var dmsPermissions = {
    "process": "exec",
    "network": "network"
};

function dms(dirName, m) {
    var problems = [];
    var validId = typeof m.id === "string" && dmsIdPattern.test(m.id);
    var id = dmsId(validId ? m.id : dirName);
    if (!validId)
        problems.push("dms: id must match " + dmsIdPattern.source);
    var surfaces = dmsSurfaces(m);
    var names = Object.keys(surfaces);
    var unsupported = names.filter(function (s) {
        return s !== "widget";
    }).map(function (s) {
        return "dms:" + s;
    });
    if (surfaces.widget === undefined)
        problems.push("dms: no bar widget surface (" + (names.length > 0 ? "has " + names.join(", ") : "no component") + "; the compat adapter loads the bar widget only)");
    var perms = typeof m.permissions === "string" ? m.permissions.split(/\s*,\s*/) : (Array.isArray(m.permissions) ? m.permissions : []);
    var mapped = [];
    for (var i = 0; i < perms.length; i++) {
        var p = dmsPermissions[String(perms[i]).trim()];
        if (p && mapped.indexOf(p) < 0)
            mapped.push(p);
    }
    return {
        compat: "dms",
        upstreamId: validId ? m.id : "",
        id: id,
        problems: problems,
        unsupported: unsupported,
        manifest: {
            schemaVersion: 1,
            id: id,
            name: m.name,
            version: m.version,
            description: typeof m.description === "string" ? m.description : "",
            kinds: surfaces.widget !== undefined ? ["bar-widget"] : [],
            entry: surfaces.widget !== undefined ? {
                "bar-widget": stripDotSlash(surfaces.widget)
            } : {},
            settings: {},
            permissions: mapped,
            provides: []
        }
    };
}

// adapt(dirName, manifestText, pluginText) -> { compat, id, manifest, problems, unsupported }
//   manifestText / pluginText: file contents, or null when the file is absent.
//   compat: "" (native), "omarchy" or "dms". id: the registry id.
//   problems: parse/adapter errors; empty means "run the native validation
//   on manifest". manifest.json wins when a directory holds both files.
function adapt(dirName, manifestText, pluginText) {
    var none = {
        compat: "",
        upstreamId: "",
        id: dirName,
        manifest: null,
        problems: [],
        unsupported: []
    };
    if (typeof manifestText === "string") {
        var m;
        try {
            m = JSON.parse(manifestText);
        } catch (e) {
            none.problems = ["manifest.json is not valid JSON: " + e.message];
            return none;
        }
        if (isObject(m) && isObject(m.entryPoints) && m.entry === undefined)
            return omarchy(dirName, m);
        none.manifest = m;
        return none;
    }
    if (typeof pluginText === "string") {
        var p;
        none.compat = "dms";
        none.id = dmsId(dirName);
        try {
            p = JSON.parse(pluginText);
        } catch (e) {
            none.problems = ["plugin.json is not valid JSON: " + e.message];
            return none;
        }
        if (!isObject(p)) {
            none.problems = ["plugin.json is not a JSON object"];
            return none;
        }
        return dms(dirName, p);
    }
    none.problems = ["manifest.json missing or unreadable"];
    return none;
}
