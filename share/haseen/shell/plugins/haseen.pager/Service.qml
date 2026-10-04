// haseen.pager: the notification daemon. Stacking, grouping per source,
// markup parsing, resolved source icons, inline reply (KDE Connect),
// per-source snooze, held notifications, Recent and disk history.
//
// Adapted from omapager (https://github.com/njpatel/omapager), MIT,
// Copyright (c) 2026 Neil Jagdish Patel. See LICENSE and UPSTREAM.md for what
// changed: the Omarchy plugin API is replaced by qs.Haseen, Do Not Disturb is
// the shared `dnd` flag, the Python helpers are gone (store in FileView, icons
// resolved locally, replies through kdeconnect.sh), and the deck's surface
// exists only while there is something on it.
//
// Quickshell's NotificationServer owns org.freedesktop.Notifications, so only
// one daemon may run: haseen.notifications steps aside while this one is in
// `services` (see its Service.qml).

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Haseen

import "Store.js" as Store
import "Security.js" as Security
import "Layout.js" as Layout
import "Markup.js" as Markup

Scope {
    id: service

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // ------------------------------------------------------------- settings
    //
    // Upstream's bar widget pushed its shell.json entry into the daemon; here
    // the service gets `settings` itself. Applied as plain properties (not
    // bindings) so the `pager` IPC verbs `stack` and `align` can override them
    // for the session, as upstream's did.
    property string stacking: "source"      // all | source
    property real fontScale: 1
    property string actionsAlign: "right"   // right | left
    property bool hideSettingsAction: true
    property string displayMode: "active"   // active | specific | all
    property string displayName: ""
    property int edgeSpacing: 12
    property bool showCountdown: false
    property string avoidFullscreen: "off"  // off | all | steam
    property bool offerSnoozeWhenSharing: true
    property bool fetchIcons: false
    property bool allowDefaultActionOnCardClick: false
    property int clipboardTimeout: 60
    property int historyHours: 24
    property bool smartRaise: true
    property var snoozeChoices: ["30", "60", "240", "tomorrow"]
    property int wakeHour: 8
    property int sourceLimit: 8
    property int heldPerSource: 10
    property int recentCount: 5
    property int cardWidth: 380

    function _setting(key: string, fallback: var): var {
        const v = settings ? settings[key] : undefined;
        return v === undefined || v === null ? fallback : v;
    }

    function _clamp(v: var, min: int, max: int, fallback: int): int {
        const n = Number(v);
        return isFinite(n) ? Math.max(min, Math.min(max, Math.round(n))) : fallback;
    }

    function applySettings(): void {
        const stack = String(_setting("stacking", "source"));
        if ((stack === "all" || stack === "source") && stack !== stacking)
            commit(() => {
                service.stacking = stack;
            });
        fontScale = _clamp(_setting("fontScale", 100), 75, 200, 100) / 100;
        const align = String(_setting("actionsAlign", "right"));
        actionsAlign = align === "left" ? "left" : "right";
        hideSettingsAction = _setting("hideSettingsAction", true) !== false;
        const mode = String(_setting("displayMode", "active"));
        // Keep the output name before the mode so selecting a present monitor
        // does not pass through a transient specific-without-a-name state.
        displayName = String(_setting("displayName", "") || "");
        displayMode = mode === "specific" || mode === "all" ? mode : "active";
        edgeSpacing = _clamp(_setting("edgeSpacing", 12), 0, 64, 12);
        showCountdown = _setting("showCountdown", false) === true;
        const avoid = String(_setting("avoidFullscreen", "off"));
        avoidFullscreen = avoid === "all" || avoid === "steam" ? avoid : "off";
        offerSnoozeWhenSharing = _setting("offerSnoozeWhenSharing", true) !== false;
        setFetchRemoteIcons(_setting("fetchRemoteIcons", false) === true);
        allowDefaultActionOnCardClick = _setting("allowDefaultActionOnCardClick", false) === true;
        const life = Number(_setting("clipboardTimeout", 60));
        clipboardTimeout = [30, 60, 90].indexOf(life) >= 0 ? life : 60;
        historyHours = Store.retentionHours(_setting("historyHours", 24));
        smartRaise = _setting("smartRaise", true) !== false;
        // "tomorrow" means the next morning; 0 is a valid hour.
        wakeHour = _clamp(_setting("wakeHour", 8), 0, 23, 8);
        sourceLimit = _clamp(_setting("sourceLimit", 8), 2, 20, 8);
        heldPerSource = _clamp(_setting("heldPerSource", 10), 3, 25, 10);
        recentCount = _clamp(_setting("recentCount", 5), 1, 20, 5);
        cardWidth = _clamp(_setting("width", 380), 240, 800, 380);
        // Empty means "none chosen", not "no snoozing".
        const chosen = _setting("snoozeDurations", null);
        snoozeChoices = Array.isArray(chosen) && chosen.length > 0 ? chosen.map(String) : ["30", "60", "240", "tomorrow"];
        if (!_quietLoaded)
            codesBypassQuiet = _setting("codesBypassQuiet", true) !== false;
        _trimDiskHistory();
    }

    onSettingsChanged: Qt.callLater(applySettings)
    Component.onCompleted: applySettings()

    // ------------------------------------------------------------- roles
    //
    // shell.qml routes `notifications clear/toggleDnd` to the plugin that
    // provides the role. haseen.notifications is the fallback provider and
    // unregisters itself while this plugin is in `services`; if it got there
    // after us, take the role back.
    readonly property bool hosted: pluginId !== "" && Config.services.indexOf(pluginId) >= 0 && Config.isEnabled(pluginId)

    function _claimRole(): void {
        if (hosted && !Plugins.roles.notifications)
            Plugins.registerRole("notifications", pluginId, service);
    }

    Connections {
        target: Plugins
        function onRolesChanged() {
            Qt.callLater(service._claimRole);
        }
    }

    // Role functions (architecture 5.5).
    function clear(): void {
        clearAll("cleared");
        clearRecent();
    }

    function toggleDnd(): void {
        setDoNotDisturb(!doNotDisturb);
    }

    // ------------------------------------------------------------- quiet
    //
    // Do Not Disturb is the shared `dnd` flag (qs.Haseen Flags), so `haseen
    // toggle dnd`, `notifications toggleDnd`, the bar and the panel agree.
    // The flag file is the state; this plugin only writes it through Flags.
    readonly property bool doNotDisturb: Flags.dnd
    property double silencedSince: 0
    // The DND state quiet.json last recorded, so a restart keeps the moment
    // silencing began instead of restarting the Held Back window.
    property bool _savedDnd: false

    function setDoNotDisturb(value: bool): void {
        if (!!value === doNotDisturb)
            return;
        Flags.set("dnd", !!value);
    }

    onDoNotDisturbChanged: {
        if (doNotDisturb) {
            if (!(_savedDnd && silencedSince > 0))
                silencedSince = Date.now() / 1000;
            if (sharingActive)
                sharingOfferHandled = true;
        } else {
            silencedSince = 0;
        }
        if (storeReady)
            _savedDnd = doNotDisturb;
        saveQuiet();
    }

    // A verification code is the one thing quiet cannot afford to swallow.
    // Codes are only ever detected from a keyword next to a plausible shape,
    // so this is a narrow hole - and it can be closed.
    property bool codesBypassQuiet: true

    function setCodesBypassQuiet(value: bool): void {
        if (!!value === codesBypassQuiet)
            return;
        codesBypassQuiet = !!value;
        saveQuiet();
    }

    // ------------------------------------------------------------- sharing
    //
    // The Hyprland portal names all its PipeWire video streams alike. Observe
    // their lifetime, not compositor frame activity, which also includes
    // screenshots and VNC and has no startup snapshot.
    readonly property var sharingCandidates: {
        if (!offerSnoozeWhenSharing)
            return [];
        const nodes = Pipewire.nodes.values;
        const out = [];
        for (let i = 0; i < nodes.length && out.length < 64; i++)
            if (nodes[i].type === PwNodeType.VideoSource)
                out.push(nodes[i]);
        return out;
    }

    PwObjectTracker {
        objects: service.sharingCandidates
    }

    readonly property int sharingStreams: {
        if (!Pipewire.ready)
            return 0;
        let count = 0;
        for (const node of sharingCandidates) {
            if (!node.ready)
                continue;
            const props = node.properties;
            if (props["media.class"] === "Video/Source" && String(props["media.name"] || "").indexOf("xdph-streaming-") === 0)
                count++;
        }
        return count;
    }
    readonly property bool sharingActive: sharingStreams > 0
    property bool sharingOfferHandled: false
    readonly property bool sharingOfferPending: offerSnoozeWhenSharing && sharingActive && !sharingOfferHandled && !doNotDisturb && !globalSnoozeUntil
    readonly property string sharingDetectionStatus: !offerSnoozeWhenSharing ? "Screen-sharing suggestions disabled" : !Pipewire.ready ? "Sharing detection unavailable: PipeWire disconnected" : sharingActive ? "Screen sharing detected" : "No screen sharing detected"

    onSharingActiveChanged: sharingOfferHandled = sharingActive && (doNotDisturb || globalSnoozeUntil > 0)
    onGlobalSnoozeUntilChanged: {
        if (globalSnoozeUntil > 0 && sharingActive)
            sharingOfferHandled = true;
    }

    function dismissSharingOffer(): void {
        if (sharingActive)
            sharingOfferHandled = true;
    }

    function snoozeSharingOffer(seconds: int): void {
        if (!sharingOfferPending || [1800, 3600, 14400].indexOf(seconds) < 0)
            return;
        sharingOfferHandled = true;
        snoozeSource(globalKey, "Everything", seconds, true);
    }

    // ------------------------------------------------------------- displays
    property string deckDisplayName: ""
    readonly property var displayNames: Quickshell.screens.map(s => s.name)
    readonly property string focusedDisplayName: {
        const name = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : "";
        return displayNames.indexOf(name) >= 0 ? name : (displayNames[0] || "");
    }
    readonly property string configuredDisplayName: displayMode === "specific" && displayNames.indexOf(displayName) >= 0 ? displayName : focusedDisplayName
    readonly property string targetDisplayName: {
        let wanted = focusedDisplayName;
        if (displayMode === "specific" && displayNames.indexOf(displayName) >= 0)
            wanted = configuredDisplayName;
        else if (displayNames.indexOf(deckDisplayName) >= 0)
            wanted = deckDisplayName;
        return routeAround(wanted);
    }

    // A live deck stays put while focus moves. Losing that display moves it to
    // a usable one; a configured specific display remains selected for replug.
    onDisplayNamesChanged: {
        if (deckDisplayName && displayNames.indexOf(deckDisplayName) < 0)
            deckDisplayName = configuredDisplayName;
    }
    onDisplayModeChanged: {
        if (toasts.count > 0)
            deckDisplayName = configuredDisplayName;
    }

    function pinDeckDisplay(): void {
        if (toasts.count === 0)
            deckDisplayName = routeAround(configuredDisplayName);
    }

    function showsOn(name: string): bool {
        return (displayMode === "all" && !awayFrom(name)) || name === targetDisplayName;
    }

    // ------------------------------------------------------- fullscreen
    //
    // `avoidFullscreen` (upstream's `fullscreenOverlay` "-away" modes): never
    // put a card over a display showing a qualifying fullscreen window; route
    // it to another display, or let it wait in Recent. The deck's surface only
    // exists while cards are on screen, so upstream's "step aside" modes (for
    // an always-mapped canvas) are not needed here.
    property int hyprRevision: 0
    onAvoidFullscreenChanged: {
        if (avoidFullscreen !== "off")
            hyprRefresh.restart();
    }

    function fullscreenOn(name: string): bool {
        hyprRevision;
        if (avoidFullscreen === "off" || !name)
            return false;
        let screen = null;
        for (const s of Quickshell.screens)
            if (String(s.name) === name)
                screen = s;
        const monitor = screen ? Hyprland.monitorFor(screen) : null;
        const workspace = monitor ? monitor.activeWorkspace : null;
        if (!workspace || !workspace.hasFullscreen)
            return false;
        const windows = workspace.toplevels ? workspace.toplevels.values : [];
        for (const w of windows) {
            const ipc = w.lastIpcObject || {};
            // A workspace also reports maximized windows as fullscreen. Only a
            // real fullscreen (mode bit 2) counts.
            if ((Number(ipc.fullscreen) & 2) === 0)
                continue;
            if (avoidFullscreen === "all")
                return true;
            let appClass = String(ipc["class"] || "");
            if (appClass === "" && w.wayland)
                appClass = String(w.wayland.appId || "");
            if (/^steam_app_\d+$/.test(appClass))
                return true;
        }
        return false;
    }

    function awayFrom(name: string): bool {
        return fullscreenOn(name);
    }

    function routeAround(name: string): string {
        if (!awayFrom(name))
            return name;
        if (focusedDisplayName !== name && !awayFrom(focusedDisplayName))
            return focusedDisplayName;
        for (const n of displayNames)
            if (!awayFrom(n))
                return n;
        return "";
    }

    Connections {
        target: Hyprland
        enabled: service.avoidFullscreen !== "off"
        function onRawEvent(event) {
            switch (event.name) {
            case "fullscreen":
            case "openwindow":
            case "closewindow":
            case "movewindowv2":
            case "activewindowv2":
            case "workspacev2":
            case "focusedmonv2":
            case "changefloatingmode":
                hyprRefresh.restart();
            }
        }
    }

    // A game going fullscreen emits a burst of events: refresh once, then let
    // the IPC answer land before bindings look at it again.
    // haseen:ui-timeout
    Timer {
        id: hyprRefresh

        interval: 100
        repeat: false
        onTriggered: {
            Hyprland.refreshToplevels();
            hyprSettle.restart();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: hyprSettle

        interval: 250
        repeat: false
        onTriggered: service.hyprRevision++
    }

    // ------------------------------------------------------------- timing
    readonly property int gap: Math.max(4, Theme.gap)
    readonly property int lowDuration: 5000
    readonly property int normalDuration: 8000
    readonly property int maxDuration: 30000

    function durationFor(urgency, requested) {
        if (urgency === NotificationUrgency.Critical)
            return 0;        // never expires
        const base = urgency === NotificationUrgency.Low ? lowDuration : normalDuration;
        if (requested > 0)
            return Math.min(requested, maxDuration);
        return base;
    }

    // ------------------------------------------------------------- snooze
    //
    // Silencing one source instead of the whole desktop. The key is the row's
    // group key: per site for anything arriving through a browser
    // ("web:app.slack.com"), per app for everything else. A snoozed
    // notification is still recorded, so "what did I miss" survives.
    property var snoozes: ({})        // groupKey -> { until, label, since }
    property int snoozeRevision: 0
    readonly property string globalKey: "*"
    readonly property double globalSnoozeUntil: {
        snoozeRevision;
        return snoozedUntil(globalKey);
    }

    function durationWords(minutes) {
        if (minutes < 60)
            return minutes + " minutes";
        const hours = minutes / 60;
        if (hours === 1)
            return "an hour";
        return (Math.round(hours * 10) / 10) + " hours";
    }

    function shortWords(minutes) {
        return minutes < 60 ? (minutes + "m") : ((Math.round(minutes / 6) / 10) + "h").replace(".0h", "h");
    }

    // "tomorrow" is a time, not a duration: a different number of seconds at
    // every hour of the day.
    function snoozeOption(choice) {
        const value = String(choice || "");
        if (value === "tomorrow") {
            const wake = new Date();
            wake.setDate(wake.getDate() + 1);
            wake.setHours(wakeHour, 0, 0, 0);
            return {
                short: "Tomorrow",
                menuLabel: "Snooze until tomorrow",
                seconds: Math.max(600, Math.round((wake.getTime() - Date.now()) / 1000))
            };
        }
        const minutes = Number(value);
        if (!(minutes > 0))
            return null;
        return {
            short: shortWords(minutes),
            menuLabel: "Snooze for " + durationWords(minutes),
            seconds: Math.round(minutes * 60)
        };
    }

    readonly property var snoozeOptions: {
        const out = [];
        for (const choice of snoozeChoices) {
            const option = snoozeOption(choice);
            if (option)
                out.push(option);
        }
        return out;
    }

    function snoozedUntil(groupKey) {
        const entry = snoozes[String(groupKey || "")];
        const until = entry ? Number(entry.until || 0) : 0;
        return until > Date.now() / 1000 ? until : 0;
    }

    // Soonest to wake first, which is the order the panel lists them in.
    function liveSnoozes() {
        snoozeRevision;
        const now = Date.now() / 1000;
        const out = [];
        for (const key in snoozes) {
            if (key === globalKey)
                continue;
            const entry = snoozes[key];
            if (!entry || Number(entry.until || 0) <= now)
                continue;
            out.push({
                key: key,
                label: String(entry.label || key),
                until: Number(entry.until)
            });
        }
        out.sort((a, b) => a.until - b.until);
        return out;
    }

    readonly property int snoozeCount: {
        snoozeRevision;
        return liveSnoozes().length;
    }
    readonly property bool anySnooze: {
        snoozeRevision;
        return snoozeCount > 0 || globalSnoozeUntil > 0;
    }

    // `fromNow` re-snoozes rather than extends: "4 hours" means four hours.
    function snoozeSource(groupKey, label, seconds, fromNow) {
        const key = String(groupKey || "");
        if (!key || !(seconds > 0))
            return 0;
        // Snoozing everything supersedes silencing it: the same quiet with an
        // end on it, and the end is the point.
        if (key === globalKey)
            setDoNotDisturb(false);
        const from = fromNow ? Date.now() / 1000 : Math.max(Date.now() / 1000, snoozedUntil(key));
        const next = Object.assign({}, snoozes);
        // `since` is when this quiet period began, so the panel lists only
        // what this snooze held, not last week's.
        const since = (next[key] && snoozedUntil(key)) ? Number(next[key].since || 0) : Date.now() / 1000;
        next[key] = {
            until: from + seconds,
            label: String(label || key),
            since: since
        };
        snoozes = next;
        snoozeRevision += 1;
        saveQuiet();
        // Anything from that source already on screen goes now.
        const keys = [];
        for (let i = 0; i < toasts.count; i++) {
            const row = toasts.get(i);
            if (String(row.groupKey || "") === key)
                keys.push(row.key);
        }
        for (const k of keys)
            closeToast(k, "snoozed");
        return next[key].until;
    }

    function unsnooze(groupKey) {
        const next = {};
        for (const k in snoozes)
            if (k !== String(groupKey))
                next[k] = snoozes[k];
        snoozes = next;
        snoozeRevision += 1;
        saveQuiet();
    }

    function unsnoozeAll() {
        snoozes = ({});
        snoozeRevision += 1;
        saveQuiet();
    }

    // Wakes the bindings so a snooze that has run out stops being counted, and
    // drops it from the map. Runs only while something is snoozed.
    // haseen:sample
    Timer {
        interval: 20000
        repeat: true
        running: service.anySnooze
        onTriggered: {
            const now = Date.now() / 1000;
            const next = {};
            let dropped = false;
            for (const k in service.snoozes) {
                if (Number(service.snoozes[k].until || 0) > now)
                    next[k] = service.snoozes[k];
                else
                    dropped = true;
            }
            if (dropped) {
                service.snoozes = next;
                service.saveQuiet();
            }
            service.snoozeRevision += 1;
        }
    }

    // ------------------------------------------------------------- recent
    //
    // A session-only reading stack of notifications that were not quietened.
    // Text snapshots, never the live Notification objects or their actions.
    property var recentRows: []
    property int recentRevision: 0
    readonly property int recentLimit: 20

    function rememberRecent(row) {
        const key = String(row.key);
        const rows = [];
        if (!doNotDisturb && !globalSnoozeUntil && !snoozedUntil(row.groupKey)) {
            // Source matching uses a digest, so a sender-supplied code in a raw
            // group label is not retained.
            const sourceKey = Qt.md5(String(row.groupKey || ""));
            const clean = Store.sanitiseForPersistence(row);
            rows.push({
                key: key,
                sourceKey: sourceKey,
                source: String(clean.source || clean.app || "Notification").slice(0, 120),
                summary: String(clean.summary || "").slice(0, 240),
                bodyLine: String(clean.bodyLine || "").slice(0, 1000),
                ts: Number(clean.ts)
            });
        }
        // A replacement may move to a snoozed source: drop its old entry even
        // when the new version belongs only in Held Back.
        for (let i = 0; i < recentRows.length && rows.length < recentLimit; i++)
            if (recentRows[i].key !== key)
                rows.push(recentRows[i]);
        recentRows = rows;
        recentRevision += 1;
    }

    function forgetRecent(key) {
        const wanted = String(key);
        const rows = recentRows.filter(r => r.key !== wanted);
        if (rows.length === recentRows.length)
            return false;
        recentRows = rows;
        recentRevision += 1;
        return true;
    }

    function clearRecent() {
        if (!recentRows.length)
            return false;
        recentRows = [];
        recentRevision += 1;
        return true;
    }

    function recentForPanel(limit) {
        snoozeRevision;
        recentRevision;
        if (doNotDisturb || globalSnoozeUntil)
            return [];
        const excluded = Object.create(null);
        for (const s of liveSnoozes())
            excluded[Qt.md5(s.key)] = true;
        const rows = [];
        for (let j = 0; j < recentRows.length && rows.length < limit; j++)
            if (!excluded[recentRows[j].sourceKey])
                rows.push(recentRows[j]);
        return rows;
    }

    // ------------------------------------------------------------- store
    //
    // $HASEEN_USER_STATE/pager/: live.json (cards on screen, restored after a
    // shell restart), history.json (closed notifications, newest last, at most
    // 100 and `historyHours` old) and quiet.json (snoozes, when silencing
    // began, the code exception). Upstream's Python store did this; the rules
    // are Store.js, the writes are FileView setText, coalesced per event loop
    // turn.
    readonly property string stateDir: Paths.userState + "/pager"
    property bool _dirReady: false
    property var liveDisk: []
    property var historyDisk: []
    property int historyRevision: 0
    property int heldRevision: 0
    property bool _liveLoaded: false
    property bool _historyLoaded: false
    property bool _quietLoaded: false
    readonly property bool storeReady: _liveLoaded && _historyLoaded && _quietLoaded
    property var _dirty: ({})

    // The directory holds message text: private to the user.
    Process {
        command: ["mkdir", "-p", "-m", "700", "--", service.stateDir]
        running: true
        onExited: service._dirReady = true
    }

    FileView {
        id: liveFile

        path: service._dirReady ? service.stateDir + "/live.json" : ""
        printErrors: false
        onLoaded: {
            service.liveDisk = Store.parseFile(text());
            service._liveLoaded = true;
        }
        onLoadFailed: service._liveLoaded = true
    }

    FileView {
        id: historyFile

        path: service._dirReady ? service.stateDir + "/history.json" : ""
        printErrors: false
        onLoaded: {
            service.historyDisk = Store.parseFile(text());
            service._historyLoaded = true;
        }
        onLoadFailed: service._historyLoaded = true
    }

    FileView {
        id: quietFile

        path: service._dirReady ? service.stateDir + "/quiet.json" : ""
        printErrors: false
        onLoaded: {
            try {
                const read = JSON.parse(text() || "{}");
                if (read && typeof read === "object") {
                    if (read.snoozes && typeof read.snoozes === "object" && !Array.isArray(read.snoozes))
                        service.snoozes = read.snoozes;
                    // Only meaningful while the flag was on when it was saved.
                    service._savedDnd = read.dnd === true;
                    if (service._savedDnd && Number(read.silencedSince) > 0)
                        service.silencedSince = Number(read.silencedSince);
                    // Turned off in the panel, it stays off.
                    if (read.codesBypassQuiet !== undefined)
                        service.codesBypassQuiet = read.codesBypassQuiet === true;
                }
            } catch (e) {}
            service.snoozeRevision += 1;
            service._quietLoaded = true;
        }
        onLoadFailed: service._quietLoaded = true
    }

    onStoreReadyChanged: {
        if (!storeReady)
            return;
        if (doNotDisturb && silencedSince === 0)
            silencedSince = Date.now() / 1000;
        _savedDnd = doNotDisturb;
        saveQuiet();
        _trimDiskHistory();
        restoreRows(liveDisk, false);
    }

    function _markDirty(name: string): void {
        if (!storeReady)
            return;
        const d = Object.assign({}, _dirty);
        d[name] = true;
        _dirty = d;
        Qt.callLater(_flush);
    }

    function _flush(): void {
        const d = _dirty;
        _dirty = ({});
        if (d.live)
            liveFile.setText(JSON.stringify(liveDisk));
        if (d.history)
            historyFile.setText(JSON.stringify(historyDisk));
        if (d.quiet)
            quietFile.setText(JSON.stringify({
                snoozes: snoozes,
                dnd: doNotDisturb,
                silencedSince: silencedSince,
                codesBypassQuiet: codesBypassQuiet
            }));
    }

    function saveQuiet(): void {
        _markDirty("quiet");
    }

    function _trimDiskHistory(): void {
        if (!storeReady)
            return;
        const trimmed = Store.trimHistory(historyDisk, historyHours, Date.now() / 1000);
        if (trimmed.length !== historyDisk.length) {
            historyDisk = trimmed;
            historyRevision += 1;
            heldRevision += 1;
            _markDirty("history");
        }
    }

    function storePut(row): void {
        liveDisk = Store.putLive(liveDisk, row);
        _markDirty("live");
    }

    function storeClose(key: string, reason: string): void {
        const entry = liveDisk.find(e => e.key === key);
        if (!entry)
            return;
        liveDisk = Store.dropLive(liveDisk, key);
        _markDirty("live");
        historyDisk = Store.closeInto(historyDisk, entry, reason, historyHours, Date.now() / 1000);
        historyRevision += 1;
        if (reason === "snoozed" || reason === "silenced")
            heldRevision += 1;
        _markDirty("history");
    }

    // Newest first, as the panel shows them.
    readonly property var historyRows: {
        historyRevision;
        return Store.newest(historyDisk, 100, false);
    }
    readonly property var heldRows: {
        heldRevision;
        historyRevision;
        return Store.newest(historyDisk, 80, true);
    }

    function forgetHistory(): void {
        historyDisk = [];
        historyRevision += 1;
        heldRevision += 1;
        _markDirty("history");
    }

    // Everything quiet kept from you, gone at once. Read history (non-held
    // entries) and Recent are untouched.
    function clearHeld(): void {
        historyDisk = Store.forgetHeld(historyDisk);
        historyRevision += 1;
        heldRevision += 1;
        _markDirty("history");
    }

    // When the quiet holding this source began: the earliest of the reasons
    // currently in force.
    function quietSince(groupKey) {
        const entry = snoozes[String(groupKey || "")];
        const mine = entry && snoozedUntil(groupKey) ? Number(entry.since || 0) : 0;
        const global = globalSnoozeUntil ? Number((snoozes[globalKey] || {}).since || 0) : 0;
        const silence = doNotDisturb ? silencedSince : 0;
        const starts = [mine, global, silence].filter(t => t > 0);
        return starts.length ? Math.min.apply(null, starts) : 0;
    }

    function heldFor(groupKey, limit) {
        heldRevision;
        const since = quietSince(groupKey);
        const out = [];
        for (let i = 0; i < heldRows.length && out.length < limit; i++) {
            const row = heldRows[i];
            if (String(row.groupKey || "") !== String(groupKey))
                continue;
            if (since && Number(row.ts || 0) < since)
                continue;
            out.push(row);
        }
        return out;
    }

    // Every source being kept quiet right now, with what it has held. Sources
    // snoozed by name first, with their own wake time; then, while everything
    // is quiet, the sources that actually held something.
    function quietSources(limit) {
        snoozeRevision;
        heldRevision;
        const rows = [];
        const seen = {};
        for (const s of liveSnoozes()) {
            if (rows.length >= limit)
                break;
            seen[s.key] = true;
            rows.push({
                key: s.key,
                label: s.label,
                until: s.until,
                held: heldFor(s.key, heldPerSource)
            });
        }
        if (!doNotDisturb && !globalSnoozeUntil)
            return rows;
        for (let i = 0; i < heldRows.length && rows.length < limit; i++) {
            const key = String(heldRows[i].groupKey || "");
            if (!key || seen[key])
                continue;
            const held = heldFor(key, heldPerSource);
            if (!held.length)
                continue;
            seen[key] = true;
            rows.push({
                key: key,
                label: String(heldRows[i].source || heldRows[i].app || key),
                until: 0,
                held: held
            });
        }
        return rows;
    }

    // ------------------------------------------------------------- state
    //
    // The live Notification objects stay in a plain JS map, never in the
    // model: a QObject in a ListModel role becomes a dangling pointer once the
    // server destroys it.
    property var refs: ({})
    property int refsRevision: 0
    property int keySeed: 0

    ListModel {
        id: toasts

        onCountChanged: {
            if (count === 0)
                service.deckDisplayName = "";
        }
    }

    readonly property int toastCount: toasts.count

    // One reservation follows each row through held, deferred and visible
    // states; at most maxLiveNotifications at once.
    readonly property int maxLiveNotifications: 100
    property var liveKeys: Object.create(null)

    function liveCount() {
        return Object.keys(liveKeys).length;
    }

    function reserveLive(key) {
        if (!key)
            return false;
        if (liveKeys[key])
            return true;
        if (liveCount() >= maxLiveNotifications)
            return false;
        liveKeys[key] = {
            originalId: 0,
            row: null,
            scheduled: false,
            held: false
        };
        return true;
    }

    function releaseLive(key) {
        if (!liveKeys[key])
            return;
        delete liveKeys[key];
        held = held.filter(k => k !== key);
    }

    // ------------------------------------------------------------- icons
    //
    // Resolved once per source and remembered. Local only by default: your own
    // override files, the icon theme and desktop entries. With
    // `fetchRemoteIcons` (off by default: haseen is local-first) a web source
    // without a local icon gets https://<host>/favicon.ico, fetched once per
    // session into the cache.
    property var iconCache: ({})
    property int iconRevision: 0
    readonly property string userIconDir: Paths.userConfig + "/pager/icons"
    readonly property string remoteIconDir: (Quickshell.env("XDG_CACHE_HOME") || Paths.home + "/.cache") + "/haseen/pager/icons"
    // Plain JS state, mutated in place: iconsFor() runs inside the cards'
    // bindings and must not notify anything they read.
    property var fetchQueue: []
    property var fetchTried: ({})

    function setFetchRemoteIcons(enabled: bool): void {
        if (fetchIcons === enabled)
            return;
        fetchIcons = enabled;
        if (!enabled) {
            fetchQueue.length = 0;
            if (fetchProc.running)
                fetchProc.running = false;
        }
        _iconsChanged();
    }

    function _iconsChanged(): void {
        iconCache = ({});
        iconRevision += 1;
    }

    // Only files that exist become candidates: a missing one costs a log line
    // per card.
    IconDir {
        id: userIcons

        path: service.userIconDir
        onListingChanged: service._iconsChanged()
    }

    IconDir {
        id: remoteIcons

        path: service.remoteIconDir
        onListingChanged: service._iconsChanged()
    }

    function _slug(text) {
        return String(text || "").slice(0, 256).toLowerCase().replace(/[^a-z0-9._-]+/g, "-").replace(/^[-.]+|[-.]+$/g, "").slice(0, 100);
    }

    function _themeIcon(name) {
        const n = String(name || "").trim();
        if (!/^[A-Za-z0-9_-][A-Za-z0-9_.-]{0,255}$/.test(n))
            return "";
        return Quickshell.iconPath(n, true) || "";
    }

    // app.slack.com -> app.slack.com, slack. The middle label is almost always
    // the name of the thing. Never a parent domain.
    function _hostNames(source) {
        const host = Security.canonicalHostname(String(source || ""));
        if (!host)
            return [];
        const labels = host.split(".").filter(l => ["www", "app", "web", "my", "m"].indexOf(l) < 0);
        const names = [host];
        if (labels.length >= 2)
            names.push(labels[labels.length - 2]);
        if (labels.length)
            names.push(labels[0]);
        return names;
    }

    // Image URLs to try, best first; the card walks them until one loads.
    function iconsFor(row, revision) {
        const key = String(row.groupKey || row.source || row.app || "");
        if (!key)
            return [];
        if (iconCache[key])
            return iconCache[key];
        const web = _hostNames(row.source);
        const app = [row.appIcon, row.source, row.app].filter(n => !!n);
        const out = [];
        const add = url => {
            if (url && out.indexOf(url) < 0)
                out.push(url);
        };
        // Anything you dropped in $HASEEN_USER_CONFIG/pager/icons wins.
        for (const n of web.concat(app)) {
            const s = _slug(n);
            if (s)
                for (const ext of ["png", "svg"])
                    if (userIcons.names[s + "." + ext])
                        add(Paths.fileUrl(userIconDir + "/" + s + "." + ext));
        }
        // A web notification: the site first, never the browser showing it.
        for (const n of web)
            add(_themeIcon(n));
        const siteFound = out.length > 0;
        const cached = web.length > 0 && remoteIcons.names[web[0] + ".ico"] === true;
        if (cached)
            add(Paths.fileUrl(remoteIconDir + "/" + web[0] + ".ico"));
        // The name the sender passed, if this machine has it.
        if (row.appIcon && !web.length)
            add(_themeIcon(row.appIcon));
        for (const n of app) {
            add(_themeIcon(n));
            const entry = DesktopEntries.heuristicLookup(String(n));
            if (entry && entry.icon)
                add(String(entry.icon).charAt(0) === "/" ? Paths.fileUrl(entry.icon) : _themeIcon(entry.icon));
        }
        iconCache[key] = out;
        if (fetchIcons && web.length && !cached && !siteFound)
            _wantRemote(web[0]);
        return out;
    }

    function _wantRemote(host) {
        if (fetchTried[host] || fetchQueue.indexOf(host) >= 0 || fetchQueue.length >= 20)
            return;
        fetchQueue.push(host);
        Qt.callLater(_pumpFetch);
    }

    function _pumpFetch() {
        if (!fetchIcons || fetchProc.running || fetchQueue.length === 0)
            return;
        const host = fetchQueue.shift();
        fetchTried[host] = true;
        // HTTPS only (redirects too), TLS 1.2+, bounded size and time, no
        // cookies or credentials. The host passed Security.canonicalHostname,
        // which refuses IP literals. Skipped when the cache already has it.
        fetchProc.command = ["sh", "-c", "mkdir -p -m 700 -- \"$1\" && { test -s \"$1/$2.ico\" || { curl --proto =https --proto-redir =https --tlsv1.2 --max-redirs 3 --max-filesize 262144 --max-time 8 -fsSL -o \"$1/$2.ico.part\" \"https://$2/favicon.ico\" && mv -f -- \"$1/$2.ico.part\" \"$1/$2.ico\"; }; }; rm -f -- \"$1/$2.ico.part\"", "sh", remoteIconDir, host];
        fetchProc.running = true;
    }

    Process {
        id: fetchProc

        onExited: {
            // The cache directory may have just been created.
            remoteIcons.rescan();
            Qt.callLater(service._pumpFetch);
        }
    }

    // A single clock the cards' relative times hang off, running only while
    // cards are on screen.
    property double nowTick: Date.now()

    // haseen:sample
    Timer {
        interval: 20000
        repeat: true
        running: toasts.count > 0
        onTriggered: service.nowTick = Date.now()
    }

    // ------------------------------------------------------------- the deck
    //
    // Expansion is pointer containment, not a click, and it survives a short
    // trip outside: crossing a gap between two cards should not shut it.
    property bool pointerIn: false
    property bool expanded: false
    property string openDeck: ""
    property string hoverKey: ""
    property real hoverX: -1
    property real hoverY: -1
    property var heights: ({})
    property int layoutRevision: 0

    // haseen:ui-timeout
    Timer {
        id: collapseGrace

        interval: 120
        repeat: false
        onTriggered: {
            service.commit(() => {
                service.expanded = false;
                service.openDeck = "";
            });
            service.releaseHeld();
        }
    }

    // Notifications that arrived while the deck was held: a card appearing
    // under the pointer moves everything below it.
    property var held: []

    function holding() {
        return (pointerIn && expanded) || replyingKey !== "";
    }

    function releaseHeld() {
        if (!held.length)
            return;
        const queue = held;
        held = [];
        for (const k of queue) {
            const pending = liveKeys[k];
            if (!pending || !pending.row)
                continue;
            pending.held = false;
            showRow(pending.row);
        }
    }

    // Nothing waits forever: a pointer parked over the deck should not
    // silence the machine.
    // haseen:ui-timeout
    Timer {
        interval: 30000
        repeat: false
        running: service.held.length > 0
        onTriggered: service.releaseHeld()
    }

    function pointerEntered(deckKey) {
        collapseGrace.stop();
        if (expanded && (deckKey === undefined || openDeck === deckKey))
            return;
        commit(() => {
            service.expanded = true;
            if (deckKey !== undefined)
                service.openDeck = deckKey;
        });
    }

    function pointerLeft() {
        collapseGrace.restart();
    }

    function noteHeight(key, h) {
        if (Math.abs((heights[key] || 0) - h) < 0.5)
            return;
        commit(() => {
            service.heights[key] = h;
        });
    }

    // ------------------------------------------------------- the scene clock
    //
    // One clock for the whole deck. Every card's position, scale, opacity and
    // height is a function of where the layout wants it, where it was when
    // that last changed, and how far through the move we are.
    readonly property var sceneCurve: [0.21, 1.02, 0.73, 1.0, 1.0, 1.0]
    readonly property int sceneDuration: 320
    property real t: 1
    property var was: ({})
    property real deckWas: 0

    NumberAnimation {
        id: sceneRun

        target: service
        property: "t"
        from: 0
        to: 1
        duration: service.sceneDuration
        easing.type: Easing.Bezier
        easing.bezierCurve: service.sceneCurve
        onFinished: service.sceneSettled()
    }

    function at(key, what) {
        const target = placements[key];
        if (!target)
            return 0;
        const to = target[what];
        if (t >= 1)
            return to;
        const from = was[key];
        if (!from || from[what] === undefined)
            return to;
        return from[what] + (to - from[what]) * t;
    }

    readonly property real deckHeight: t >= 1 ? layout.height : deckWas + (layout.height - deckWas) * t

    // Where everything is at this instant, taken *before* the change.
    function snapshot() {
        const snap = {};
        for (const key in placements)
            snap[key] = {
                y: at(key, "y"),
                scale: at(key, "scale"),
                opacity: at(key, "opacity"),
                height: at(key, "height")
            };
        return snap;
    }

    // Anything that moves the deck goes through here: snapshot, change, one
    // move for all of it.
    function commit(change) {
        const snap = snapshot();
        const deckNow = deckHeight;
        change();
        retarget(undefined, undefined, snap, deckNow);
    }

    function retarget(seedKey, seed, snap, deckNow) {
        if (!snap) {
            snap = snapshot();
            deckNow = deckHeight;
        }
        if (seedKey)
            snap[seedKey] = seed;
        deckWas = deckNow;
        was = snap;
        layoutRevision += 1;
        t = 0;
        sceneRun.restart();
    }

    function restingPlace(key) {
        const prev = was[key];
        return {
            y: prev ? prev.y : 0,
            scale: prev ? prev.scale : 1,
            opacity: 0,
            height: prev ? prev.height : 0,
            z: 2000,
            front: true,
            hidden: false,
            count: 1
        };
    }

    // A row on its way out keeps its place until the move that closes the gap
    // has finished, so the fade and the gap are one motion.
    function sceneSettled() {
        const keys = Object.keys(leaving);
        if (!keys.length)
            return;
        for (const key of keys)
            finishClose(key, leaving[key]);
        const snap = {};
        for (const k in placements)
            snap[k] = {
                y: placements[k].y,
                scale: placements[k].scale,
                opacity: placements[k].opacity,
                height: placements[k].height
            };
        was = snap;
        t = 1;
    }

    readonly property var layout: {
        layoutRevision;
        const rows = [];
        for (let i = 0; i < toasts.count; i++) {
            const row = toasts.get(i);
            if (!leaving[row.key])
                rows.push(row);
        }
        return Layout.compute(rows, {
            stacking: stacking,
            expanded: expanded,
            openDeck: stacking === "source" ? openDeck : undefined,
            gap: gap,
            deckGap: gap * 2,
            heightOf: key => service.heights[key] || 58
        });
    }

    readonly property int shownCount: {
        let count = 0;
        for (const deck of layout.decks)
            count += deck.rows.length;
        return count;
    }
    readonly property string firstShownKey: layout.decks.length ? String(layout.decks[0].rows[0].key) : ""

    // Copied, not borrowed: writing into layout.placements would make this
    // binding mutate its own input.
    readonly property var placements: {
        const out = {};
        const base = layout.placements;
        for (const k in base)
            out[k] = base[k];
        for (const key in leaving)
            out[key] = restingPlace(key);
        return out;
    }

    // Our own identity for a notification: the sender's id is reused.
    function nextKey() {
        let key;
        do {
            keySeed += 1;
            key = "n" + Date.now().toString(36) + keySeed.toString(36);
        } while (liveKeys[key]);
        return key;
    }

    function rowIndexFor(key) {
        for (let i = 0; i < toasts.count; i++)
            if (toasts.get(i).key === key)
                return i;
        return -1;
    }

    // id 0 means "this is a new notification".
    function keyForOriginal(id) {
        if (!id)
            return "";
        for (const key in liveKeys)
            if (liveKeys[key].originalId === id && refs[key])
                return key;
        return "";
    }

    // ------------------------------------------------------------- arrival
    function handleNotification(notification) {
        const key = keyForOriginal(notification.id) || nextKey();
        if (!reserveLive(key)) {
            notification.tracked = false;
            return;
        }
        liveKeys[key].originalId = notification.id || 0;
        notification.tracked = true;

        const row = Store.snapshot(notification, key, NotificationUrgency);
        row.duration = durationFor(notification.urgency, row.expireTimeout);
        rememberRecent(row);

        const previous = refs[key];
        refs[key] = notification;
        refsRevision += 1;
        if (previous !== notification)
            watchNotification(notification, key);
        if (previous && previous !== notification) {
            try {
                previous.tracked = false;
            } catch (e) {}
        }

        // Silenced or snoozed still means recorded: it goes straight to
        // history. A sharing offer never changes delivery.
        let muted = doNotDisturb ? "silenced" : (globalSnoozeUntil || snoozedUntil(row.groupKey)) ? "snoozed" : "";
        if (muted && codesBypassQuiet && String(row.code || ""))
            muted = "";
        if (muted && notification.urgency !== NotificationUrgency.Critical) {
            storePut(row);
            storeClose(key, muted);
            release(key);
            if (rowIndexFor(key) < 0)
                releaseLive(key);
            else
                liveKeys[key].row = null;
            return;
        }

        storePut(row);
        lookForReply(row);

        // An update to something on screen goes through either way; only a
        // genuinely new card waits while the deck is being held.
        if (holding() && rowIndexFor(key) < 0) {
            const pending = liveKeys[key];
            pending.row = row;
            if (!pending.held) {
                pending.held = true;
                held = held.concat([key]);
            }
            return;
        }
        showRow(row);
    }

    function watchNotification(notification, key) {
        const reservation = liveKeys[key];
        notification.closed.connect(() => {
            if (service.refs[key] !== notification)
                return;
            delete service.refs[key];
            service.refsRevision += 1;
            // Visible snapshots outlive their sender; pending rows must not
            // appear after the sender withdraws them.
            if (service.rowIndexFor(key) < 0)
                service.finishClose(key, "closed");
        });
        // A replaces_id update mutates this QObject; snapshot once after the
        // whole update, not once per changed field.
        let queued = false;
        const refresh = () => {
            if (!queued)
                return;
            queued = false;
            if (reservation.refresh === refresh)
                reservation.refresh = null;
            if (service.liveKeys[key] !== reservation || service.refs[key] !== notification)
                return;
            service.handleNotification(notification);
        };
        const schedule = () => {
            if (queued || service.liveKeys[key] !== reservation || service.refs[key] !== notification)
                return;
            queued = true;
            reservation.refresh = refresh;
            Qt.callLater(refresh);
        };
        for (const sig of [notification.summaryChanged, notification.bodyChanged, notification.appNameChanged, notification.appIconChanged, notification.imageChanged, notification.urgencyChanged, notification.expireTimeoutChanged, notification.hintsChanged, notification.actionsChanged])
            sig.connect(schedule);
    }

    // Qt.callLater: mutating the model while a Repeater is mid-incubation
    // crashes.
    function showRow(row) {
        const key = String(row.key || "");
        if (!reserveLive(key))
            return;
        const pending = liveKeys[key];
        pending.row = row;
        pending.originalId = row.originalId || 0;
        if (pending.held) {
            pending.held = false;
            held = held.filter(k => k !== key);
        }
        if (pending.scheduled)
            return;
        pending.scheduled = true;
        Qt.callLater(() => {
            if (service.liveKeys[key] !== pending)
                return;
            if (pending.refresh)
                pending.refresh();
            pending.scheduled = false;
            if (service.liveKeys[key] !== pending || pending.held || !pending.row)
                return;
            const next = pending.row;
            pending.row = null;
            const index = service.rowIndexFor(key);
            const snap = service.snapshot();
            const deckNow = service.deckHeight;
            if (index >= 0) {
                Store.applyTo(toasts, index, next);
                service.retarget(undefined, undefined, snap, deckNow);
            } else {
                service.pinDeckDisplay();
                toasts.insert(0, next);
                // Where it comes from: above its landing place, transparent.
                const landing = service.layout.placements[key];
                service.retarget(key, {
                    y: (landing ? landing.y : 0) - 30,
                    scale: landing ? landing.scale : 1,
                    opacity: 0,
                    height: landing ? landing.height : 0
                }, snap, deckNow);
            }
        });
    }

    // Let go of the sender's object. Untracking tells it the notification
    // closed.
    function release(key, reason) {
        const ref = refs[key];
        if (!ref)
            return;
        delete refs[key];
        refsRevision += 1;
        try {
            if (reason === "expired")
                ref.expire();
            else if (reason)
                ref.dismiss();
            else
                ref.tracked = false;
        } catch (e) {}
    }

    // ------------------------------------------------------------- departure
    property var leaving: ({})

    function closeToast(key, reason) {
        if (leaving[key])
            return;
        if (rowIndexFor(key) < 0) {
            finishClose(key, reason || "dismissed");
            return;
        }
        const snap = snapshot();
        const deckNow = deckHeight;
        const next = Object.assign({}, leaving);
        next[key] = reason || "dismissed";
        leaving = next;
        retarget(key, snap[key], snap, deckNow);
    }

    function finishClose(key, reason) {
        if (replyingKey === key)
            replyingKey = "";
        const rest = {};
        for (const k in leaving)
            if (k !== key)
                rest[k] = leaving[k];
        leaving = rest;
        const index = rowIndexFor(key);
        if (!liveKeys[key])
            return;
        releaseLive(key);
        release(key, reason);
        if (index >= 0)
            toasts.remove(index);
        delete heights[key];
        storeClose(key, reason);
        layoutRevision += 1;
    }

    // Over a snapshot of the keys, never the model's count: closeToast marks
    // a row leaving and the row goes when the scene settles.
    function clearAll(reason) {
        const keys = Object.keys(liveKeys);
        for (const k of keys)
            closeToast(k, reason || "cleared");
    }

    // One stack: the open deck, else the newest card's.
    function clearDeck(reason) {
        const decks = layout.decks;
        if (decks.length === 0)
            return 0;
        let deck = decks[0];
        if (expanded)
            for (const d of decks)
                if (d.key === openDeck) {
                    deck = d;
                    break;
                }
        const keys = deck.rows.map(r => r.key);
        for (const k of keys)
            closeToast(k, reason || "cleared");
        return keys.length;
    }

    // "Clear all N" on the front card: every card shown, across sources; not
    // arrivals queued while held, and never while a reply is being typed.
    function dismissShown() {
        if (replyingKey !== "")
            return;
        const keys = [];
        for (const deck of layout.decks)
            for (const r of deck.rows)
                keys.push(r.key);
        for (const k of keys)
            closeToast(k, "dismissed");
    }

    function dismissOne() {
        for (let i = 0; i < toasts.count; i++) {
            const key = String(toasts.get(i).key);
            if (leaving[key])
                continue;
            closeToast(key, "dismissed");
            return true;
        }
        return false;
    }

    // What the sender said can be done. A restored row has no live sender,
    // so it has none of these.
    function actionsOf(key, revision) {
        const out = [];
        const ref = refs[key];
        if (!ref || !ref.actions)
            return out;
        for (let i = 0; i < Math.min(ref.actions.length, Security.MAX_ACTIONS); i++) {
            const a = ref.actions[i];
            const identifier = String(a.identifier || "");
            if (identifier.length > Security.MAX_ACTION_ID || !identifier)
                continue;
            if (identifier === "default") {
                out.push({
                    id: identifier,
                    text: "Open in app"
                });
                continue;
            }
            const label = Security.bounded(String(a.text || identifier), Security.MAX_ACTION_LABEL);
            if (hideSettingsAction && (/^settings$/i.test(label) || /^settings$/i.test(identifier)))
                continue;
            out.push({
                id: identifier,
                text: label
            });
        }
        return out;
    }

    function invokeAction(key, identifier) {
        if (typeof identifier !== "string" || identifier.length > Security.MAX_ACTION_ID)
            return;
        const ref = refs[key];
        if (ref && ref.actions) {
            for (let i = 0; i < Math.min(ref.actions.length, Security.MAX_ACTIONS); i++) {
                if (String(ref.actions[i].identifier) === identifier) {
                    try {
                        ref.actions[i].invoke();
                    } catch (e) {}
                    break;
                }
            }
        }
        closeToast(key, "activated");
    }

    // ------------------------------------------------------- source routing
    //
    // Which open window already shows the thing that notified you: the
    // sender's own window by pid, then a window whose class carries the
    // source, then (smartRaise) a browser tab whose title names it.
    function wordIn(text, word) {
        let at = text.indexOf(word);
        while (at >= 0) {
            const before = at === 0 ? "" : text.charAt(at - 1);
            const after = text.charAt(at + word.length);
            if (!/[a-z0-9]/.test(before) && !/[a-z0-9]/.test(after))
                return true;
            at = text.indexOf(word, at + 1);
        }
        return false;
    }

    function openWindows() {
        const list = Hyprland.toplevels ? Hyprland.toplevels.values : [];
        const out = [];
        for (const w of list) {
            const ipc = w.lastIpcObject;
            const wmClass = String((ipc && ipc["class"]) || "");
            if (wmClass)
                out.push({
                    wmClass: wmClass,
                    title: String((ipc && ipc.title) || ""),
                    address: String((ipc && ipc.address) || ""),
                    pid: Number((ipc && ipc.pid) || 0),
                    focusOrder: Number(ipc && ipc.focusHistoryID !== undefined ? ipc.focusHistoryID : 9999)
                });
        }
        return out;
    }

    readonly property var browserClasses: /^(chrome|chromium|firefox|zen|brave|edge|vivaldi|librewolf|helium)/
    readonly property var browserSuffix: /\s*[-\u2013\u2014|]\s*(google chrome|chromium|mozilla firefox|firefox|zen browser|brave|microsoft edge|vivaldi|librewolf)\s*$/
    readonly property var genericLabels: ({
            www: 1,
            app: 1,
            web: 1,
            my: 1,
            m: 1,
            mail: 1,
            com: 1,
            org: 1,
            net: 1,
            io: 1,
            co: 1,
            dev: 1,
            ai: 1,
            so: 1,
            site: 1,
            uk: 1
        })

    function brandsOf(host) {
        const labels = String(host || "").toLowerCase().split(".");
        const out = [];
        for (const l of labels)
            if (l.length >= 4 && !genericLabels[l]) {
                out.push(l);
                break;
            }
        const registered = labels.length >= 2 ? labels[labels.length - 2] : "";
        if (registered.length >= 4 && !genericLabels[registered] && out.indexOf(registered) < 0)
            out.push(registered);
        return out;
    }

    function windowForPid(pid) {
        const want = Number(pid || 0);
        if (!want)
            return null;
        return openWindows().find(w => w.pid === want) || null;
    }

    function mostRecent(candidates) {
        if (!candidates.length)
            return null;
        let best = candidates[0];
        for (const c of candidates)
            if (c.focusOrder < best.focusOrder)
                best = c;
        return best;
    }

    function windowForSource(source) {
        const name = String(source || "").toLowerCase();
        if (!name)
            return null;
        const windows = openWindows();
        let found = [];
        if (name.indexOf(".") > 0) {
            found = windows.filter(w => w.wmClass.toLowerCase().indexOf(name) >= 0);
            if (found.length)
                return mostRecent(found);
            if (!smartRaise)
                return null;
            for (const brand of brandsOf(name)) {
                found = windows.filter(w => browserClasses.test(w.wmClass.toLowerCase()) && wordIn(w.title.toLowerCase().replace(browserSuffix, ""), brand));
                if (found.length)
                    return mostRecent(found);
            }
            return null;
        }
        // Not a host: a phone-forwarded "WhatsApp". Whole labels only, four
        // characters or more.
        const slug = name.replace(/[^a-z0-9]+/g, "");
        if (slug.length < 4)
            return null;
        for (const w of windows) {
            const lower = w.wmClass.toLowerCase();
            if (lower === slug) {
                found.push(w);
                continue;
            }
            if (lower.indexOf("chrome-") !== 0)
                continue;
            if (lower.substring(7).split("__")[0].split(".").indexOf(slug) >= 0)
                found.push(w);
        }
        return mostRecent(found);
    }

    // By address, the only identity: dispatch arguments never carry text
    // from a window or a notification.
    function focusWindow(win) {
        if (!win || !/^0x[0-9a-f]+$/i.test(String(win.address || "")))
            return;
        Hyprland.dispatch(Hyprland.usingLua ? 'hl.dsp.focus({window = hl.get_window("address:' + win.address + '")})' : "focuswindow address:" + win.address);
    }

    function activate(key) {
        const index = rowIndexFor(key);
        const row = index >= 0 ? toasts.get(index) : null;
        const ref = refs[key];
        let handled = false;
        if (allowDefaultActionOnCardClick && ref && ref.actions) {
            for (let i = 0; i < Math.min(ref.actions.length, Security.MAX_ACTIONS); i++) {
                if (String(ref.actions[i].identifier) === "default") {
                    try {
                        ref.actions[i].invoke();
                        handled = true;
                    } catch (e) {}
                    break;
                }
            }
        }
        if (!handled && row) {
            // Source first, link last: a Slack message quoting a link is
            // still a Slack notification. The link has its own button.
            const win = windowForPid(row.senderPid) || windowForSource(row.source);
            if (win)
                focusWindow(win);
            else if (Markup.hostname(row.source))
                Security.openExternalUrl("https://" + Markup.hostname(row.source) + "/");
            else if (String(row.link || ""))
                Security.openExternalUrl(String(row.link));
        }
        closeToast(key, "activated");
    }

    // ------------------------------------------------------------- replying
    //
    // A message forwarded from the phone can be answered from here: KDE
    // Connect keeps an object per phone notification with a sendReply method,
    // and kdeconnect.sh matches our row to it by app name and text.
    readonly property string kdeBin: Qt.resolvedUrl("kdeconnect.sh").toString().replace(/^file:\/\//, "")
    property string replyingKey: ""
    property string replyError: ""
    property var replyQueue: []

    Process {
        id: replyProc

        property string replyKey: ""

        onExited: code => {
            if (code === 0) {
                service.replyingKey = "";
                service.closeToast(replyKey, "activated");
            } else {
                service.replyError = "Unable to safely identify reply target";
            }
        }
    }

    // A reply box holds the keyboard, so it must not hold it indefinitely.
    // haseen:ui-timeout
    Timer {
        interval: 120000
        repeat: false
        running: service.replyingKey !== ""
        onTriggered: service.replyingKey = ""
    }

    Process {
        id: findProc

        property var job: ({})

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const job = findProc.job || {};
                let path = "";
                let who = "";
                try {
                    const found = JSON.parse(String(text) || "{}");
                    path = String(found.path || "");
                    who = String(found.title || "");
                } catch (e) {}
                const index = service.rowIndexFor(String(job.key || ""));
                if (path && index >= 0) {
                    toasts.setProperty(index, "replyPath", path);
                    if (who)
                        toasts.setProperty(index, "replyTo", who);
                } else if (!path && index >= 0 && (job.tries || 0) < 1) {
                    // Once more in a moment: the phone's object may not exist yet.
                    job.tries = (job.tries || 0) + 1;
                    service.replyQueue = service.replyQueue.slice(0, 99).concat([job]);
                    replyRetry.restart();
                }
                Qt.callLater(service.pumpReplies);
            }
        }
    }

    function lookForReply(row) {
        if (!/kde\s*connect/i.test(String(row.app || "")))
            return;
        replyQueue = replyQueue.concat([
            {
                key: String(row.key || ""),
                source: String(row.source || ""),
                body: String(row.bodyLine || row.body || ""),
                tries: 0
            }
        ]);
        pumpReplies();
    }

    function pumpReplies() {
        if (findProc.running || replyQueue.length === 0)
            return;
        const job = replyQueue[0];
        replyQueue = replyQueue.slice(1);
        findProc.job = job;
        findProc.command = [kdeBin, "find", job.source, job.body];
        findProc.running = true;
    }

    // haseen:ui-timeout
    Timer {
        id: replyRetry

        interval: 1500
        repeat: false
        onTriggered: service.pumpReplies()
    }

    function sendReply(key, text) {
        const index = rowIndexFor(key);
        if (index < 0)
            return;
        const row = toasts.get(index);
        const path = String(row.replyPath || "");
        if (!path || !String(text).trim() || String(text).length > 4096 || replyProc.running)
            return;
        replyProc.replyKey = key;
        replyProc.command = [kdeBin, "reply", path, String(text), String(row.source), String(row.bodyLine)];
        replyProc.running = true;
    }

    // ------------------------------------------------------------- offers
    //
    // Acting on what Detect.js found: copy the code, open the link. The offer
    // is a click, never automatic.
    property string secretHeld: ""
    property string _clipValue: ""

    Process {
        id: clipProc

        // wl-clipboard is a haseen package; if wl-copy fails anyway, Qt holds
        // the selection instead (without the sensitive hint).
        onExited: code => {
            if (code !== 0 && service._clipValue)
                Quickshell.clipboardText = service._clipValue;
            service._clipValue = "";
        }
    }

    // A verification code is not clipboard history material: wl-copy
    // --sensitive marks it, and it is cleared once it has had time to be used.
    function copyText(text, sensitive) {
        const value = String(text || "");
        if (!value || value.length > (sensitive ? 64 : 4096))
            return;
        const args = ["wl-copy"];
        if (sensitive)
            args.push("--sensitive");
        args.push("--", value);
        clipProc.running = false;
        _clipValue = value;
        clipProc.command = args;
        clipProc.running = true;
        if (sensitive) {
            secretHeld = value;
            secretLife.restart();
        }
    }

    // haseen:ui-timeout
    Timer {
        id: secretLife

        interval: service.clipboardTimeout * 1000
        repeat: false
        onTriggered: clipReader.running = true
    }

    // Only clear it if it is still the thing on the clipboard.
    Process {
        id: clipReader

        command: ["wl-paste", "--no-newline"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (service.secretHeld && String(text) === service.secretHeld) {
                    clipProc.running = false;
                    service._clipValue = "";
                    clipProc.command = ["wl-copy", "--clear"];
                    clipProc.running = true;
                }
                service.secretHeld = "";
            }
        }
    }

    function takeOffer(kind, value, key) {
        if (kind === "code") {
            const index = rowIndexFor(String(key || ""));
            if (index < 0 || String(toasts.get(index).codes).split(" ").indexOf(String(value)) < 0)
                return;
            copyText(value, true);
        } else if (kind === "phone") {
            copyText(value, false);
        } else {
            Security.openExternalUrl(value);
        }
        // A copied code is a finished notification - unless it carried more
        // than one. Long enough after the press for the tick to be seen.
        if (kind === "code" && String(key || "")) {
            const index = rowIndexFor(String(key));
            const several = index >= 0 && String(toasts.get(index).codes || "").indexOf(" ") > 0;
            if (!several) {
                codeTaken.keys = codeTaken.keys.concat([String(key)]);
                codeTaken.restart();
            }
        }
    }

    // haseen:ui-timeout
    Timer {
        id: codeTaken

        property var keys: []

        interval: 900
        repeat: false
        onTriggered: {
            const pending = keys;
            keys = [];
            for (const k of pending)
                service.closeToast(k, "activated");
        }
    }

    // ------------------------------------------------------------- restore
    function restoreRows(rows, replay) {
        // Restore is oldest first; history (replay) is newest first.
        for (let i = replay ? rows.length - 1 : 0; replay ? i >= 0 : i < rows.length; i += replay ? -1 : 1) {
            const row = Store.restored(rows[i]);
            if (!row)
                continue;
            if (liveKeys[row.key]) {
                if (!replay)
                    continue;
                row.key = nextKey();
            }
            if (!reserveLive(row.key))
                break;
            if (replay)
                storePut(row);
            showRow(row);
        }
    }

    // Put the last few back on screen, as restored rows: no live sender and a
    // short grace rather than their original timeout.
    readonly property int replayCount: 6

    function replayHistory() {
        restoreRows(Store.newest(historyDisk, replayCount, false), true);
    }

    // ------------------------------------------------------------- server
    NotificationServer {
        id: server

        keepOnReload: false
        imageSupported: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        persistenceSupported: true

        onNotification: notification => service.handleNotification(notification)
    }

    // ------------------------------------------------------------- IPC
    //
    // `pager`: upstream's scripting verbs (its `omapager` target and the
    // Omarchy `notifications` keybinding verbs). Every verb returns a string.
    IpcHandler {
        target: "pager"

        function count(): string {
            return String(toasts.count);
        }

        function probe(): string {
            return JSON.stringify({
                toasts: toasts.count,
                doNotDisturb: service.doNotDisturb,
                expanded: service.expanded,
                stacking: service.stacking,
                fontScale: service.fontScale,
                fetchRemoteIcons: service.fetchIcons,
                allowDefaultActionOnCardClick: service.allowDefaultActionOnCardClick,
                sharingActive: service.sharingActive,
                sharingStreams: service.sharingStreams,
                sharingOfferPending: service.sharingOfferPending,
                offerSnoozeWhenSharing: service.offerSnoozeWhenSharing,
                globalSnoozeUntil: service.globalSnoozeUntil,
                codesBypassQuiet: service.codesBypassQuiet,
                displayMode: service.displayMode,
                displayName: service.displayName,
                displays: service.displayNames,
                focusedDisplay: service.focusedDisplayName,
                targetDisplay: service.targetDisplayName,
                notificationDisplays: service.displayNames.filter(n => service.showsOn(n)),
                avoidFullscreen: service.avoidFullscreen,
                avoidedDisplays: service.displayNames.filter(n => service.awayFrom(n)),
                recent: service.recentRows.length,
                history: service.historyDisk.length,
                held: service.heldRows.length,
                storeReady: service.storeReady,
                role: Plugins.roles.notifications ? Plugins.roles.notifications.id : ""
            });
        }

        // The cards on screen, newest first, for a script to check.
        function cards(): string {
            const out = [];
            for (let i = 0; i < toasts.count; i++) {
                const r = toasts.get(i);
                out.push({
                    key: r.key,
                    source: r.source,
                    groupKey: r.groupKey,
                    summary: r.summary,
                    urgency: r.urgency,
                    actions: service.actionsOf(r.key, service.refsRevision).map(a => a.id),
                    leaving: !!service.leaving[r.key]
                });
            }
            return JSON.stringify(out);
        }

        function clear(): string {
            service.clearAll("cleared");
            return "ok";
        }

        function dnd(): string {
            // Flags writes the file asynchronously: answer with the new state.
            const want = !service.doNotDisturb;
            service.setDoNotDisturb(want);
            return want ? "on" : "off";
        }

        // Drive the deck without a pointer.
        function expand(): string {
            if (service.expanded) {
                service.commit(() => {
                    service.expanded = false;
                    service.openDeck = "";
                    service.hoverKey = "";
                });
            } else if (toasts.count > 0) {
                const front = toasts.get(0);
                service.pointerEntered(Layout.deckKeyFor(front, service.stacking));
                service.hoverKey = String(front.key);
            } else {
                service.pointerEntered(undefined);
            }
            return service.expanded ? "expanded" : "collapsed";
        }

        // Snooze the front card's source, in minutes.
        function snooze(minutes: string): string {
            if (toasts.count === 0)
                return "nothing";
            const row = toasts.get(0);
            const mins = Number(minutes) > 0 ? Number(minutes) : 60;
            const until = service.snoozeSource(String(row.groupKey || ""), String(row.source || row.app || ""), mins * 60);
            return until ? (String(row.source || row.app) + " until " + new Date(until * 1000).toTimeString().slice(0, 5)) : "no source";
        }

        // Snooze everything, or wake it when it already is.
        function snoozeAll(minutes: string): string {
            if (service.globalSnoozeUntil) {
                service.unsnooze(service.globalKey);
                return "awake";
            }
            const mins = Number(minutes) > 0 ? Number(minutes) : 60;
            const until = service.snoozeSource(service.globalKey, "Everything", mins * 60, true);
            return until ? ("everything until " + new Date(until * 1000).toTimeString().slice(0, 5)) : "no";
        }

        function unsnooze(key: string): string {
            if (!String(key || "")) {
                service.unsnoozeAll();
                return "all";
            }
            service.unsnooze(String(key));
            return String(key);
        }

        function snoozes(): string {
            return JSON.stringify(service.liveSnoozes());
        }

        function codes(state: string): string {
            const want = String(state || "").toLowerCase();
            if (want === "on" || want === "off")
                service.setCodesBypassQuiet(want === "on");
            return service.codesBypassQuiet ? "on" : "off";
        }

        function open(deckKey: string): string {
            service.pointerEntered(deckKey);
            return service.openDeck;
        }

        // Invoke one of the sender's actions on the front card.
        function act(identifier: string): string {
            if (toasts.count === 0)
                return "nothing";
            const key = String(toasts.get(0).key);
            const available = service.actionsOf(key, service.refsRevision);
            let wanted = String(identifier || "");
            if (!wanted && available.length > 0)
                wanted = available[0].id;
            if (!wanted)
                return "no actions";
            service.invokeAction(key, wanted);
            return wanted;
        }

        // Take one of the front card's offers: code, link or phone.
        function offer(kind: string): string {
            if (toasts.count === 0)
                return "nothing";
            const row = toasts.get(0);
            const want = String(kind || "code");
            const value = want === "code" ? String(row.code || "") : want === "phone" ? String(row.phone || "") : String(row.link || "");
            if (!value)
                return "none";
            service.takeOffer(want, value, String(row.key));
            return "performed";
        }

        function align(side: string): string {
            if (side === "left" || side === "right")
                service.actionsAlign = side;
            return service.actionsAlign;
        }

        function stack(mode: string): string {
            if (mode === "all" || mode === "source")
                service.commit(() => {
                    service.stacking = mode;
                });
            return service.stacking;
        }

        // Answer the front card; "" just opens the field.
        function reply(text: string): string {
            if (toasts.count === 0)
                return "nothing";
            const key = String(toasts.get(0).key);
            if (!String(toasts.get(0).replyPath || ""))
                return "not repliable";
            if (!String(text || "").trim()) {
                service.replyingKey = key;
                service.pointerEntered(Layout.deckKeyFor(toasts.get(0), service.stacking));
                service.hoverKey = key;
                return "open";
            }
            service.sendReply(key, String(text));
            return "sent";
        }

        function dismissOne(): string {
            return service.dismissOne() ? "ok" : "none";
        }

        function dismissAll(): string {
            service.clearDeck("dismissed");
            return "ok";
        }

        function dismissShown(): string {
            service.dismissShown();
            return "ok";
        }

        function invokeLast(): string {
            if (toasts.count === 0)
                return "none";
            service.activate(String(toasts.get(0).key));
            return "ok";
        }

        function showHistory(): string {
            service.replayHistory();
            return "ok";
        }

        // Forgets what was recorded on disk. What is on screen stays.
        function forgetHistory(): string {
            service.forgetHistory();
            return "ok";
        }

        // Take every card whose summary contains `summary` off the screen.
        function dismiss(summary: string): string {
            const needle = String(summary || "");
            if (!needle)
                return "none";
            const keys = [];
            for (let i = 0; i < toasts.count; i++)
                if (String(toasts.get(i).summary || "").indexOf(needle) !== -1)
                    keys.push(String(toasts.get(i).key));
            for (const k of keys)
                service.closeToast(k, "dismissed");
            return keys.length ? "ok" : "none";
        }

        // The Recent stack: no argument lists it, `clear` empties it, anything
        // else dismisses the first entry whose summary contains it.
        function recent(action: string): string {
            const wanted = String(action || "");
            const rows = service.recentForPanel(service.recentCount);
            if (!wanted)
                return JSON.stringify(rows.map(r => ({
                                key: r.key,
                                source: r.source,
                                summary: r.summary
                            })));
            if (wanted === "clear")
                return service.clearRecent() ? "cleared" : "empty";
            for (const r of rows)
                if (r.summary.indexOf(wanted) >= 0)
                    return service.forgetRecent(r.key) ? "dismissed" : "gone";
            return "no such notification";
        }

        function refreshFullscreen(): string {
            hyprRefresh.restart();
            return "ok";
        }
    }

    // ------------------------------------------------------------- surface
    //
    // One fixed-width layer per output that shows notifications, created
    // while there is something on it and kept for the last card's exit
    // animation. The mask keeps everything outside the deck click-through.
    readonly property bool hasSomethingToShow: toasts.count > 0 || replyingKey !== ""
    property bool lingering: false

    onHasSomethingToShowChanged: {
        lingering = !hasSomethingToShow;
        if (lingering)
            lingerTimer.restart();
    }

    // haseen:ui-timeout
    Timer {
        id: lingerTimer

        interval: 800
        repeat: false
        onTriggered: service.lingering = false
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: surfaceLoader

            required property var modelData
            readonly property bool showing: service.showsOn(String(modelData.name))

            active: showing && (service.hasSomethingToShow || service.lingering)

            PanelWindow {
                id: surface

                screen: surfaceLoader.modelData
                color: "transparent"
                anchors {
                    top: true
                    bottom: true
                    right: true
                }
                implicitWidth: clipper.width + 10
                WlrLayershell.namespace: "haseen-pager"
                WlrLayershell.layer: WlrLayer.Overlay
                // Exclusive only while a reply is being typed (a keybinding or
                // the IPC verb can open it, and OnDemand would ignore typing);
                // Escape, sending and the 2-minute timeout all end it.
                WlrLayershell.keyboardFocus: service.replyingKey !== "" ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
                exclusiveZone: 0
                mask: Region {
                    item: deck
                }

                Item {
                    id: clipper

                    readonly property int motionInset: 4

                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: service.edgeSpacing
                    width: service.cardWidth + motionInset + service.edgeSpacing
                    height: deck.y + deck.height + motionInset
                    clip: true

                    Item {
                        id: deck

                        x: clipper.motionInset
                        width: service.cardWidth
                        height: service.deckHeight

                        // One hover region for the whole deck, above the cards:
                        // moving between two cards must not leave and re-enter.
                        // It accepts no buttons, so clicks fall through.
                        MouseArea {
                            id: hoverArea

                            function hoverAt(x, y) {
                                service.hoverX = x;
                                service.hoverY = y;
                                const places = service.placements;
                                let found = "";
                                for (const key in places) {
                                    const pl = places[key];
                                    if (pl.hidden)
                                        continue;
                                    const h = pl.height || 58;
                                    if (y >= pl.y && y <= pl.y + h) {
                                        found = key;
                                        break;
                                    }
                                }
                                service.hoverKey = found;
                            }

                            z: 5000
                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            propagateComposedEvents: true

                            onContainsMouseChanged: {
                                service.pointerIn = containsMouse;
                                if (containsMouse) {
                                    service.pointerEntered(undefined);
                                    hoverAt(mouseX, mouseY);
                                } else {
                                    service.hoverKey = "";
                                    service.pointerLeft();
                                }
                            }
                            onPositionChanged: mouse => {
                                hoverAt(mouse.x, mouse.y);
                                // In source mode, which deck you are over opens.
                                if (service.stacking !== "source")
                                    return;
                                for (const d of service.layout.decks) {
                                    const first = d.rows[0];
                                    const place = service.layout.placements[first.key];
                                    if (!place)
                                        continue;
                                    const top = place.y;
                                    const bottom = top + (service.heights[first.key] || 58);
                                    if (mouse.y >= top - 6 && mouse.y <= bottom + 6) {
                                        service.pointerEntered(d.key);
                                        return;
                                    }
                                }
                            }

                            // Cards can move under a stationary pointer after a
                            // dismissal; refresh what is under it.
                            Connections {
                                target: sceneRun
                                function onFinished() {
                                    Qt.callLater(() => {
                                        if (hoverArea.containsMouse)
                                            hoverArea.hoverAt(hoverArea.mouseX, hoverArea.mouseY);
                                    });
                                }
                            }
                        }

                        Repeater {
                            model: toasts

                            Toast {
                                required property var model

                                row: model
                                icons: service.iconsFor(model, service.iconRevision)
                                iconRevision: service.iconRevision
                                scene: service
                                cardWidth: deck.width
                                place: service.placements[model.key] || ({
                                        y: 0,
                                        scale: 1,
                                        opacity: 0,
                                        z: 1,
                                        front: false,
                                        hidden: true
                                    })
                                hovered: service.hoverKey === model.key
                                bulkCount: service.replyingKey === "" && model.key === service.firstShownKey ? service.shownCount : 0
                                actions: service.actionsOf(model.key, service.refsRevision)
                                fontScale: service.fontScale
                                showCountdown: service.showCountdown
                                actionsAlign: service.actionsAlign
                                replyError: service.replyingKey === model.key ? service.replyError : ""
                                replying: service.replyingKey === model.key
                                hoverX: service.hoverX
                                hoverY: service.hoverY
                                now: service.nowTick
                                expanded: service.expanded && (service.stacking !== "source" || service.openDeck === Layout.deckKeyFor(model, service.stacking))
                                sole: toasts.count === 1
                                // Nothing counts down while the deck is open or
                                // an answer is half typed.
                                paused: service.expanded || service.replyingKey !== ""
                                drawnHeight: service.at(model.key, "height")
                                snoozeOptions: service.snoozeOptions

                                onTargetHeightChanged: service.noteHeight(model.key, targetHeight)
                                Component.onCompleted: service.noteHeight(model.key, targetHeight)
                                onDismissAllRequested: service.dismissShown()
                                onReplyRequested: {
                                    service.replyError = "";
                                    service.replyingKey = model.key;
                                    service.pointerEntered(Layout.deckKeyFor(model, service.stacking));
                                    service.hoverKey = String(model.key);
                                }
                                onReplySent: text => service.sendReply(model.key, text)
                                onReplyCancelled: service.replyingKey = ""
                                onActionInvoked: identifier => service.invokeAction(model.key, identifier)
                                onOfferTaken: (kind, value) => service.takeOffer(kind, value, model.key)
                                onExpired: service.closeToast(model.key, "expired")
                                onActivated: service.activate(model.key)
                                onDismissed: service.closeToast(model.key, "dismissed")
                                onSnoozeRequested: seconds => service.snoozeSource(String(model.groupKey || ""), String(model.source || model.app || ""), seconds)
                                onSilenceRequested: service.setDoNotDisturb(true)
                            }
                        }
                    }
                }
            }
        }
    }
}
