pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Host.js" as Host

// Haseen owns all providers and persistence; legacy names are routing aliases,
// never an Omarchy shell/configuration dependency.
// Shell/registry API contracts adapted from Omarchy (MIT).
// Copyright (c) David Heinemeier Hansson
QtObject {
    id: runtime
    property var nativeShell: null
    property var services: ({})
    property var overlays: ({})
    property var widgets: ({})
    property var serviceOwners: ({})
    property var activePopout: null
    property var _writes: []
    property var _writing: null
    property var _pendingPanels: ({})
    // url -> does that panel entry build its own window. Mutated in place:
    // the answer never changes while a file is loaded, and a new object here
    // would re-run every binding that asked.
    property var _panelSurfaces: ({})
    readonly property var legacyRoles: ({
        "omarchy.lock": "lock", "omarchy.idle": "idle", "omarchy.osd": "osd",
        "omarchy.launcher": "launcher", "omarchy.menu": "menu", "omarchy.notifications": "notifications",
        "omarchy.clipboard": "clipboard", "omarchy.calendar": "calendar", "omarchy.bluetooth": "bluetooth",
        "omarchy.network": "network", "omarchy.screensaver": "screensaver"
    })
    readonly property var lockProvider: roleService("lock")
    readonly property var screensaverProvider: roleService("screensaver")
    readonly property var idleProvider: roleService("idle")
    property QtObject legacyLock: QtObject {
        readonly property bool locked: runtime.lockProvider ? runtime.lockProvider.locked === true : false
    }
    property QtObject legacyIdle: QtObject {
        readonly property bool screensaverActive: runtime.screensaverProvider ? runtime.screensaverProvider.active === true : false
        readonly property bool screensaverStartedThisCycle: runtime.idleProvider ? runtime.idleProvider.screensaverStartedThisCycle === true : false
        readonly property int screensaverWindowCount: runtime.screensaverProvider ? runtime.screensaverProvider.windowCount || 0 : 0
    }
    signal settingsWritten(string pluginId, bool success)
    property Connections nativePanelChanges: Connections {
        target: runtime.nativeShell
        ignoreUnknownSignals: true
        function onOpenPanelsChanged() { if (runtime.nativeShell && runtime.nativeShell.openPanels.length) runtime.closePopout(); }
    }
    property int registryRevision: 0
    property var _catalogueOwners: []
    property var _catalogueComponents: ({})
    property QtObject barWidgetRegistry: QtObject {
        property var widgets: ({})
        property int revision: 0
        signal changed()
        function metadataFor(id) { const entry = widgets[runtime.catalogueId(id)]; return entry ? entry.metadata : null; }
        function availableIds() { return Object.keys(widgets); }
        function has(id) { return !!widgets[runtime.catalogueId(id)]; }
    }
    property QtObject pluginRegistry: QtObject {
        readonly property var installedPlugins: runtime.installedManifests()
        readonly property int registryRevision: runtime.registryRevision
        readonly property bool scanning: !Plugins.ready
        property string lastEnableError: ""
        signal pluginsChanged()
        signal pluginEnableFinished(string id, bool success)
        function isEnabled(id) {
            const key = runtime.resolve(id), record = Plugins.registry[key];
            return !!record && record.valid && Config.isEnabled(key);
        }
        function resolveEnabledId(id) { const key = runtime.resolve(id); return isEnabled(key) ? key : ""; }
        function entryPointUrl(manifest, kind) {
            if (!manifest) return "";
            return Plugins.entryUrl(runtime.resolve(manifest.id), kind === "barWidget" ? "bar-widget" : String(kind));
        }
        function setEnabled(id, value, placement) {
            if (placement && Object.keys(placement).length) {
                lastEnableError = "compat: placement changes require haseen bar configuration";
                console.warn(lastEnableError); return false;
            }
            return runtime.setPluginEnabled(id, !!value);
        }
    }
    property Connections registryChanges: Connections {
        target: Plugins
        function onRegistryChanged() {
            runtime.registryRevision++;
            runtime.pluginRegistry.pluginsChanged();
            if (runtime._catalogueOwners.length) runtime.rebuildCatalogue();
        }
    }
    property Connections configChanges: Connections {
        target: Config
        function onMergedChanged() { if (runtime._catalogueOwners.length) runtime.rebuildCatalogue(); }
    }
    function installedManifests() {
        const revision = registryRevision, out = {};
        for (const id in Plugins.registry) {
            const record = Plugins.registry[id];
            if (!record.valid) continue;
            out[record.upstreamId || id] = Object.assign({}, record.upstreamManifest || record, { __sourceDir: record.dir });
        }
        return out;
    }
    function catalogueId(id) {
        const key = resolve(id), record = Plugins.registry[key];
        return record ? record.upstreamId || key : key;
    }
    function acquireCatalogue(owner) {
        if (_catalogueOwners.indexOf(owner) < 0) _catalogueOwners = _catalogueOwners.concat([owner]);
        rebuildCatalogue(); return barWidgetRegistry;
    }
    function releaseCatalogue(owner) {
        _catalogueOwners = _catalogueOwners.filter(item => item !== owner);
        if (!_catalogueOwners.length) {
            barWidgetRegistry.widgets = {};
            for (const id in _catalogueComponents) _catalogueComponents[id].component.destroy();
            _catalogueComponents = {};
            barWidgetRegistry.revision++; barWidgetRegistry.changed();
        }
    }
    function rebuildCatalogue() {
        const entries = {}, components = {};
        for (const id in Plugins.registry) {
            const record = Plugins.registry[id];
            if (!record.valid || !Config.isEnabled(id) || record.kinds.indexOf("bar-widget") < 0) continue;
            // Nook injects bar/moduleName/settings after its Loader creates
            // the child. Native and DMS required/context contracts cannot be
            // fulfilled by that injector, so this is an Omarchy-only catalogue.
            if (record.compat !== "omarchy") continue;
            const url = Plugins.entryUrl(id, "bar-widget"), previous = _catalogueComponents[id];
            const component = previous && previous.url === url ? previous.component : Qt.createComponent(url);
            if (component.status === 3) {
                Plugins.warnOnce("compat-catalogue:" + id, "compat: widget catalogue cannot compile " + id + ": " + Host.firstError(component.errorString(), url));
                if (!previous || previous.component !== component) component.destroy();
                continue;
            }
            components[id] = { url: url, component: component };
            entries[record.upstreamId || id] = { component: component,
                metadata: Object.assign({}, record.upstreamManifest ? record.upstreamManifest.barWidget || {} : {},
                    { id: record.upstreamId || id, name: record.name, description: record.description }) };
        }
        for (const id in _catalogueComponents)
            if (!components[id] || components[id].component !== _catalogueComponents[id].component) _catalogueComponents[id].component.destroy();
        _catalogueComponents = components;
        barWidgetRegistry.widgets = entries;
        barWidgetRegistry.revision++; barWidgetRegistry.changed();
    }
    function setPluginEnabled(id, enabled) {
        const key = resolve(id), record = Plugins.registry[key];
        if (!record || !record.valid) {
            pluginRegistry.lastEnableError = "compat: cannot enable/disable an unknown or invalid plugin " + id;
            console.warn(pluginRegistry.lastEnableError); return false;
        }
        pluginRegistry.lastEnableError = "";
        _writes = _writes.concat([{ id: key, action: enabled ? "enable" : "disable" }]);
        startWrite(); return true;
    }
    function finishWrite(job, success) {
        if (job.action) {
            pluginRegistry.lastEnableError = success ? "" : "compat: haseen plugin " + job.action + " failed for " + job.id;
            pluginRegistry.pluginEnableFinished(job.id, success);
        } else settingsWritten(job.id, success);
    }

    function unsupported(action, id) {
        Plugins.warnOnce("compat:" + action + ":" + id, "compat: " + action + " unavailable for '" + id + "'; enable a haseen provider with the required API");
        return false;
    }
    function roleService(role) {
        const entry = Plugins.roles[role];
        return entry && entry.instance ? entry.instance : (services["haseen." + role] || null);
    }
    function resolve(id) {
        id = String(id || "");
        if (!legacyRoles[id]) return Plugins.resolveId(id);
        const provider = Plugins.provider(legacyRoles[id]);
        const builtin = "haseen." + legacyRoles[id];
        return provider || (Plugins.registry[builtin] && Config.isEnabled(builtin) ? builtin : "");
    }
    function serviceFor(id) {
        id = String(id || "");
        // The two historical session-state APIs expose only readable state.
        if (id === "omarchy.lock") return lockProvider ? legacyLock : null;
        if (id === "omarchy.idle") return roleService("idle") ? legacyIdle : null;
        const resolved = resolve(id);
        if (services[resolved]) return services[resolved];
        for (const role in Plugins.roles) {
            const entry = Plugins.roles[role];
            if (entry && entry.id === resolved) return entry.instance;
        }
        return null;
    }
    function claimService(id, owner) {
        if (serviceOwners[id] && serviceOwners[id] !== owner) return false;
        serviceOwners = Object.assign({}, serviceOwners, { [id]: owner });
        return true;
    }
    function releaseService(id, owner) {
        if (serviceOwners[id] !== owner) return;
        const next = Object.assign({}, serviceOwners); delete next[id]; serviceOwners = next;
    }
    function registerService(id, item) {
        if (!item || (services[id] && services[id] !== item)) return false;
        services = Object.assign({}, services, { [id]: item });
        return true;
    }
    function unregisterService(id, item) {
        if (services[id] !== item) return;
        const next = Object.assign({}, services); delete next[id]; services = next;
    }
    function overlayFor(id) { return overlays[resolve(id)] || null; }
    function registerOverlay(id, item) {
        if (!item || (overlays[id] && overlays[id] !== item)) return false;
        overlays = Object.assign({}, overlays, { [id]: item });
        return true;
    }
    function unregisterOverlay(id, item) {
        if (overlays[id] !== item) return;
        if (activePopout === item) releasePopout(item);
        const next = Object.assign({}, overlays); delete next[id]; overlays = next;
    }
    function registerWidget(id, item, barApi) {
        if (!item) return false;
        const entries = widgets[id] || [];
        if (entries.some(e => e.item === item)) return true;
        widgets = Object.assign({}, widgets, { [id]: entries.concat([{ item: item, bar: barApi }]) });
        if (_pendingPanels[id]) {
            const queue = _pendingPanels[id];
            const next = Object.assign({}, _pendingPanels); delete next[id]; _pendingPanels = next;
            for (const data of queue) {
                if (!openProvider(id, item, data)) console.warn("compat: loaded provider rejected summon payload for", id);
            }
        }
        return true;
    }
    function unregisterWidget(id, item) {
        const entries = widgets[id] || [];
        if (activePopout && (activePopout === item || belongsTo(activePopout, item))) releasePopout(activePopout);
        const next = Object.assign({}, widgets), remaining = entries.filter(e => e.item !== item);
        if (remaining.length) next[id] = remaining; else delete next[id];
        widgets = next;
    }
    function moduleWidgets(id) { return (widgets[String(id || "")] || []).map(e => e.item); }
    function belongsTo(target, ancestor) {
        for (let node = target; node; node = node.parent) if (node === ancestor) return true;
        return false;
    }
    function requestPopout(owner) {
        if (!owner) return false;
        if (activePopout === owner) return true;
        const old = activePopout;
        if (old) {
            const close = typeof old.closeForPopoutSwitch === "function" ? "closeForPopoutSwitch" : "close";
            if (typeof old[close] !== "function") return unsupported("close previous popout", "popup");
            activePopout = null;
            old[close]();
        }
        if (nativeShell && nativeShell.openPanels.length) nativeShell.openPanels = [];
        activePopout = owner;
        return true;
    }
    function releasePopout(owner) {
        if (activePopout !== owner) return false;
        activePopout = null;
        return true;
    }
    function closePopout() {
        const old = activePopout;
        if (!old) return true;
        if (typeof old.close !== "function") return unsupported("close popout", "popup");
        activePopout = null; old.close(); return true;
    }
    function switchPanelFrom(owner, direction) {
        const entries = [];
        for (const id in widgets) for (const entry of widgets[id]) {
            const item = entry.item;
            if (typeof item.open === "function" || typeof item.openPanel === "function" || typeof item.togglePanel === "function") entries.push(entry);
        }
        let index = entries.findIndex(e => e.item === owner || belongsTo(owner, e.item));
        if (index < 0 || entries.length < 2) return false;
        const current = entries[index], sameScreen = entries.filter(e => !current.bar || !e.bar || e.bar.screen === current.bar.screen);
        index = sameScreen.indexOf(current);
        if (sameScreen.length < 2) return false;
        const item = sameScreen[(index + (Number(direction) < 0 ? -1 : 1) + sameScreen.length) % sameScreen.length].item;
        if (!closePopout()) return false;
        const fn = typeof item.open === "function" ? "open" : typeof item.openPanel === "function" ? "openPanel" : "togglePanel";
        item[fn](); return true;
    }
    function payload(value) {
        if (value === undefined || value === null || value === "") return {};
        try { const p = typeof value === "string" ? JSON.parse(value) : value; return Host.object(p) ? p : null; }
        catch (e) { console.warn("compat: invalid panel payload:", String(e)); return null; }
    }
    function applyPayload(item, data) {
        if (!Object.keys(data).length) return true;
        if (typeof item.applyPayload === "function") return item.applyPayload(data) !== false;
        if (typeof item.setPayload === "function") return item.setPayload(data) !== false;
        // Validate the entire payload before touching the provider.
        for (const key in data) if (["__proto__", "constructor", "prototype"].indexOf(key) >= 0 || !(key in item) || typeof item[key] === "function") return unsupported("payload field " + key, item.pluginId || "panel");
        try { for (const key in data) item[key] = data[key]; }
        catch (e) { console.warn("compat: provider rejected payload:", String(e)); return false; }
        return true;
    }
    // A legacy panel entry receives no surface from its host: upstream's panel
    // loader only injects properties, so an entry that wants a window builds
    // one. Such an entry must not be hosted inside the native popup, whose
    // focus grab covers that popup's own window alone: the first click on the
    // plugin's window would read as an outside click and destroy the entry.
    // The entry's own root declaration answers this, so no list of plugin ids
    // can go stale behind an updated plugin.
    function panelSelfWindowed(id) {
        const key = resolve(id), record = Plugins.registry[key];
        if (!record || !record.valid || record.compat !== "omarchy") return false;
        const url = Plugins.entryUrl(key, "panel");
        if (url === "") return false;
        if (_panelSurfaces[url] !== undefined) return _panelSurfaces[url];
        let owns = false;
        try { owns = declaresWindow(Host.source(url, runtime)); }
        catch (e) { Plugins.warnOnce("compat-panel-surface:" + key, "compat: cannot read the panel entry of '" + key + "': " + String(e)); }
        _panelSurfaces[url] = owns;
        return owns;
    }
    // The root type, or any type the entry declares, is a window. Comments are
    // masked first so prose about a window cannot count as one; string literals
    // are not, because a JS regex holding a quote (replace(/'/g, ...), which a
    // real panel entry uses) makes quote masking swallow the rest of the file.
    // A string that spells out a window declaration builds one anyway.
    function declaresWindow(text) {
        const clean = String(text).replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g, " ");
        return /(^|[^\w.])(?:[A-Z]\w*\.)?[A-Z]\w*Window\s*\{/.test(clean);
    }
    function openProvider(id, item, data) {
        const record = Plugins.registry[id];
        if (record && record.compat === "omarchy" && (record.kinds.indexOf("panel") >= 0 || record.kinds.indexOf("overlay") >= 0)) {
            if (typeof item.open !== "function") return unsupported("open(payloadJson)", id);
            return item.open(JSON.stringify(data)) !== false;
        }
        if (id === Plugins.provider("menu") && Object.keys(data).length === 1 && typeof data.path === "string" && typeof item.open === "function") {
            return item.open(data.path) !== false;
        }
        if (!applyPayload(item, data)) return false;
        const fn = typeof item.open === "function" ? "open" : typeof item.openPanel === "function" ? "openPanel" : "";
        return fn ? item[fn]() !== false : Object.keys(data).length === 0;
    }
    function isPluginOpen(id) {
        const resolved = resolve(id);
        if (nativeShell && nativeShell.openPanels.indexOf(resolved) >= 0) return true;
        const item = overlayFor(resolved) || serviceFor(resolved);
        if (item && (item.shown === true || item.opened === true || item.active === true || item.rulesOpen === true || item.latched === true)) return true;
        return moduleWidgets(resolved).some(w => w.opened === true || w.isOpen === true || w.panelOpen === true);
    }
    function summon(id, value) {
        const resolved = resolve(id), data = payload(value);
        if (!resolved || data === null) return false;
        if (!Config.isEnabled(resolved)) return unsupported("summon disabled plugin", id);
        const service = serviceFor(resolved);
        if ((legacyRoles[id] === "osd" || resolved === Plugins.provider("osd")) && service && typeof service.show === "function") {
            const icon = String(data.icon || ""), glyphs = { brightness: "\uf185", volume: "\uf028", muted: "\ueee8" };
            const number = Number(data.value);
            if (!isFinite(number)) return false;
            service.show(glyphs[icon] || icon, number > 1 ? number / 100 : number, data.muted === true);
            return true;
        }
        const record = Plugins.registry[resolved];
        if (record && record.kinds.indexOf("overlay") >= 0) {
            const overlay = overlayFor(resolved);
            if (!overlay || typeof overlay.open !== "function" || !requestPopout(overlay)) return unsupported("overlay provider", id);
            const opened = openProvider(resolved, overlay, data);
            if (!opened) releasePopout(overlay);
            return opened;
        }
        const separatePanel = record && record.kinds.indexOf("panel") >= 0;
        const entries = (widgets[resolved] || []).filter(e => !separatePanel || !e.bar || e.bar.kind === "panel");
        const focused = nativeShell && typeof nativeShell.focusedScreen === "function" ? nativeShell.focusedScreen() : null;
        const entry = entries.find(e => e.bar && e.bar.screen === focused) || entries[0];
        if (entry) {
            const w = entry.item;
            if (typeof w.open === "function" || typeof w.openPanel === "function") return openProvider(resolved, w, data);
            if (!applyPayload(w, data)) return false;
            if (!isPluginOpen(resolved) && typeof w.togglePanel === "function") { w.togglePanel(); return true; }
            if (isPluginOpen(resolved)) return true;
        }
        if (nativeShell && Plugins.componentUrl(resolved, "panel") !== "" && Config.isEnabled(resolved)) {
            if (!closePopout()) return false;
            // Loaded providers receive their payload, not a discarded IPC argument.
            if (!entry) _pendingPanels = Object.assign({}, _pendingPanels, { [resolved]: (_pendingPanels[resolved] || []).concat([data]) });
            if (nativeShell.openPanels.indexOf(resolved) < 0) nativeShell.togglePanel(resolved);
            return nativeShell.openPanels.indexOf(resolved) >= 0;
        }
        if (service && typeof service.open === "function") return openProvider(resolved, service, data);
        return unsupported("summon", id);
    }
    function hide(id) {
        const resolved = resolve(id);
        let handled = false;
        for (const w of moduleWidgets(resolved)) if (typeof w.close === "function") { w.close(); handled = true; }
        if (nativeShell && nativeShell.openPanels.indexOf(resolved) >= 0) { nativeShell.closePanel(resolved); handled = true; }
        const service = overlayFor(resolved) || serviceFor(resolved);
        if (service && typeof service.hide === "function") { service.hide(); handled = true; }
        else if (service && typeof service.close === "function") { service.close(); handled = true; }
        else if (service && resolved === Plugins.provider("osd") && "shown" in service) { service.shown = false; handled = true; }
        const next = Object.assign({}, _pendingPanels); delete next[resolved]; _pendingPanels = next;
        return handled || unsupported("hide", id);
    }
    function toggle(id, value) { return isPluginOpen(id) ? hide(id) : summon(id, value); }
    function persist(id, request) {
        let copy;
        try { copy = JSON.parse(JSON.stringify(request)); }
        catch (e) { console.warn("compat: settings must be JSON serializable:", String(e)); return false; }
        _writes = _writes.concat([{ id: id, request: copy }]);
        startWrite();
        return true; // accepted, settingsWritten reports the durable result
    }
    function startWrite() {
        if (_writing || !_writes.length) return;
        _writing = _writes[0]; _writes = _writes.slice(1);
        writer.command = [Paths.haseenPath + "/../../bin/haseen-plugin-" + (_writing.action || "settings"), _writing.id, "--yes"];
        writer.running = true;
    }
    property Process writer: Process {
        stdinEnabled: true
        stdout: StdioCollector { id: written }
        stderr: StdioCollector { id: errors }
        onStarted: { if (!runtime._writing.action) write(JSON.stringify(runtime._writing.request) + "\n"); stdinEnabled = false; }
        onRunningChanged: {
            if (!running) Qt.callLater(function() {
                if (!runtime._writing || runtime.writer.running) return;
                const job = runtime._writing;
                runtime._writing = null;
                stdinEnabled = true;
                console.warn("compat: cannot start plugin persistence command for", job.id);
                runtime.finishWrite(job, false);
                runtime.startWrite();
            });
        }
        onExited: function(code) {
            if (!runtime._writing) return;
            const job = runtime._writing, id = job.id;
            let success = code === 0;
            if (success) {
                try { Config.user = JSON.parse(job.action ? Host.source(Paths.userShellConfig, runtime) : written.text); }
                catch (e) { console.warn("compat: settings writer returned invalid JSON:", String(e)); success = false; }
            } else console.warn("compat: settings write failed for", id, errors.text);
            runtime._writing = null;
            stdinEnabled = true;
            runtime.finishWrite(job, success);
            Qt.callLater(() => runtime.startWrite());
        }
    }
}
