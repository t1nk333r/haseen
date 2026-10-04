pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

// Plugin registry (architecture 5.2). Scans ~/.config/haseen/plugins/ and the
// built-in shell/plugins/ (directory watch, no polling), reads every
// manifest.json and validates the required fields. The directory name is the
// plugin id; when both directories hold the same id the user copy wins, even
// if it is broken, so an override never silently falls back.
//
// The full schema check lives in `haseen plugin validate`; this one only
// keeps a malformed manifest from reaching a Loader.
Singleton {
    id: root

    readonly property var kinds: ["bar-widget", "panel", "service", "launcher-provider", "overlay"]
    readonly property var idPattern: /^[a-z0-9-]+(\.[a-z0-9-]+)+$/

    // id -> { id, name, version, description, kinds, entry, settings,
    //         permissions, provides, dir, origin, overrides, valid, errors }
    property var registry: ({})
    // [{ id, message }] for every invalid manifest and load failure.
    property var errors: []
    // True once both directories are listed and every manifest answered.
    readonly property bool ready: _listed && _pending === 0

    // role -> { id, instance } for loaded plugins that declare `provides`.
    property var roles: ({})

    property var _dirs: []
    property var _texts: ({})
    property int _pending: 0
    property bool _listed: false
    // 1 when ~/.config/haseen/plugins is a directory, -1 when absent, 0 unknown.
    // FolderListModel falls back to the working directory for a missing
    // folder, so it is only created once the directory is known to exist.
    // A plugins directory created later is picked up by `haseen shell ipc shell reload`.
    property int _userDir: 0
    property var _runtimeErrors: []
    property var _warned: ({})

    readonly property var panelIds: Object.keys(registry).filter(id => registry[id].valid && registry[id].kinds.indexOf("panel") >= 0)

    function componentUrl(id: string, kind: string): string {
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

    function reportError(id: string, message: string): void {
        _runtimeErrors = _runtimeErrors.concat([
            {
                id: id,
                message: message
            }
        ]);
        console.warn("haseen: plugin", id + ":", message);
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
        const user = userLoader.item;
        const builtinDone = builtinDirs.status === FolderListModel.Ready && builtinDirs.count > 0;
        const userDone = _userDir === -1 || (_userDir === 1 && user !== null && user.status === FolderListModel.Ready);
        if (!builtinDone || !userDone)
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
        if (_userDir === 1)
            add(user, Paths.userPlugins, "user");
        add(builtinDirs, Paths.builtinPlugins, "builtin");
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
            if (reg[d.name]) {
                if (reg[d.name].origin === "user")
                    reg[d.name].overrides = true;
                continue;
            }
            let m = null;
            let problems = [];
            if (text === null) {
                problems = ["manifest.json missing or unreadable"];
            } else {
                try {
                    m = JSON.parse(text);
                    problems = validate(d.name, m);
                } catch (e) {
                    problems = ["manifest.json is not valid JSON: " + e.message];
                }
            }
            const ok = problems.length === 0;
            reg[d.name] = {
                id: d.name,
                name: ok ? m.name : d.name,
                version: ok ? m.version : "",
                description: ok && typeof m.description === "string" ? m.description : "",
                kinds: ok ? m.kinds : [],
                entry: ok ? m.entry : {},
                settings: ok && m.settings && typeof m.settings === "object" ? m.settings : {},
                permissions: ok && Array.isArray(m.permissions) ? m.permissions : [],
                provides: ok && Array.isArray(m.provides) ? m.provides : [],
                dir: d.dir,
                origin: d.origin,
                overrides: false,
                valid: ok,
                errors: problems
            };
            for (const p of problems)
                errs.push({
                    id: d.name,
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

    FileView {
        path: Paths.userPlugins
        printErrors: false
        onLoaded: {
            root._userDir = -1;
            root._scheduleRescan();
        }
        onLoadFailed: error => {
            root._userDir = error === FileViewError.NotAFile ? 1 : -1;
            root._scheduleRescan();
        }
    }

    LazyLoader {
        id: userLoader
        active: root._userDir === 1

        FolderListModel {
            folder: Paths.fileUrl(Paths.userPlugins)
            showDirs: true
            showFiles: false
            showDotAndDotDot: false
            sortField: FolderListModel.Name
            onStatusChanged: root._scheduleRescan()
            onCountChanged: root._scheduleRescan()
        }
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

    Instantiator {
        model: root._dirs
        delegate: FileView {
            required property var modelData
            path: modelData.dir + "/manifest.json"
            watchChanges: true
            printErrors: false
            onFileChanged: reload()
            onLoaded: root._setText(modelData.dir, text())
            onLoadFailed: root._setText(modelData.dir, null)
        }
    }
}
