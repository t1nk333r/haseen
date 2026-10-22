// Model.js: pure logic for haseen.syncthing (plan 098). No QML types here,
// so tests/test-syncthing.sh runs it under the real Qt JS engine.
//
// Adapted from ilyaZar's omarchy-syncthing (MIT, Copyright (c) 2026
// IlyaZar), its session normalisation (core/internal/session) and status
// icon rules: a folder's state and completion, the overall state the bar
// shows (offline, error, syncing, paused, idle), invitations, and the
// recent file activity from ItemFinished events.

// Interface strings stay English here and are translated where QML shows
// them; N_ and N_n mark them for tools/i18n.py (plan 109). The text helpers
// (folderText, overall, activityText) take an optional last argument `t`
// with tr() and tn(): QML passes the I18n singleton, so a sentence built
// around a value comes back in the interface language; without it they
// write English, which the IPC state and the tests read.
function N_(text) { return text; }
function N_n(one, other) { return other; }

function fill(text, args) {
    return String(text).replace(/%([1-9])/g, (whole, digit) => args[Number(digit) - 1] === undefined ? whole : String(args[Number(digit) - 1]));
}

const ENGLISH = {
    tr: (text, ...args) => fill(text, args),
    tn: (one, other, count, ...args) => fill(count === 1 ? one : other, [count].concat(args))
};

const MAX_ACTIVITY = 20;

function num(v) {
    const n = Number(v);
    return isFinite(n) && n >= 0 ? n : 0;
}

// parseStatus(text): `haseen syncthing status` as a state, or null.
function parseStatus(text) {
    let s;
    try {
        s = JSON.parse(String(text || ""));
    } catch (e) {
        return null;
    }
    if (!s || typeof s !== "object" || !Array.isArray(s.folders) || !Array.isArray(s.devices))
        return null;
    const str = v => typeof v === "string" ? v : "";
    return {
        version: str(s.version),
        myID: str(s.myID),
        guiUrl: /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]):[0-9]+\/$/.test(str(s.guiUrl)) ? s.guiUrl : "",
        folders: s.folders.filter(f => f && typeof f.id === "string").map(f => ({
            id: f.id,
            label: str(f.label) || f.id,
            path: str(f.path),
            paused: f.paused === true,
            state: str(f.state) || "unknown",
            error: str(f.error),
            globalBytes: num(f.globalBytes),
            needBytes: num(f.needBytes),
            needFiles: num(f.needFiles),
            pullErrors: num(f.pullErrors),
            devices: Array.isArray(f.devices) ? f.devices.filter(d => typeof d === "string") : []
        })),
        devices: s.devices.filter(d => d && typeof d.id === "string").map(d => ({ id: d.id, name: str(d.name) || d.id.slice(0, 7), paused: d.paused === true, connected: d.connected === true })),
        pendingDevices: (Array.isArray(s.pendingDevices) ? s.pendingDevices : []).filter(d => d && typeof d.id === "string").map(d => ({ id: d.id, name: str(d.name) || d.id.slice(0, 7), address: str(d.address) })),
        pendingFolders: (Array.isArray(s.pendingFolders) ? s.pendingFolders : []).filter(f => f && typeof f.id === "string" && typeof f.device === "string").map(f => ({ id: f.id, device: f.device, deviceName: str(f.deviceName) || f.device.slice(0, 7), label: str(f.label) || f.id }))
    };
}

// completion(folder): percent of the global size this device has.
function completion(f) {
    if (!f || f.globalBytes <= 0)
        return 100;
    return Math.max(0, Math.min(100, Math.floor(100 * (1 - f.needBytes / f.globalBytes))));
}

function folderBusy(f) {
    return !f.paused && /^(syncing|scanning|sync-preparing|scan-waiting|sync-waiting|cleaning)$/.test(f.state);
}

function folderFailed(f) {
    return !f.paused && (f.state === "error" || f.error !== "" || f.pullErrors > 0);
}

// folderText(folder, t): "Up to date", "Syncing 42%", "Scanning", "Paused"…
// A state this list does not know shows as Syncthing names it.
function folderText(f, t) {
    const T = t || ENGLISH;
    if (!f)
        return "";
    if (f.paused)
        return T.tr(N_("Paused"));
    if (f.state === "error" || f.error)
        return T.tr(N_("Error: %1"), f.error || T.tr(N_("stopped")));
    if (f.pullErrors > 0)
        return T.tn("%1 file failed", N_n("%1 file failed", "%1 files failed"), f.pullErrors);
    if (f.state === "syncing" || f.state === "sync-preparing")
        return T.tr(N_("Syncing %1%"), completion(f));
    if (f.state === "scanning" || f.state === "scan-waiting")
        return T.tr(N_("Scanning"));
    if (f.state === "sync-waiting")
        return T.tr(N_("Waiting to sync"));
    if (f.state === "idle")
        return f.needFiles > 0 ? T.tr(N_("Out of sync (%1)"), f.needFiles) : T.tr(N_("Up to date"));
    return f.state.charAt(0).toUpperCase() + f.state.slice(1);
}

