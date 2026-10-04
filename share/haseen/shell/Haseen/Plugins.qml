pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../Compat/Manifest.js" as CompatManifest

// Plugin registry (architecture 5.2). Scans ~/.config/haseen/plugins/ and the
// built-in shell/plugins/ (directory watch, no polling), reads every
// manifest.json and validates the required fields. The directory name is the
// plugin id; when both directories hold the same id the user copy wins, even
// if it is broken, so an override never silently falls back.
//
// Compat (architecture 5.4): ~/.config/omarchy/plugins/ and
// ~/.config/DankMaterialShell/plugins/ are scanned read-only after those two.
// Compat/Manifest.js adapts Omarchy manifests and DMS plugin.json files to
// the native shape; their bar widgets load through a Compat/ host.
//
// The full schema check lives in `haseen plugin validate`; this one only
// keeps a malformed manifest from reaching a Loader.
Singleton {
    id: root

    readonly property var kinds: ["bar-widget", "panel", "service", "launcher-provider", "overlay"]
    readonly property var idPattern: /^[a-z0-9-]+(\.[a-z0-9-]+)+$/

    // id -> { id, name, version, description, kinds, entry, settings,
    //         permissions, provides, dir, origin, overrides, valid, errors,
    //         compat ("" | "omarchy" | "dms"), upstreamId (the id in the
    //         upstream manifest), unsupported (kinds not loaded) }
    property var registry: ({})
    // [{ id, message }] for every invalid manifest and load failure.
    property var errors: []
    // True once every directory is listed and every manifest answered.
    readonly property bool ready: _listed && _pending === 0

    // role -> { id, instance } for loaded plugins that declare `provides`.
    property var roles: ({})

    property var _dirs: []
    property var _texts: ({})
    property int _pending: 0
    property bool _listed: false
    readonly property string omarchyPlugins: Paths.configHome + "/omarchy/plugins"
    readonly property string dmsPlugins: Paths.configHome + "/DankMaterialShell/plugins"
    property var _runtimeErrors: []
    property var _warned: ({})

    readonly property var panelIds: Object.keys(registry).filter(id => registry[id].valid && registry[id].kinds.indexOf("panel") >= 0)

    // URL the hosts load: the plugin's own file, or for an adapted plugin the
    // Compat host that provides the upstream contract around entryUrl().
    function componentUrl(id: string, kind: string): string {
        const url = entryUrl(id, kind);
        const rec = registry[id];
        if (url === "" || rec.compat === "")
            return url;
        return Paths.fileUrl(Paths.shellDir + "/Compat/" + (rec.compat === "omarchy" ? "OmarchyHost.qml" : "DmsHost.qml"));
    }

    function entryUrl(id: string, kind: string): string {
        const rec = registry[id];
        if (!rec || !rec.valid || rec.kinds.indexOf(kind) < 0)
            return "";
        return Paths.fileUrl(rec.dir + "/" + rec.entry[kind]);
    }

    // Manifest defaults overlaid with shell.json plugins.<id>.settings.
    function settingsFor(id: string): var {
        const rec = registry[id];
        const out = {};
        if (rec)
            for (const k in rec.settings)
                if (rec.settings[k] && rec.settings[k].default !== undefined)
                    out[k] = rec.settings[k].default;
        const user = Config.pluginEntry(id).settings;
        if (user && typeof user === "object" && !Array.isArray(user))
            for (const k in user)
                out[k] = user[k];
        return out;
    }

    function provider(role: string): string {
        for (const id in registry) {
            const rec = registry[id];
            if (rec.valid && rec.provides.indexOf(role) >= 0 && Config.isEnabled(id))
                return id;
        }
        return "";
    }

    // One log line per key for the lifetime of the shell.
    function warnOnce(key: string, message: string): void {
        if (_warned[key])
            return;
        const w = Object.assign({}, _warned);
        w[key] = true;
        _warned = w;
        console.warn("haseen:", message);
    }

    // Called by hosts once the registry is ready and an id still resolves to nothing.
    function noteMissing(id: string, kind: string): void {
        if (!ready)
            return;
        const rec = registry[id];
        if (!rec)
            warnOnce("unknown:" + id, "unknown plugin id '" + id + "', skipped");
        else if (!rec.valid)
            warnOnce("invalid:" + id, "plugin '" + id + "' is invalid, skipped: " + rec.errors.join("; "));
        else if (rec.kinds.indexOf(kind) < 0)
            warnOnce("kind:" + id + ":" + kind, "plugin '" + id + "' has no '" + kind + "' entry, skipped");
    }

    // A failure every bar reports once per screen is recorded once.
    function reportError(id: string, message: string): void {
        if (_runtimeErrors.some(e => e.id === id && e.message === message))
            return;
        _runtimeErrors = _runtimeErrors.concat([
            {
                id: id,
                message: message
            }
        ]);
        // Same key as onReadyChanged, so an error is logged once either way.
        warnOnce("err:" + id + ":" + message, "plugin " + id + ": " + message);
        _rebuild();
    }

    function registerRole(role: string, id: string, instance: var): void {
        const r = Object.assign({}, roles);
        r[role] = {
            id: id,
            instance: instance
        };
        roles = r;
    }

    function unregisterRole(role: string, instance: var): void {
        if (!roles[role] || roles[role].instance !== instance)
            return;
        const r = Object.assign({}, roles);
        delete r[role];
        roles = r;
    }

    // Calls fn on the loaded instance providing role. False when nobody answers.
    function callRole(role: string, fn: string, args: var): bool {
        const entry = roles[role];
        if (!entry || !entry.instance || typeof entry.instance[fn] !== "function")
            return false;
        entry.instance[fn].apply(entry.instance, args || []);
        return true;
    }

    // JSON for `shell plugins` over IPC.
    function describe(): string {
        const list = Object.keys(registry).sort().map(id => {
            const r = registry[id];
            return {
                id: id,
                name: r.name,
                version: r.version,
                origin: r.origin,
                compat: r.compat,
                unsupported: r.unsupported,
                overrides: r.overrides,
                kinds: r.kinds,
                provides: r.provides,
                permissions: r.permissions,
                valid: r.valid,
                enabled: Config.isEnabled(id),
                listed: Config.isListed(id),
                errors: r.errors
            };
        });
        const roleMap = {};
        for (const role in roles)
            roleMap[role] = roles[role].id;
        return JSON.stringify({
            ready: ready,
            plugins: list,
            roles: roleMap,
            errors: errors
        });
    }

    function validate(dirName: string, m: var): var {
        const errs = [];
        if (!m || typeof m !== "object" || Array.isArray(m))
            return ["manifest is not a JSON object"];
        if (m.schemaVersion !== 1)
            errs.push("schemaVersion must be 1");
        if (typeof m.id !== "string" || !idPattern.test(m.id))
            errs.push("id must match " + idPattern.source);
        else if (m.id !== dirName)
            errs.push("id '" + m.id + "' does not match its directory '" + dirName + "'");
        if (typeof m.name !== "string" || m.name.length === 0)
            errs.push("name is required");
        if (typeof m.version !== "string" || m.version.length === 0)
            errs.push("version is required");
        if (!Array.isArray(m.kinds) || m.kinds.length === 0) {
            errs.push("kinds must be a non-empty array");
        } else {
            const entry = (m.entry && typeof m.entry === "object") ? m.entry : {};
            for (const k of m.kinds) {
                if (kinds.indexOf(k) < 0)
                    errs.push("unknown kind '" + k + "'");
                else if (typeof entry[k] !== "string" || !/\.qml$/.test(entry[k]) || entry[k].startsWith("/") || entry[k].split("/").indexOf("..") >= 0)
                    errs.push("kind '" + k + "' needs a relative .qml entry");
            }
        }
        if (m.provides !== undefined && !(Array.isArray(m.provides) && m.provides.every(p => typeof p === "string")))
            errs.push("provides must be an array of strings");
        return errs;
    }

    function _scheduleRescan(): void {
        Qt.callLater(_rescan);
    }

    function _rescan(): void {
        const builtinDone = builtinDirs.status === FolderListModel.Ready && builtinDirs.count > 0;
        if (!builtinDone || !userSource.done || !omarchySource.done || !dmsSource.done)
            return;
        const dirs = [];
        const add = (model, base, origin) => {
            for (let i = 0; i < model.count; i++)
                dirs.push({
                    name: model.get(i, "fileName"),
                    dir: base + "/" + model.get(i, "fileName"),
                    origin: origin
                });
        };
        // Search order: user, built-in, then the read-only compat dirs.
        if (userSource.model)
            add(userSource.model, userSource.path, "user");
        add(builtinDirs, Paths.builtinPlugins, "builtin");
        if (omarchySource.model)
            add(omarchySource.model, omarchySource.path, "omarchy");
        if (dmsSource.model)
            add(dmsSource.model, dmsSource.path, "dms");
        // Order matters: `ready` must only turn true after the registry holds
        // every manifest, or hosts would report known ids as unknown.
        const same = dirs.length === _dirs.length && dirs.every((d, i) => d.dir === _dirs[i].dir);
        if (!same) {
            const texts = {};
            for (const d of dirs)
                if (_texts[d.dir] !== undefined)
                    texts[d.dir] = _texts[d.dir];
            _texts = texts;
            _pending = dirs.filter(d => texts[d.dir] === undefined).length;
            _dirs = dirs;
            _rebuild();
        }
        _listed = true;
    }

    function _setText(dir: string, text: var): void {
        const first = _texts[dir] === undefined;
        const t = Object.assign({}, _texts);
        t[dir] = text;
        _texts = t;
        _rebuild();
        if (first && _pending > 0)
            _pending -= 1;
    }

    function _rebuild(): void {
        const reg = {};
        const errs = [];
        for (const d of _dirs) {
            const text = _texts[d.dir];
            if (text === undefined)
                continue;
            const a = CompatManifest.adapt(d.name, text.manifest, text.plugin);
            if (reg[a.id]) {
                reg[a.id].overrides = true;
                continue;
            }
            const m = a.manifest;
            const problems = a.problems.length > 0 ? a.problems : validate(a.id, m);
            const ok = problems.length === 0;
            reg[a.id] = {
                id: a.id,
                name: ok ? m.name : a.id,
                version: ok ? m.version : "",
                description: ok && typeof m.description === "string" ? m.description : "",
                kinds: ok ? m.kinds : [],
                entry: ok ? m.entry : {},
                settings: ok && m.settings && typeof m.settings === "object" ? m.settings : {},
                permissions: ok && Array.isArray(m.permissions) ? m.permissions : [],
                provides: ok && Array.isArray(m.provides) ? m.provides : [],
                dir: d.dir,
                origin: d.origin,
                compat: a.compat,
                upstreamId: a.upstreamId,
                unsupported: a.unsupported,
                overrides: false,
                valid: ok,
                errors: problems
            };
            for (const p of problems)
                errs.push({
                    id: a.id,
                    message: p
                });
        }
        for (const e of _runtimeErrors) {
            errs.push(e);
            if (reg[e.id])
                reg[e.id].errors = reg[e.id].errors.concat([e.message]);
        }
        registry = reg;
        errors = errs;
    }

    onReadyChanged: {
        if (!ready)
            return;
        for (const e of errors)
            warnOnce("err:" + e.id + ":" + e.message, "plugin " + e.id + ": " + e.message);
    }

    // A plugin directory that may not exist. FolderListModel falls back to the
    // working directory for a missing folder, so the model is only created
    // once a FileView probe (NotAFile = a directory) says it exists. A
    // directory created later is picked up by `haseen shell ipc shell reload`.
    component OptionalDir: Scope {
        id: source

        required property string path
        // 1 directory, -1 absent, 0 unknown.
        property int presence: 0
        readonly property var model: presence === 1 ? loader.item : null
        readonly property bool done: presence === -1 || (model !== null && model.status === FolderListModel.Ready)

        signal listingChanged

        FileView {
            path: source.path
            printErrors: false
            onLoaded: {
                source.presence = -1;
                source.listingChanged();
            }
            onLoadFailed: error => {
                source.presence = error === FileViewError.NotAFile ? 1 : -1;
                source.listingChanged();
            }
        }

        LazyLoader {
            id: loader
            active: source.presence === 1

            FolderListModel {
                folder: Paths.fileUrl(source.path)
                showDirs: true
                showFiles: false
                showDotAndDotDot: false
                sortField: FolderListModel.Name
                onStatusChanged: source.listingChanged()
                onCountChanged: source.listingChanged()
            }
        }
    }

    OptionalDir {
        id: userSource
        path: Paths.userPlugins
        onListingChanged: root._scheduleRescan()
    }

    OptionalDir {
        id: omarchySource
        path: root.omarchyPlugins
        onListingChanged: root._scheduleRescan()
    }

    OptionalDir {
        id: dmsSource
        path: root.dmsPlugins
        onListingChanged: root._scheduleRescan()
    }

    FolderListModel {
        id: builtinDirs
        folder: Paths.fileUrl(Paths.builtinPlugins)
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
        onStatusChanged: root._scheduleRescan()
        onCountChanged: root._scheduleRescan()
    }

    // Native and Omarchy plugins have manifest.json, DMS plugins plugin.json;
    // a user directory may hold either. undefined = not answered yet,
    // null = absent. _setText runs once both files answered.
    Instantiator {
        model: root._dirs
        delegate: Scope {
            id: probe

            required property var modelData
            readonly property bool wantsManifest: modelData.origin !== "dms"
            readonly property bool wantsPlugin: modelData.origin === "user" || modelData.origin === "dms"
            property var manifest: wantsManifest ? undefined : null
            property var plugin: wantsPlugin ? undefined : null

            function report(): void {
                if (manifest !== undefined && plugin !== undefined)
                    root._setText(modelData.dir, {
                        manifest: manifest,
                        plugin: plugin
                    });
            }

            FileView {
                path: probe.wantsManifest ? probe.modelData.dir + "/manifest.json" : ""
                watchChanges: probe.wantsManifest
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    probe.manifest = text();
                    probe.report();
                }
                onLoadFailed: {
                    probe.manifest = null;
                    probe.report();
                }
            }

            FileView {
                path: probe.wantsPlugin ? probe.modelData.dir + "/plugin.json" : ""
                watchChanges: probe.wantsPlugin
                printErrors: false
                onFileChanged: reload()
                onLoaded: {
                    probe.plugin = text();
                    probe.report();
                }
                onLoadFailed: {
                    probe.plugin = null;
                    probe.report();
                }
            }
        }
    }
}
