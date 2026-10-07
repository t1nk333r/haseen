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
// Omarchy services and panels use the same registry as native plugins. DMS
// bar widgets become bar-widget entries, DMS daemons service entries and DMS
// desktop widgets overlay entries (Compat/DmsDesktopHost.qml puts them on the
// desktop layer); the other DMS surfaces stay unsupported. DMS
// `dependencies` become requires.tools, which the shell gates on
// (Haseen/Requires.js).
var supportedKinds = ["bar-widget", "service", "panel", "overlay"];

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
// Haseen/Requires.js commandPattern: a name the requirement probe can look up.
var commandPattern = /^[A-Za-z0-9][A-Za-z0-9._+-]*$/;

function isObject(v) {
    return v !== null && typeof v === "object" && !Array.isArray(v);
}

// Upstream requirement lists -> native requires.tools. DMS `dependencies`
// (and its deprecated alias `requires`) are "required system tools", in
// practice commands and package names mixed, so they become tools, not
// strict bins. An entry that is not a plain name ("gpu screen recorder", a
// version range) cannot be probed and is dropped. Undefined when nothing is
// left, so the manifest has no `requires`.
function toolsFrom(lists) {
    var tools = [];
    for (var i = 0; i < lists.length; i++)
        if (Array.isArray(lists[i]))
            for (var j = 0; j < lists[i].length; j++) {
                var name = typeof lists[i][j] === "string" ? lists[i][j].trim() : "";
                if (commandPattern.test(name) && tools.indexOf(name) < 0)
                    tools.push(name);
            }
    return tools.length > 0 ? {
        tools: tools
    } : undefined;
}

// Omarchy's manifest has no requirement field and its registry ignores
// unknown keys, so a plugin may carry haseen's `requires` object as is; a
// bare array is read like DMS's list, and null as none.
function omarchyRequires(r) {
    return Array.isArray(r) ? toolsFrom([r]) : (r === null ? undefined : r);
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

// Omarchy section defaults/schema -> native setting descriptors.
function omarchySectionSettings(bw) {
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

// Installed plugins use three schema forms: section defaults/schema, a flat
// native-like top-level settings map, or settings.defaults/settings.schema.
// Bar-specific descriptors win when the manifest declares both.
function omarchySettings(m) {
    var out = omarchySectionSettings(m);
    for (var section of [m.service, m.panel, m.overlay])
        Object.assign(out, omarchySectionSettings(section));
    var top = isObject(m.settings) ? m.settings : {};
    if (isObject(top.defaults) || Array.isArray(top.schema)) {
        Object.assign(out, omarchySectionSettings(top));
    } else {
        for (var key in top) {
            var descriptor = top[key];
            var hasDefault = isObject(descriptor) && descriptor["default"] !== undefined;
            var value = hasDefault ? descriptor["default"] : (isObject(descriptor) ? undefined : descriptor);
            var entry = {type: settingType(isObject(descriptor) ? descriptor.type : "", value)};
            if (value !== undefined)
                entry["default"] = value;
            if (isObject(descriptor) && typeof descriptor.description === "string")
                entry.description = descriptor.description;
            out[key] = entry;
        }
    }
    return Object.assign(out, omarchySectionSettings(m.barWidget));
}

// Omarchy permits a single-segment id (for example omaconnect). Namespace it
// for haseen's registry while retaining upstreamId for service lookups; never
// rename or modify the directory in the read-only Omarchy source.
function omarchyId(name) {
    return /^[a-z0-9-]+$/.test(String(name)) ? "omarchy." + name : name;
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
        problems.push("omarchy: no supported kind (has " + kinds.join(", ") + "; supported: " + supportedKinds.join(", ") + ")");
    var entry = {};
    for (var i = 0; i < supported.length; i++)
        entry[supported[i]] = ep[omarchyEntryKeys[supported[i]]];
    return {
        compat: "omarchy",
        upstreamId: typeof m.id === "string" ? m.id : "",
        id: omarchyId(dirName),
        problems: problems,
        unsupported: unsupported,
        manifest: {
            schemaVersion: m.schemaVersion,
            id: typeof m.id === "string" ? omarchyId(m.id) : m.id,
            name: m.name,
            version: m.version,
            description: typeof m.description === "string" ? m.description : "",
            kinds: supported,
            entry: entry,
            settings: omarchySettings(m),
            permissions: [],
            provides: [],
            requires: omarchyRequires(m.requires)
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

// DMS surface -> haseen kind, for the surfaces the compat hosts load. A
// desktop widget is a layer surface the host owns on every screen, which is
// what the overlay kind means (architecture 5.2).
var dmsKinds = {
    "widget": "bar-widget",
    "daemon": "service",
    "desktop": "overlay"
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
        return dmsKinds[s] === undefined;
    }).map(function (s) {
        return "dms:" + s;
    });
    var kinds = [];
    var entry = {};
    for (var s in dmsKinds)
        if (surfaces[s] !== undefined) {
            kinds.push(dmsKinds[s]);
            entry[dmsKinds[s]] = stripDotSlash(surfaces[s]);
        }
    if (kinds.length === 0)
        problems.push("dms: no bar widget, daemon or desktop surface (" + (names.length > 0 ? "has " + names.join(", ") : "no component") + "; the compat adapter loads bar widgets, daemons and desktop widgets only)");
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
            kinds: kinds,
            entry: entry,
            settings: {},
            permissions: mapped,
            provides: [],
            requires: toolsFrom([m.dependencies, m.requires])
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