// overall(state, online, t): what the bar shows: { kind, text }, kind one of
// offline, error, syncing, invited, paused, idle.
function overall(s, online, t) {
    const T = t || ENGLISH;
    if (!online || !s)
        return { kind: "offline", text: T.tr(N_("Syncthing is not running")) };
    const failed = s.folders.filter(folderFailed);
    if (failed.length)
        return { kind: "error", text: failed.length === 1 ? T.tr(N_("%1: %2"), failed[0].label, folderText(failed[0], t)) : T.tn("%1 folder has errors", N_n("%1 folder has errors", "%1 folders have errors"), failed.length) };
    const busy = s.folders.filter(folderBusy);
    if (busy.length)
        return { kind: "syncing", text: busy.length === 1 ? T.tr(N_("%1: %2"), busy[0].label, folderText(busy[0], t)) : T.tn("Syncing %1 folder", N_n("Syncing %1 folder", "Syncing %1 folders"), busy.length) };
    const invites = s.pendingDevices.length + s.pendingFolders.length;
    if (invites)
        return { kind: "invited", text: T.tn("%1 invitation", N_n("%1 invitation", "%1 invitations"), invites) };
    if (s.folders.length && s.folders.every(f => f.paused))
        return { kind: "paused", text: T.tr(N_("Paused")) };
    const up = s.devices.filter(d => d.connected).length;
    return { kind: "idle", text: s.folders.length ? T.tr(N_("Up to date · %1 of %2 devices"), up, s.devices.length) : T.tr(N_("No folders yet")) };
}

const GLYPHS = { offline: "\u{F04E8}", error: "\u{F04E7}", syncing: "\u{F04E6}", invited: "\u{F04E6}", paused: "\u{F04E6}", idle: "\u{F04E6}" };

function glyph(kind) {
    return GLYPHS[kind] || GLYPHS.idle;
}

function formatBytes(n) {
    const v = num(n);
    const units = ["B", "KB", "MB", "GB", "TB"];
    let i = 0, x = v;
    while (x >= 1024 && i < units.length - 1) {
        x /= 1024;
        i++;
    }
    return (i === 0 ? String(Math.round(x)) : x.toFixed(x >= 10 ? 0 : 1)) + " " + units[i];
}

// parseEvents(text, lastId, activity): a /rest/events reply. Returns
// { lastId, changed, activity }: the highest id seen, whether anything
// other than a finished item came (worth a new status), and the newest
// finished items first, at most MAX_ACTIVITY.
function parseEvents(text, lastId, activity) {
    let list;
    try {
        list = JSON.parse(String(text || ""));
    } catch (e) {
        list = null;
    }
    const out = { lastId: num(lastId), changed: false, activity: (activity || []).slice() };
    if (!Array.isArray(list))
        return out;
    for (const e of list) {
        if (!e || typeof e !== "object")
            continue;
        if (num(e.id) > out.lastId)
            out.lastId = num(e.id);
        if (e.type === "ItemFinished" && e.data && typeof e.data.item === "string") {
            out.activity.unshift({
                folder: typeof e.data.folder === "string" ? e.data.folder : "",
                item: e.data.item,
                action: typeof e.data.action === "string" ? e.data.action : "update",
                error: typeof e.data.error === "string" ? e.data.error : "",
                time: typeof e.time === "string" ? e.time : ""
            });
        } else {
            out.changed = true;
        }
    }
    out.activity = out.activity.slice(0, MAX_ACTIVITY);
    return out;
}

// activityText(entry, folders, t): "Updated notes.md · Docs".
function activityText(a, folders, t) {
    const T = t || ENGLISH;
    const f = (folders || []).find(x => x.id === a.folder);
    const line = a.error ? T.tr(N_("Failed %1"), a.item) : a.action === "delete" ? T.tr(N_("Deleted %1"), a.item) : a.action === "metadata" ? T.tr(N_("Changed %1"), a.item) : T.tr(N_("Updated %1"), a.item);
    return line + (f ? " · " + f.label : "");
}

// expandHome(path, home): a leading ~ means the home directory.
function expandHome(path, home) {
    const p = String(path || "").trim();
    if (p === "~")
        return home;
    return p.indexOf("~/") === 0 ? home + p.slice(1) : p;
}

// shared(folder, deviceId): the folder is shared with that device.
function shared(f, id) {
    return !!(f && f.devices.indexOf(id) >= 0);
}

// backoff(failures): seconds to wait before asking a stopped Syncthing
// again: 5, 10, 20, 40, then the cap (settings.refreshIntervalSec, ≥ 60).
function backoff(failures, cap) {
    const c = Math.max(60, num(cap) || 60);
    return Math.min(c, 5 * Math.pow(2, Math.max(0, failures)));
}
