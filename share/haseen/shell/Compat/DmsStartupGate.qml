pragma Singleton

import QtQuick
import Quickshell
import qs.Haseen
import "Host.js" as Host

// The `startupCheck` gate of DankMaterialShell plugins (architecture 5.4).
// A plugin.json may name a QML file whose root has check(done) (or a
// synchronous check()); DMS runs it before loading any surface and keeps the
// plugin unloaded when it reports a problem. The calling convention and the
// result rules follow DankMaterialShell's quickshell/Services/PluginService.qml
// runStartupGate / _normalizeStartupError (MIT, Copyright (c) 2025 Avenge
// Media LLC):
//   done(null) / done(undefined) / done("")  -> load the plugin
//   done("message")                          -> refuse, title only
//   done({ title, details })                 -> refuse, title and details
// A refusal is reported once through Plugins.reportError and, as DMS's toast
// does, a desktop notification. Every DMS host of the plugin (bar widget on
// each screen, daemon, desktop widget) waits for the same single run. A pass
// is remembered for the life of the shell; a refusal is not, so enabling the
// plugin again after installing what it needs checks again.
Singleton {
    id: gate

    // Registry id -> { waiters: [fn] } while a check runs.
    property var _running: ({})
    // Registry id -> true once its check passed.
    property var _passed: ({})

    function checkUrl(id: string): string {
        const rec = Plugins.registry[id];
        const m = rec && rec.compat === "dms" ? rec.upstreamManifest : null;
        let file = m && typeof m.startupCheck === "string" ? m.startupCheck : "";
        if (file.indexOf("./") === 0)
            file = file.slice(2);
        if (file === "" || file.startsWith("/") || file.split("/").indexOf("..") >= 0)
            return "";
        return Paths.fileUrl(rec.dir + "/" + file);
    }

    function normalize(result: var): var {
        if (!result)
            return null;
        if (typeof result === "string")
            return {
                title: result,
                details: ""
            };
        return {
            title: String(result.title || "Plugin dependency missing"),
            details: String(result.details || "")
        };
    }

    // run(id, onResult) — onResult(true) when the plugin may load. Without a
    // startupCheck it answers at once, before returning.
    function run(id: string, onResult: var): void {
        const url = checkUrl(id);
        if (url === "" || _passed[id]) {
            onResult(true);
            return;
        }
        if (_running[id]) {
            _running[id].waiters.push(onResult);
            return;
        }
        const entry = {
            waiters: [onResult]
        };
        const running = Object.assign({}, _running);
        running[id] = entry;
        _running = running;

        let probe = null, release = null, settled = false;
        const finish = result => {
            if (settled)
                return;
            settled = true;
            if (probe)
                probe.destroy();
            if (release)
                Qt.callLater(release);
            const err = gate.normalize(result);
            const left = Object.assign({}, gate._running);
            delete left[id];
            gate._running = left;
            if (err === null) {
                const passed = Object.assign({}, gate._passed);
                passed[id] = true;
                gate._passed = passed;
            } else {
                const rec = Plugins.registry[id];
                const name = rec ? rec.name : id;
                Plugins.reportError(id, "dms: startup check: " + err.title);
                // As qs.Services ToastService does; not imported here, since
                // every qs.Compat user would then need the DMS modules.
                Quickshell.execDetached(["notify-send", "--app-name=haseen", "--urgency=critical", name + " Startup Failed", err.details !== "" ? err.title + "\n\n" + err.details : err.title]);
            }
            for (const waiter of entry.waiters)
                waiter(err === null);
        };
        const cancel = Host.load(url, gate, loaded => {
            if (loaded.error !== "") {
                finish("startupCheck: " + loaded.error);
                return;
            }
            probe = loaded.item;
            try {
                if (typeof probe.check !== "function")
                    throw new Error("startupCheck has no check function");
                if (probe.check.length >= 1)
                    probe.check(finish);
                else
                    finish(probe.check());
            } catch (e) {
                finish(String(e && e.message ? e.message : e));
            }
        });
        // A synchronous check settles inside Host.load, before its release
        // function exists; free the component now in that case.
        release = cancel;
        if (settled)
            Qt.callLater(cancel);
    }
}
