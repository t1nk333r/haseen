pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import "../Compat/Manifest.js" as CompatManifest
import "Requires.js" as Requires

// Plugin registry (architecture 5.2). Scans ~/.config/haseen/plugins/ and the
// built-in shell/plugins/ (directory watch, no polling), reads every
// manifest.json and validates the required fields. The directory name is the
// plugin id; when both directories hold the same id the user copy wins, even
// if it is broken, so an override never silently falls back.
//
// Compat (architecture 5.4): ~/.config/omarchy/plugins/ and
// ~/.config/DankMaterialShell/plugins/ are scanned read-only after those two.
// Compat/Manifest.js adapts Omarchy manifests and DMS plugin.json files;
// visual entries and services load through kind-specific Compat hosts.
//
// The full schema check lives in `haseen plugin validate`; this one only
// keeps a malformed manifest from reaching a Loader.
//
// Safe mode (plan 061): while $HASEEN_USER_STATE/safe-mode exists, every
// plugin that is not built in is held back: entryUrl() answers "" and
// Config.isEnabled() false, so hosts unload it at once, and a user copy
// that overrides a built-in id gives way to the built-in. Removing the file
// brings them back. `haseen shell recover safe-mode on|off` writes it.
//
// Requirements (plan 064): a manifest's `requires` (commands, tools, layers,
// a minimum haseen version; DMS `dependencies` map to tools) is probed in
// one bash run per new set of facts, never polled. A plugin is not valid
// while a fact is unknown (`checking`, silent) or a requirement is unmet
// (`unmet`: in errors, logged, and one notification when a host asks for
// it). The facts are probed again when a plugin directory appears or goes,
// and on `haseen shell ipc shell reload`.
Singleton {
    id: root

    readonly property var kinds: ["bar-widget", "panel", "service", "launcher-provider", "overlay"]
    readonly property var idPattern: /^[a-z0-9-]+(\.[a-z0-9-]+)+$/

    // id -> { id, name, version, description, kinds, entry, settings,
    //         permissions, provides, dir, origin, overrides, valid, errors,
    //         compat ("" | "omarchy" | "dms"), upstreamId (the id in the
    //         upstream manifest), unsupported (kinds not loaded),
    //         requires (the manifest's), unmet (messages), checking }
    property var registry: ({})
    // [{ id, message }] for every invalid manifest, unmet requirement and
    // load failure.
    property var errors: []
    // True once every directory is listed, every manifest answered and every
    // requirement fact probed.
    readonly property bool ready: _listed && _pending === 0 && _wanted.length === 0

    // role -> { id, instance } for loaded plugins that declare `provides`.
    property var roles: ({})

    property var _dirs: []
    property var _texts: ({})
    property int _pending: 0
    property bool _listed: false
    readonly property string omarchyPlugins: Paths.configHome + "/omarchy/plugins"
    readonly property string dmsPlugins: Paths.configHome + "/DankMaterialShell/plugins"
    property var _runtimeErrors: []
    // Requirement facts (Requires.js keys): "bin:x"/"layer:y" -> bool,
    // "version" -> installed version text. _wanted: keys still to probe;
    // _asking: the keys of the running probe.
    property var _facts: ({})
    property var _wanted: []
    property var _asking: []

    // Safe mode: the flag file exists. Its JSON body ({ reason, since }) is
    // shown by `shell plugins`; an unreadable body still means "on".
    readonly property bool safeMode: safeModeFile.on
    readonly property var safeModeInfo: safeModeFile.info
    property var _warned: ({})

    readonly property var panelIds: Object.keys(registry).filter(id => registry[id].valid && registry[id].kinds.indexOf("panel") >= 0)

    // Service and overlay companions are shared across all screens. A listed
    // legacy widget can depend on both, even when only the widget is
    // configured: an Omarchy widget on its service, a DMS bar pill on the
    // daemon or desktop surface of the same plugin (DMS loads every surface
    // of an enabled plugin).
    readonly property var serviceIds: {
        const ids = Config.services.filter(id => Config.isEnabled(id));
        for (const id of Config.section("left").concat(Config.section("center"), Config.section("right"))) {
            const rec = registry[id];
            if (rec && rec.valid && rec.compat !== "" && Config.isEnabled(id)
                    && (rec.kinds.indexOf("service") >= 0 || rec.kinds.indexOf("overlay") >= 0) && ids.indexOf(id) < 0)
                ids.push(id);
        }
        return [...new Set(ids)];
    }

    // Stable string model keys retain distinct service/overlay instances for
    // a plugin that supplies both. Objects here would be recreated on registry
    // updates and spuriously restart unrelated background services.
    readonly property var serviceKeys: {
        const keys = [];
        for (const id of serviceIds) {
            const rec = registry[id];
            if (rec && rec.valid && rec.compat !== "") {
                for (const kind of ["service", "overlay"])
                    if (rec.kinds.indexOf(kind) >= 0)
                        keys.push(kind + ":" + id);
            } else {
                keys.push(serviceKind(id) + ":" + id);
            }
        }
        return keys;
    }

    function serviceKind(id: string): string {
        const rec = registry[id];
        return rec && rec.kinds.indexOf("service") < 0 && rec.kinds.indexOf("overlay") >= 0 ? "overlay" : "service";
    }

    function resolveId(id: string): string {
        if (registry[id])
            return id;
        for (const key in registry)
            if (registry[key].compat !== "" && registry[key].upstreamId === id)
                return key;
        return id;
    }

    // URL the hosts load: the plugin's own file, or for an adapted plugin the
    // Compat host that provides the upstream contract around entryUrl().
    function componentUrl(id: string, kind: string): string {
        const url = entryUrl(id, kind);
        const rec = registry[id];
        if (url === "" || rec.compat === "")
            return url;
        if (rec.compat === "omarchy") {
            const file = kind === "service" || kind === "overlay" ? "OmarchyServiceHost.qml" : "OmarchyHost.qml";
            return Paths.fileUrl(Paths.shellDir + "/Compat/" + file);
        }
        const dmsHosts = {
            "service": "DmsServiceHost.qml",
            "overlay": "DmsDesktopHost.qml"
        };
        return Paths.fileUrl(Paths.shellDir + "/Compat/" + (dmsHosts[kind] || "DmsHost.qml"));
    }

    function entryUrl(id: string, kind: string): string {
        const rec = registry[id];
        if (!rec || !rec.valid || held(id) || rec.kinds.indexOf(kind) < 0)
            return "";
        return Paths.fileUrl(rec.dir + "/" + rec.entry[kind]);
    }

    // True for a plugin that safe mode keeps from loading: anything not
    // built in (user, user:omarchy, user:dms, omarchy, dms).
    function held(id: string): bool {
        const rec = registry[id];
        return safeMode && rec !== undefined && rec.origin !== "builtin";
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
        else if (held(id))
            warnOnce("held:" + id, "safe mode: plugin '" + id + "' (" + rec.origin + ") held back");
        else if (rec.checking)
            return;
        else if (rec.unmet.length > 0)
            _refuse(rec);
        else if (!rec.valid)
            warnOnce("invalid:" + id, "plugin '" + id + "' is invalid, skipped: " + rec.errors.join("; "));
        else if (rec.kinds.indexOf(kind) < 0)
            warnOnce("kind:" + id + ":" + kind, "plugin '" + id + "' has no '" + kind + "' entry, skipped");
    }

    // An enabled plugin whose requirements are unmet: logged and notified
    // once for the life of the shell. Critical, so it stays until read, as
    // a refused DMS startup check does (Compat/DmsStartupGate.qml).
    function _refuse(rec: var): void {
        if (_warned["unmet:" + rec.id])
            return;
        warnOnce("unmet:" + rec.id, "plugin '" + rec.id + "' not loaded: " + rec.unmet.join("; "));
        Quickshell.execDetached(["notify-send", "--app-name=haseen", "--urgency=critical", rec.name + " not loaded", rec.unmet.join("\n") + "\n\nInstall what it needs, then reload the shell (haseen shell ipc shell reload)."]);
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
                held: held(id),
                listed: Config.isListed(id),
                errors: r.errors,
                requires: r.requires,
                unmet: r.unmet
            };
        });
        const roleMap = {};
        for (const role in roles)
            roleMap[role] = roles[role].id;
        return JSON.stringify({
            ready: ready,
            safeMode: safeMode ? Object.assign({
                on: true
            }, safeModeInfo) : {
                on: false
            },
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
        return errs.concat(Requires.problems(m.requires));
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
            // A new plugin set may need tools installed since the last probe.
            _facts = {};
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
        const wanted = [];
        // In safe mode a user copy of a built-in id is skipped, so the
        // built-in behind it loads instead of nothing.
        const builtins = safeMode ? _dirs.filter(d => d.origin === "builtin").map(d => d.name) : [];
        for (const d of _dirs) {
            if (d.origin === "user" && builtins.indexOf(d.name) >= 0)
                continue;
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
            const gate = ok ? Requires.unmet(m.requires, _facts) : {
                pending: false,
                messages: []
            };
            if (ok)
                for (const k of Requires.keys(m.requires))
                    if (_facts[k] === undefined && wanted.indexOf(k) < 0)
                        wanted.push(k);
            const upstreamManifest = ok && a.compat !== ""
                ? JSON.parse(a.compat === "dms" ? text.plugin : text.manifest) : null;
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
                upstreamManifest: upstreamManifest,
                unsupported: a.unsupported,
                overrides: false,
                valid: ok && !gate.pending && gate.messages.length === 0,
                errors: problems.concat(gate.messages),
                requires: ok && m.requires ? m.requires : {},
                unmet: gate.messages,
                checking: gate.pending
            };
            for (const p of problems.concat(gate.messages))
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
        _wanted = wanted;
        if (wanted.length > 0)
            Qt.callLater(_probe);
    }

    function _probe(): void {
        if (requirementProbe.running || _wanted.length === 0)
            return;
        _asking = _wanted;
        requirementProbe.command = ["bash", "-c", requirementProbe.script, "probe", Paths.haseenPath + "/VERSION"].concat(_asking);
        requirementProbe.running = true;
    }

    // Every asked key gets an answer, so a failed probe refuses the plugins
    // that asked instead of leaving the registry not ready.
    function _answer(text: string): void {
        if (_asking.length === 0)
            return;
        const lines = text.split("\n");
        const facts = Object.assign({}, _facts);
        for (const k of _asking) {
            if (k === "version") {
                const line = lines.find(l => l.startsWith("version:"));
                facts.version = line ? line.slice(8).trim() : "";
            } else {
                facts[k] = lines.indexOf(k) >= 0;
            }
        }
        _asking = [];
        _facts = facts;
        _rebuild();
    }

    // One run answers every key, as plugin_unmet in shell/lib/plugin.sh does:
    // bin = a command on PATH; tool = a command, an installed package or
    // provider (pacman -T), or a name no repository knows (unknowable, so
    // met); layer = its applied state file (layers.sh layer_is_applied);
    // version = the VERSION text.
    Process {
        id: requirementProbe

        readonly property string script: ["v=$1; shift", "for k; do", "    n=${k#*:}", "    case $k in",
            "    bin:*) if type -P \"$n\" >/dev/null; then echo \"$k\"; fi ;;",
            "    tool:*) if type -P \"$n\" >/dev/null || pacman -T \"$n\" >/dev/null 2>&1 || ! pacman -Si \"$n\" >/dev/null 2>&1; then echo \"$k\"; fi ;;",
            "    layer:*) if [[ -r ${HASEEN_SYSROOT:-}${HASEEN_STATE_DIR:-/var/lib/haseen}/layers/$n ]]; then echo \"$k\"; fi ;;",
            "    version) echo \"version:$(cat -- \"$v\" 2>/dev/null)\" ;;", "    esac", "done"].join("\n")

        stdout: StdioCollector {
            id: probeOutput
        }
        onExited: root._answer(probeOutput.text)
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!requirementProbe.running)
                        root._answer("");
                });
        }
    }

    onReadyChanged: {
        if (!ready)
            return;
        for (const e of errors)
            warnOnce("err:" + e.id + ":" + e.message, "plugin " + e.id + ": " + e.message);
    }

    onSafeModeChanged: {
        console.warn("haseen: safe mode", safeMode ? "on: plugins that are not built in are held back" : "off");
        _rebuild();
    }

    FileView {
        id: safeModeFile

        property bool on: false
        property var info: ({})

        // The parent directory must exist for the watch to see the file
        // appear; `haseen shell run` creates it.
        path: Paths.userState + "/safe-mode"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let parsed = {};
            try {
                parsed = JSON.parse(text());
            } catch (e) {}
            info = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? {
                reason: typeof parsed.reason === "string" ? parsed.reason : "",
                since: typeof parsed.since === "string" ? parsed.since : ""
            } : {};
            on = true;
        }
        onLoadFailed: {
            on = false;
            info = {};
        }
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
