import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import "Host.js" as Host

// Adapted API contract from Omarchy PluginShellApi.qml (MIT).
// Copyright (c) David Heinemeier Hansson
QtObject {
    id: api
    required property string pluginId
    property var bar: null
    readonly property var nativeShell: Compat.Runtime.nativeShell
    readonly property var appLibrary: DesktopEntries.applications
    readonly property var barConfig: Config.bar
    readonly property var settings: Plugins.settingsFor(pluginId)
    readonly property string idleProvider: Plugins.provider("idle") || (Plugins.registry["haseen.idle"] ? "haseen.idle" : "")
    readonly property var idleConfig: idleProvider ? Object.assign({}, Plugins.settingsFor(idleProvider), { screensaver: Plugins.settingsFor(idleProvider).screensaverAfter }) : ({})
    // Legacy idle values are a view of the real haseen idle provider, not a
    // second inert config branch. Persistence translates its changed keys.
    readonly property var shellConfig: Object.assign({}, Config.merged, { idle: idleConfig })

    function serviceFor(id) { return Compat.Runtime.serviceFor(id); }
    function firstPartyServiceFor(id) { return Compat.Runtime.serviceFor(id); }
    function summon(id, payloadJson) { return Compat.Runtime.summon(id, payloadJson); }
    function hide(id) { return Compat.Runtime.hide(id); }
    function toggle(id, payloadJson) { return Compat.Runtime.toggle(id, payloadJson); }
    function isPluginOpen(id) { return Compat.Runtime.isPluginOpen(id); }
    // The snapshot this instance holds. Originals copy every delivered setting,
    // change one key and write the copy back (omapager persistSettings), and
    // they assign their own `settings` on the way, so the copy stops tracking
    // the shell. Writing the whole copy would revert keys another screen's
    // instance changed meanwhile; only this instance's own delta is persisted.
    property var _delivered: ({})
    property bool _wrote: false
    onSettingsChanged: if (!_wrote) _delivered = snapshot(settings)
    Component.onCompleted: _delivered = snapshot(settings)
    function snapshot(value) {
        try { return JSON.parse(JSON.stringify(value || {})); }
        catch (e) { return {}; }
    }
    function updateEntryInline(id, settings) {
        const resolved = Compat.Runtime.resolve(id);
        if (resolved !== pluginId || !Host.object(settings)) {
            console.warn("compat: updateEntryInline can only write", pluginId, "with an object");
            return false;
        }
        const next = snapshot(settings);
        const delta = Host.changes(_delivered, next).filter(change => change.path.length
            && !change.path.some(key => ["__proto__", "constructor", "prototype"].indexOf(key) >= 0));
        _wrote = true;
        _delivered = next;
        if (!delta.length)
            return true;
        return Compat.Runtime.persist(pluginId, { changes: delta.map(change => change.remove
            ? ({ path: ["plugins", pluginId, "settings"].concat(change.path), remove: true })
            : ({ path: ["plugins", pluginId, "settings"].concat(change.path), value: change.value })) });
    }
    function mutateShellConfig(mutator) {
        if (typeof mutator !== "function") return false;
        const before = JSON.parse(JSON.stringify(shellConfig)), after = JSON.parse(JSON.stringify(before));
        let delta;
        try { mutator(after); delta = Host.changes(before, after); }
        catch (e) { console.warn("compat: settings mutator failed:", String(e)); return false; }
        if (!delta.length) return true;
        if (delta.some(change => !Host.allowedChange(pluginId, change.path))) {
            console.warn("compat: mutateShellConfig permits bar presentation, idle.screensaver and own plugin settings only:", pluginId);
            return false;
        }
        if (delta.some(change => change.path[0] === "idle") && !idleProvider)
            return Compat.Runtime.unsupported("idle settings", pluginId);
        return Compat.Runtime.persist(pluginId, { changes: delta, idleProvider: idleProvider });
    }
}
