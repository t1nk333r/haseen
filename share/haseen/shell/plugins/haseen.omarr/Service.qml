import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.omarr service (role `omarr`): polls the configured *arr stack, keeps
// one snapshot per service, sends the event notifications and the live
// download card, and publishes feed.json. Created once per shell while the
// plugin is enabled and listed in `services`; the bar widget (one per screen)
// and the lazily loaded panel read it through Plugins.roles.omarr.
//
// Adapted from Service.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes:
// - settings are the manifest's (shell.json plugins."haseen.omarr".settings),
//   written through `haseen plugin settings` instead of Omarchy's
//   updateEntryInline, and applied at once through Config.setRuntime;
// - the private state directory is $XDG_STATE_HOME/haseen/omarr, unless a HOME
//   already keeps upstream's ~/.local/state/omarchy/omarr and has no haseen
//   one: that one is then used where it is (Model.chooseStateDir), so stored
//   API keys and passwords are never copied or moved;
// - notifications go through `haseen notification send` (the shell's own
//   notification server and its history), and the download card is one such
//   notification updated in place instead of a window of its own;
// - pages open through Apps.launch, outside the shell's cgroup;
// - the 2 s downloader poll runs only while a client reported an active job
//   or the panel is open, instead of always (architecture 6).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property string pluginDir: Paths.builtinPlugins + "/haseen.omarr"
    // With the debugIpc test hook on, the IPC target below answers state().
    readonly property bool debugIpc: settings.debugIpc === true

    property bool panelOpen: false
    property int pollElapsed: 0 // seconds towards the next regular poll
    property bool scanning: false
    property var scanResults: []
    property var credentials: ({})
    property var seenIds: []
    property var snapshots: []
    property var nowFeed: ({ downloads: [], calendar: [], warnings: [], sessions: [], onDeck: [], recent: [], downloadingCount: 0, downCount: 0 })
    property var qbitReady: ({})
    property var detailQueue: []
    property int detailQueuePage: 1
    property int detailQueueTotal: 0
    property string detailQueueId: ""
    property string statusText: "omARR"
    property int unreadCount: 0
    property var artReady: ({})
    property var artPending: ({})
    property var artRev: ({})
    property var onDeckFeed: []
    property var recentFeed: []
    property var calendarFeed: []
    property int badgeCount: 0
    property bool badgeUrgent: false
    property bool seeding: true
    property bool dirsReady: false
    property var writeQueue: []
    property string pendingWriteText: ""
    property string pendingWriteThen: ""
    property string progressDismissedKey: ""
    property var progressJob: null
    // Feed export bookkeeping: when feed.json was last written and the material
    // signature it was written from (see publishFeed).
    property double feedWrittenAt: 0
    property string feedSignature: ""
    // Every notification argv sent, newest last, for the debug hook.
    property var sentNotes: []

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string haseenStateDir: Paths.userState + "/omarr"
    readonly property string legacyStateDir: home + "/.local/state/omarchy/omarr"
    // Chosen once at start (stateProbe below); "" until then.
    property string stateDir: ""
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/haseen/omarr"
    readonly property string credsPath: stateDir === "" ? "" : stateDir + "/credentials.json"
    readonly property string seenPath: stateDir === "" ? "" : stateDir + "/seen.json"
    readonly property string headerPath: cacheDir + "/header.txt"
    readonly property string bodyPath: cacheDir + "/body.txt"

    // A settings change shows at once: it is applied to the running shell
    // through Config.setRuntime and kept here while its write is queued, so a
    // shell.json reload in between cannot show the old value.
    property var pendingSettings: null
    readonly property var pluginSettings: Model.pluginSettings(pendingSettings !== null ? pendingSettings : settings)
    readonly property var services: pluginSettings.services
    readonly property int pollSeconds: pluginSettings.pollSeconds
    readonly property int pageSize: pluginSettings.pageSize
    readonly property string density: pluginSettings.density
    readonly property bool showProgressToast: pluginSettings.showProgressToast !== false
    readonly property bool configured: services.length > 0
    // A client reported an active download at the last poll.
    readonly property bool downloadsActive: Model.downloaderBusy(snapshots)

    property var reqQueue: []
    property var currentReq: null
    property var snapshotMap: ({})
    property var healthMisses: ({})

    function setPanelOpen(open: bool): void {
        root.panelOpen = open;
    }

    function cookiePath(id) {
        return cacheDir + "/qbit-" + String(id || "").replace(/[^A-Za-z0-9._-]/g, "_") + ".cookies";
    }

    function serviceById(id) {
        const key = String(id || "");
        for (let i = 0; i < root.services.length; i++) {
            if (root.services[i].id === key)
                return root.services[i];
        }
        return null;
    }

    function iconPath(serviceOrEvent) {
        const slug = Model.iconSlug(serviceOrEvent || {});
        return slug ? root.pluginDir + "/icons/" + slug + ".svg" : "";
    }

    // ---- Settings writes. Each change sends the whole payload, in order,
    // through `haseen plugin settings` (arrays replace, so a removed service
    // stays removed).
    property var settingsWrites: []
    property var settingsWriting: null

    function persistSettings(values) {
        const current = Model.normalizeSettings(root.pluginSettings);
        const extra = values && typeof values === "object" ? values : {};
        for (const key in extra)
            current[key] = extra[key];
        const payload = Model.settingsPayload(current);
        root.pendingSettings = payload;
        Config.setRuntime(["plugins", root.pluginId, "settings"], payload);
        root.settingsWrites = root.settingsWrites.concat([payload]);
        root.startSettingsWrite();
    }

    function startSettingsWrite() {
        if (root.settingsWriting !== null || root.settingsWrites.length === 0)
            return;
        root.settingsWriting = root.settingsWrites[0];
        root.settingsWrites = root.settingsWrites.slice(1);
        settingsWriter.command = [root.binDir + "/haseen-plugin-settings", root.pluginId, "--yes"];
        settingsWriter.running = true;
    }

    function finishSettingsWrite(ok: bool) {
        if (!ok)
            console.warn("haseen.omarr: settings were not saved:", settingsErr.text);
        root.settingsWriting = null;
        if (root.settingsWrites.length === 0 && root.pendingSettings !== null) {
            // A shell.json reload may have cleared the runtime layer before
            // the newest write landed; reassert it, then let the file speak.
            Config.setRuntime(["plugins", root.pluginId, "settings"], root.pendingSettings);
            root.pendingSettings = null;
        }
        Qt.callLater(root.startSettingsWrite);
    }

    function persistCredentials() {
        root.enqueueWrite(root.stateDir, "credentials.json", Model.serializeCredentials(root.credentials), "");
    }

    function persistSeen() {
        root.enqueueWrite(root.stateDir, "seen.json", Model.serializeSeenFile(root.seenIds), "");
    }

    function enqueueWrite(dir, name, text, thenKind) {
        root.writeQueue = root.writeQueue.concat([{
                dir: dir,
                name: name,
                text: String(text || ""),
                thenKind: String(thenKind || "")
            }]);
        root.pumpWrites();
    }

    function pumpWrites() {
        if (secretProc.running || !root.writeQueue.length)
            return;
        const next = root.writeQueue[0];
        root.writeQueue = root.writeQueue.slice(1);
        root.pendingWriteText = next.text;
        root.pendingWriteThen = next.thenKind;
        secretProc.command = Model.atomicWriteCmd(next.dir, next.name, Model.utf8ByteLength(next.text));
        secretProc.running = true;
    }

    function persistCredential(id, patch) {
        root.credentials = Model.setCredential(root.credentials, id, patch);
        persistCredentials();
    }

    function addService(draft, creds) {
        const next = Model.addService(root.pluginSettings, draft);
        persistSettings(next);
        if (creds && next.services.length) {
            const added = next.services[next.services.length - 1];
            persistCredential(added.id, creds);
        }
        Qt.callLater(root.forcePoll);
    }

    function updateService(id, patch, creds) {
        persistSettings(Model.updateService(root.pluginSettings, id, patch));
        if (creds)
            persistCredential(id, creds);
        Qt.callLater(root.forcePoll);
    }

    function removeService(id) {
        persistSettings(Model.removeService(root.pluginSettings, id));
        const creds = {};
        for (const key in root.credentials) {
            if (key === String(id))
                continue;
            creds[key] = root.credentials[key];
        }
        root.credentials = creds;
        persistCredentials();
        Qt.callLater(root.rebuildSnapshots);
    }

    function moveService(id, delta) {
        persistSettings(Model.moveService(root.pluginSettings, id, delta));
    }

    function openUrl(url) {
        const cmd = Model.openItemCommand(url);
        if (cmd.length)
            Apps.launch(cmd);
    }

    function openService(id) {
        const snap = Model.snapshotById(root.snapshots, id);
        if (snap && snap.url)
            root.openUrl(snap.url);
    }

    function openItem(item, serviceId) {
        const snap = Model.snapshotById(root.snapshots, serviceId || (item && item.serviceId) || "");
        root.openUrl(Model.itemOpenUrl(snap, item));
    }

    function cred(id) {
        return Model.credentialFor(root.credentials, id);
    }

    function enqueue(req) {
        root.reqQueue = root.reqQueue.concat([req]);
        root.pump();
    }

    function pump() {
        if (!root.dirsReady || apiProc.running || secretProc.running || root.writeQueue.length)
            return;
        if (!root.reqQueue.length) {
            root.refreshDerived();
            return;
        }
        const next = root.reqQueue[0];
        root.reqQueue = root.reqQueue.slice(1);
        root.startReq(next);
    }

    function startReq(req) {
        root.currentReq = req;
        if (req.headerText) {
            req.useCurlConfig = Model.headerIsConfig(req.headerText);
            const header = req.useCurlConfig ? Model.curlHeaderConfig(req.headerText) : req.headerText;
            root.enqueueWrite(root.cacheDir, "header.txt", header, req.bodyText ? "body" : "curl");
            return;
        }
        if (req.bodyText) {
            root.enqueueWrite(root.cacheDir, "body.txt", req.bodyText, "curl");
            return;
        }
        root.runCurl(req);
    }

    function setHealthMisses(id, n) {
        const next = {};
        for (const key in root.healthMisses)
            next[key] = root.healthMisses[key];
        next[String(id)] = n;
        root.healthMisses = next;
    }

    function commitHealth(service, snap, statusCode) {
        const decision = Model.decideHealth(root.snapshotFor(service).health, statusCode, root.healthMisses[service.id] || 0);
        root.setHealthMisses(service.id, decision.misses);
        if (!decision.commit)
            return false;
        root.commitSnapshot(Model.applyHttpHealth(snap, statusCode), service);
        return true;
    }

    function commitIdentity(service, snap, statusCode, info) {
        const decision = Model.decideHealth(root.snapshotFor(service).health, statusCode, root.healthMisses[service.id] || 0);
        root.setHealthMisses(service.id, decision.misses);
        if (!decision.commit)
            return;
        if (statusCode < 200 || statusCode >= 400) {
            root.commitSnapshot(Model.applyHttpHealth(snap, statusCode), service);
            return;
        }
        const next = Model.applyHttpHealth(snap, statusCode);
        const row = info && typeof info === "object" ? info : {};
        next.version = String(row.version || "");
        next.statusText = String(row.statusText || next.version || "Reachable");
        if (row.machineId)
            next.machineId = String(row.machineId);
        root.commitSnapshot(next, service);
    }

    // Keys and passwords never reach argv: headers and form bodies go through
    // 0600 files in the 0700 cache directory (Model.atomicWriteCmd).
    function runCurl(req) {
        if (!req || !Model.isHttpUrl(req.url)) {
            Qt.callLater(root.pump);
            return;
        }
        const max = req.image ? Model.IMAGE_MAX_BYTES : Model.API_MAX_BYTES;
        let cmd = ["curl", "-sS", "-w", "\n%{http_code}", "--proto", "=http,https"];
        cmd = cmd.concat(req.scan ? Model.scanCurlBounds() : Model.curlBounds(max));
        if (req.method === "POST")
            cmd.push("-X", "POST");
        if (req.headerText) {
            if (req.useCurlConfig)
                cmd.push("--config", root.headerPath);
            else
                cmd.push("-H", "@" + root.headerPath);
        }
        if (req.bodyText) {
            cmd.push("-H", "Content-Type: application/x-www-form-urlencoded");
            cmd.push("--data-binary", "@" + root.bodyPath);
        }
        const wrap = req.outputPath || req.cookieWrite || req.cookieRead;
        if (wrap) {
            const out = Model.nameInDir(root.cacheDir, req.outputPath);
            const cwrite = Model.nameInDir(root.cacheDir, req.cookieWrite);
            const cread = Model.nameInDir(root.cacheDir, req.cookieRead);
            if ((req.outputPath && !out) || (req.cookieWrite && !cwrite) || (req.cookieRead && !cread)) {
                Qt.callLater(root.pump);
                return;
            }
            cmd = Model.safeCurlCmd(root.cacheDir, {
                outputName: out,
                cookieWriteName: cwrite,
                cookieReadName: cread,
                url: req.url
            }, cmd);
        } else {
            cmd.push("--", req.url);
        }
        apiProc.command = cmd;
        apiProc.running = true;
    }

    function snapshotFor(service) {
        const existing = root.snapshotMap[service.id];
        return existing ? existing : Model.emptySnapshot(service);
    }

    function cloneSnap(snap) {
        const next = Model.emptySnapshot(snap);
        const keys = ["health", "statusText", "version", "machineId", "paused", "speed", "queue", "queuePage", "queueTotal", "calendar", "activity", "wanted", "sessions", "onDeck", "recent"];
        for (let i = 0; i < keys.length; i++)
            next[keys[i]] = snap[keys[i]];
        return next;
    }

    function setDetailQueue(id, page, items, total) {
        root.detailQueueId = String(id || "");
        root.detailQueuePage = Model.listPage(page);
        root.detailQueue = items || [];
        root.detailQueueTotal = parseInt(total, 10) || 0;
    }

    function clearDetailQueue() {
        root.detailQueueId = "";
        root.detailQueuePage = 1;
        root.detailQueue = [];
        root.detailQueueTotal = 0;
    }

    function turnQueuePage(serviceId, delta) {
        const service = root.serviceById(serviceId);
        if (!service)
            return;
        const current = root.detailQueueId === serviceId ? root.detailQueuePage : 1;
        const page = Model.listPage(current + (parseInt(delta, 10) || 0));
        if (page <= 1) {
            root.clearDetailQueue();
            return;
        }
        const auth = root.cred(service.id);
        if (service.kind === "sonarr" || service.kind === "radarr") {
            root.enqueue({
                kind: "arr-queue",
                serviceId: service.id,
                url: Model.arrQueueUrl(service.url, page, root.pageSize),
                headerText: auth.apiKey ? Model.headerApiKey(auth.apiKey) : "",
                page: page
            });
        } else if (service.kind === "sabnzbd") {
            root.enqueue({
                kind: "sab-queue",
                serviceId: service.id,
                url: Model.sabApiUrl(service.url),
                method: "POST",
                bodyText: Model.sabBody(auth.apiKey, "queue", {
                    start: String(Model.listOffset(page, root.pageSize))
                }, root.pageSize),
                page: page
            });
        } else if (service.kind === "qbittorrent") {
            const ready = root.qbitReady[service.id] === true;
            root.enqueue({
                kind: "qbit-torrents",
                serviceId: service.id,
                url: Model.qbitTorrentsUrl(service.url, page, root.pageSize),
                cookieRead: ready ? root.cookiePath(service.id) : "",
                page: page
            });
        } else {
            return;
        }
        root.pump();
    }

    function commitSnapshot(next, service, seedEvents) {
        const prev = root.snapshotMap[next.id] || Model.emptySnapshot(service);
        const events = Model.eventsFromPoll(prev, next, service);
        const ids = [];
        for (let i = 0; i < events.length; i++)
            ids.push(events[i].id);
        if (root.seeding || seedEvents) {
            root.seenIds = Model.rememberIds(root.seenIds, ids);
        } else {
            for (let e = 0; e < events.length; e++) {
                if (!Model.shouldNotify(events[e], service, root.seenIds))
                    continue;
                root.sendToast(events[e], service);
                root.seenIds = Model.rememberIds(root.seenIds, [events[e].id]);
            }
        }
        const map = {};
        for (const key in root.snapshotMap)
            map[key] = root.snapshotMap[key];
        map[next.id] = next;
        root.snapshotMap = map;
        root.rebuildSnapshotList();
    }

    function rebuildSnapshotList() {
        const list = [];
        for (let i = 0; i < root.services.length; i++) {
            const svc = root.services[i];
            list.push(Model.applyServiceMeta(root.snapshotMap[svc.id] || Model.emptySnapshot(svc), svc));
        }
        root.snapshots = list;
        root.refreshDerived();
    }

    function rebuildSnapshots() {
        const map = {};
        for (let i = 0; i < root.services.length; i++) {
            const svc = root.services[i];
            map[svc.id] = Model.applyServiceMeta(root.snapshotMap[svc.id] || Model.emptySnapshot(svc), svc);
        }
        root.snapshotMap = map;
        root.rebuildSnapshotList();
    }

    function refreshDerived() {
        const next = Model.mergeNow(root.snapshots);
        const deck = Model.reuseFeedList(root.onDeckFeed, next.onDeck);
        const recent = Model.reuseFeedList(root.recentFeed, next.recent);
        const calendar = Model.reuseFeedList(root.calendarFeed, next.calendar);
        if (deck !== root.onDeckFeed)
            root.onDeckFeed = deck;
        if (recent !== root.recentFeed)
            root.recentFeed = recent;
        if (calendar !== root.calendarFeed)
            root.calendarFeed = calendar;
        next.onDeck = root.onDeckFeed;
        next.recent = root.recentFeed;
        next.calendar = root.calendarFeed;
        root.nowFeed = next;
        root.statusText = root.configured ? Model.barStatusText(root.snapshots) : "Add a service";
        const badge = Model.barBadge(root.snapshots);
        root.badgeCount = badge.count;
        root.badgeUrgent = badge.urgent === true;
        if (Model.progressToastStale(root.progressDismissedKey, root.snapshots))
            root.progressDismissedKey = "";
        root.progressJob = Model.progressToast(root.snapshots, root.progressDismissedKey);
        root.syncProgressNote();
        root.publishFeed();
    }

    // Publish the live feed for readers outside this process (upstream: the
    // owner's desktop widgets read it). Every field is projected by
    // Model.feedDocument() from rows the bar and the panel already show;
    // root.credentials never reaches it. Written through the same atomic 0600
    // writer, and only when Model.feedWriteDue() says so.
    function publishFeed() {
        if (!root.dirsReady)
            return;
        const state = {
            snapshots: root.snapshots,
            nowFeed: root.nowFeed,
            statusText: root.statusText,
            badgeCount: root.badgeCount,
            badgeUrgent: root.badgeUrgent,
            unreadCount: root.unreadCount
        };
        const signature = Model.feedSignature(state);
        const now = Date.now();
        if (!Model.feedWriteDue(root.feedWrittenAt, root.feedSignature, signature, now))
            return;
        root.feedWrittenAt = now;
        root.feedSignature = signature;
        root.enqueueWrite(root.stateDir, "feed.json", Model.feedJson(state, now), "");
    }

    // ---- The download card: one notification per job set, kept by the
    // sender that waits on it (progressNote). Its first line of output is the
    // notification's id; changes replace it in place. The sender exits when
    // the card is closed or its Hide is pressed, which dismisses the jobs it
    // showed until they finish, as upstream's card did; stopping the sender
    // (no job left, or the setting off) closes the card.
    property string progressNoteId: ""
    property string progressNoteShown: ""
    property string progressNoteKeys: ""
    property bool progressNoteStopping: false

    function jobKeys(job) {
        const jobs = job && job.jobs && job.jobs.length ? job.jobs : (job ? [job] : []);
        const keys = [];
        for (let i = 0; i < jobs.length; i++)
            keys.push(jobs[i].key);
        return keys.join(",");
    }

    function syncProgressNote() {
        const job = root.showProgressToast ? root.progressJob : null;
        if (!job) {
            if (progressNote.running) {
                root.progressNoteStopping = true;
                progressNote.running = false;
            }
            return;
        }
        const text = Model.progressNoteKey(job);
        const icon = root.iconPath(root.serviceById(job.serviceId));
        root.progressNoteKeys = root.jobKeys(job);
        if (!progressNote.running) {
            root.progressNoteId = "";
            root.progressNoteShown = text;
            progressNote.command = Model.progressNoteCommand(job, root.binDir, icon);
            progressNote.running = true;
            root.noteSent(progressNote.command);
            return;
        }
        if (root.progressNoteId === "" || text === root.progressNoteShown)
            return;
        root.progressNoteShown = text;
        const cmd = Model.progressUpdateCommand(job, root.binDir, icon, root.progressNoteId);
        Quickshell.execDetached(cmd);
        root.noteSent(cmd);
    }

    function dismissProgressToast() {
        root.progressDismissedKey = root.progressNoteKeys || root.jobKeys(root.progressJob);
        root.progressJob = Model.progressToast(root.snapshots, root.progressDismissedKey);
    }

    function noteSent(cmd) {
        if (root.debugIpc)
            root.sentNotes = root.sentNotes.concat([cmd]).slice(-50);
    }

    function sendToast(event, service) {
        const cmd = Model.toastCommand(event, root.binDir, root.iconPath(service));
        // The sender waits for the notification's click, so it runs detached.
        Quickshell.execDetached(cmd);
        root.noteSent(cmd);
        root.unreadCount += 1;
    }

    function clearUnread() {
        root.unreadCount = 0;
    }

    function handleSuccess(text) {
        const req = root.currentReq;
        if (!req)
            return;
        const parsed = Model.splitHttp(text);
        if (req.kind === "scan") {
            root.handleScan(req, parsed.status);
            return;
        }
        const service = root.serviceById(req.serviceId);
        if (!service)
            return;
        if (req.kind === "poster") {
            root.finishArt(req.outputPath, parsed.status >= 200 && parsed.status < 400);
            return;
        }
        let snap = Model.applyServiceMeta(root.cloneSnap(root.snapshotFor(service)), service);
        if (req.kind === "generic") {
            root.commitHealth(service, snap, parsed.status);
            return;
        }
        if (req.kind === "arr-status") {
            const status = Model.parseArrStatus(parsed.body);
            root.commitIdentity(service, snap, parsed.status, {
                version: status.version,
                statusText: status.appName ? status.appName + " " + status.version : status.version
            });
            return;
        }
        if (req.kind === "arr-queue") {
            if (parsed.status >= 200 && parsed.status < 400) {
                const arrItems = Model.parseArrQueue(parsed.body, service.kind, root.pageSize);
                const arrTotal = Model.arrTotalRecords(parsed.body);
                if (req.page > 1) {
                    root.setDetailQueue(service.id, req.page, arrItems, arrTotal);
                    return;
                }
                snap.queue = arrItems;
                snap.queueTotal = arrTotal;
                snap.queuePage = 1;
                root.commitSnapshot(snap, service);
                if (root.panelOpen)
                    root.enqueuePosters(service, snap);
            }
            return;
        }
        if (req.kind === "arr-calendar") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.calendar = Model.parseArrCalendar(parsed.body, service.kind, root.pageSize);
                root.commitSnapshot(snap, service);
                if (root.panelOpen)
                    root.enqueuePosters(service, snap);
            }
            return;
        }
        if (req.kind === "arr-wanted") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.wanted = Model.parseArrWanted(parsed.body, service.kind);
                root.commitSnapshot(snap, service);
            }
            return;
        }
        if (req.kind === "arr-history") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.activity = Model.parseArrHistory(parsed.body, service.kind);
                root.commitSnapshot(snap, service);
            }
            return;
        }
        if (req.kind === "sab-queue") {
            if (parsed.status < 200 || parsed.status >= 400) {
                if (!(req.page > 1))
                    root.commitHealth(service, snap, parsed.status);
                return;
            }
            const sab = Model.parseSabQueue(parsed.body, root.pageSize);
            if (req.page > 1) {
                root.setDetailQueue(service.id, req.page, sab.queue, sab.total);
                return;
            }
            root.setHealthMisses(service.id, 0);
            snap = Model.applyHttpHealth(snap, parsed.status);
            snap.paused = sab.paused;
            snap.speed = sab.speed;
            snap.queue = sab.queue;
            snap.queueTotal = sab.total;
            snap.queuePage = 1;
            snap.statusText = sab.paused ? "Paused" : (sab.speed ? Model.formatSpeed(sab.speed) : "Idle");
            root.commitSnapshot(snap, service);
            return;
        }
        if (req.kind === "sab-history") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.activity = Model.parseSabHistory(parsed.body);
                root.commitSnapshot(snap, service);
            }
            return;
        }
        if (req.kind === "qbit-login") {
            const ready = {};
            for (const rk in root.qbitReady)
                ready[rk] = root.qbitReady[rk];
            ready[service.id] = parsed.status >= 200 && parsed.status < 400 && String(parsed.body).indexOf("Fails") === -1;
            root.qbitReady = ready;
            if (ready[service.id])
                root.enqueueQbit(service, true);
            else
                root.commitHealth(service, snap, parsed.status || 401);
            return;
        }
        if (req.kind === "qbit-torrents") {
            if (parsed.status === 403 || parsed.status === 401) {
                const reset = {};
                for (const qk in root.qbitReady)
                    reset[qk] = root.qbitReady[qk];
                reset[service.id] = false;
                root.qbitReady = reset;
                root.enqueueQbitLogin(service);
                return;
            }
            if (parsed.status < 200 || parsed.status >= 400) {
                if (!(req.page > 1))
                    root.commitHealth(service, snap, parsed.status);
                return;
            }
            const qbitItems = Model.parseQbitTorrents(parsed.body, root.pageSize);
            if (req.page > 1) {
                root.setDetailQueue(service.id, req.page, qbitItems, 0);
                return;
            }
            root.setHealthMisses(service.id, 0);
            snap = Model.applyHttpHealth(snap, parsed.status);
            snap.queue = qbitItems;
            snap.queueTotal = 0;
            snap.queuePage = 1;
            root.commitSnapshot(snap, service);
            return;
        }
        if (req.kind === "qbit-transfer") {
            if (parsed.status >= 200 && parsed.status < 400) {
                const xfer = Model.parseQbitTransfer(parsed.body);
                snap.speed = xfer.speed;
                if (snap.health === "up")
                    snap.statusText = xfer.speed ? Model.formatSpeed(xfer.speed) : "Idle";
                root.commitSnapshot(snap, service);
            }
            return;
        }
        if (req.kind === "jellyfin-identity") {
            const jellyfin = Model.parseJellyfinIdentity(parsed.body);
            root.commitIdentity(service, snap, parsed.status, {
                version: jellyfin.version,
                statusText: jellyfin.name ? jellyfin.name + (jellyfin.version ? " " + jellyfin.version : "") : jellyfin.version
            });
            return;
        }
        if (req.kind === "jellyfin-sessions") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.sessions = Model.parseJellyfinSessions(parsed.body, root.pageSize);
                root.commitSnapshot(snap, service);
                if (root.panelOpen)
                    root.enqueueJellyfinArt(service, snap);
            }
            return;
        }
        if (req.kind === "jellyfin-users") {
            if (parsed.status >= 200 && parsed.status < 400) {
                const jfAuth = root.cred(service.id);
                const profile = Model.pickJellyfinUser(parsed.body, jfAuth.username);
                if (!profile.id) {
                    root.commitSnapshot(Model.applyJellyfinProfileMiss(snap, jfAuth.username), service);
                    return;
                }
                snap.profileName = profile.name;
                root.commitSnapshot(snap, service);
                root.enqueueJellyfinLibrary(service, profile.id);
            }
            return;
        }
        if (req.kind === "jellyfin-ondeck") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.onDeck = Model.parseJellyfinLibrary(parsed.body, root.pageSize);
                root.commitSnapshot(snap, service);
                if (root.panelOpen)
                    root.enqueueJellyfinArt(service, snap);
            }
            return;
        }
        if (req.kind === "jellyfin-recent") {
            if (parsed.status >= 200 && parsed.status < 400) {
                snap.recent = Model.parseJellyfinLibrary(parsed.body, root.pageSize);
                root.commitSnapshot(snap, service);
                if (root.panelOpen)
                    root.enqueueJellyfinArt(service, snap);
            }
            return;
        }
    }

    function handleFailure() {
        const req = root.currentReq;
        if (req && req.kind === "poster") {
            root.finishArt(req.outputPath, false);
            return;
        }
        if (!req || !Model.isHealthKind(req.kind) || req.page > 1)
            return;
        const service = root.serviceById(req.serviceId);
        if (!service)
            return;
        root.commitHealth(service, root.cloneSnap(root.snapshotFor(service)), 0);
    }

    function handleScan(req, status) {
        if (!(status >= 200 && status < 400))
            return;
        const found = Model.scanHitsForPort(req.port);
        const hits = [];
        if (!found.length) {
            hits.push({
                kind: "generic",
                name: req.name,
                url: req.url,
                port: req.port
            });
        } else {
            for (let h = 0; h < found.length; h++)
                hits.push({
                    kind: found[h].kind,
                    name: found[h].name,
                    url: req.url,
                    port: req.port
                });
        }
        const existing = root.scanResults.slice();
        for (let i = 0; i < hits.length; i++) {
            let dupe = false;
            for (let j = 0; j < existing.length; j++) {
                if (existing[j].kind === hits[i].kind && existing[j].url === hits[i].url)
                    dupe = true;
            }
            if (!dupe)
                existing.push(hits[i]);
        }
        root.scanResults = existing;
    }

    function enqueuePosters(service, snap) {
        const posters = {};
        const fanarts = {};
        const calendar = snap.calendar || [];
        for (let c = 0; c < calendar.length; c++) {
            const cid = calendar[c].posterId;
            if (cid) {
                posters[cid] = true;
                fanarts[cid] = true;
            }
        }
        const lists = [snap.queue || [], snap.wanted || []];
        for (let l = 0; l < lists.length; l++) {
            for (let i = 0; i < lists[l].length; i++) {
                const pid = lists[l][i].posterId;
                if (pid)
                    posters[pid] = true;
            }
        }
        const auth = root.cred(service.id);
        const header = auth.apiKey ? Model.headerApiKey(auth.apiKey) : "";
        for (const fid in fanarts) {
            root.enqueueArt({
                kind: "poster",
                serviceId: service.id,
                url: Model.arrFanartUrl(service.url, fid),
                headerText: header,
                outputPath: Model.fanartCachePath(root.cacheDir, service.id, fid),
                image: true
            });
        }
        for (const id in posters) {
            root.enqueueArt({
                kind: "poster",
                serviceId: service.id,
                url: Model.arrPosterUrl(service.url, service.kind, id),
                headerText: header,
                outputPath: Model.posterCachePath(root.cacheDir, service.id, id),
                image: true
            });
        }
    }

    function enqueueGeneric(service) {
        root.enqueue({
            kind: "generic",
            serviceId: service.id,
            url: service.url
        });
    }

    function enqueueArr(service) {
        const auth = root.cred(service.id);
        const header = auth.apiKey ? Model.headerApiKey(auth.apiKey) : "";
        const range = Model.arrCalendarRange(new Date(), 7);
        root.enqueue({ kind: "arr-status", serviceId: service.id, url: Model.arrStatusUrl(service.url), headerText: header });
        root.enqueue({ kind: "arr-queue", serviceId: service.id, url: Model.arrQueueUrl(service.url, 1, root.pageSize), headerText: header });
        root.enqueue({ kind: "arr-calendar", serviceId: service.id, url: Model.arrCalendarUrl(service.url, range.start, range.end), headerText: header });
        root.enqueue({ kind: "arr-history", serviceId: service.id, url: Model.arrHistoryUrl(service.url, service.kind, root.pageSize), headerText: header });
        if (root.panelOpen)
            root.enqueue({ kind: "arr-wanted", serviceId: service.id, url: Model.arrWantedUrl(service.url, service.kind), headerText: header });
    }

    function enqueueSab(service, queueOnly) {
        const auth = root.cred(service.id);
        root.enqueue({
            kind: "sab-queue",
            serviceId: service.id,
            url: Model.sabApiUrl(service.url),
            method: "POST",
            bodyText: Model.sabBody(auth.apiKey, "queue", null, root.pageSize)
        });
        if (queueOnly)
            return;
        root.enqueue({
            kind: "sab-history",
            serviceId: service.id,
            url: Model.sabApiUrl(service.url),
            method: "POST",
            bodyText: Model.sabBody(auth.apiKey, "history", null, root.pageSize)
        });
    }

    function enqueueQbitLogin(service) {
        const auth = root.cred(service.id);
        root.enqueue({
            kind: "qbit-login",
            serviceId: service.id,
            url: Model.qbitLoginUrl(service.url),
            method: "POST",
            bodyText: Model.qbitLoginBody(auth.username || "admin", auth.password),
            cookieWrite: root.cookiePath(service.id)
        });
    }

    function enqueueQbit(service, skipLogin) {
        const ready = root.qbitReady[service.id] === true;
        const auth = root.cred(service.id);
        if (!skipLogin && !ready && (auth.username || auth.password)) {
            root.enqueueQbitLogin(service);
            return;
        }
        const jar = root.cookiePath(service.id);
        root.enqueue({
            kind: "qbit-torrents",
            serviceId: service.id,
            url: Model.qbitTorrentsUrl(service.url, 1, root.pageSize),
            cookieRead: ready || skipLogin ? jar : ""
        });
        root.enqueue({
            kind: "qbit-transfer",
            serviceId: service.id,
            url: Model.qbitTransferUrl(service.url),
            cookieRead: ready || skipLogin ? jar : ""
        });
    }

    function enqueueJellyfin(service) {
        const auth = root.cred(service.id);
        const header = Model.headerJellyfin(auth.apiKey);
        root.enqueue({ kind: "jellyfin-identity", serviceId: service.id, url: Model.jellyfinSystemInfoUrl(service.url), headerText: header });
        root.enqueue({ kind: "jellyfin-sessions", serviceId: service.id, url: Model.jellyfinSessionsUrl(service.url), headerText: header });
        root.enqueue({ kind: "jellyfin-users", serviceId: service.id, url: Model.jellyfinUsersUrl(service.url), headerText: header });
    }

    function enqueueJellyfinLibrary(service, userId) {
        const auth = root.cred(service.id);
        const header = Model.headerJellyfin(auth.apiKey);
        root.enqueue({ kind: "jellyfin-ondeck", serviceId: service.id, url: Model.jellyfinResumeUrl(service.url, userId, root.pageSize), headerText: header });
        root.enqueue({ kind: "jellyfin-recent", serviceId: service.id, url: Model.jellyfinLatestUrl(service.url, userId, root.pageSize), headerText: header });
    }

    function enqueueJellyfinArt(service, snap) {
        const auth = root.cred(service.id);
        const header = Model.headerJellyfin(auth.apiKey);
        const lists = [snap.sessions || [], snap.onDeck || [], snap.recent || []];
        const seen = {};
        for (let l = 0; l < lists.length; l++) {
            for (let i = 0; i < lists[l].length; i++) {
                const item = lists[l][i] || {};
                const id = String(item.id || "");
                if (!id || seen[id])
                    continue;
                seen[id] = true;
                const url = Model.jellyfinArtUrl(service.url, item.artItemId || id, item.artType);
                if (!url)
                    continue;
                root.enqueueArt({
                    kind: "poster",
                    serviceId: service.id,
                    url: url,
                    headerText: header,
                    outputPath: Model.jellyfinCachePath(root.cacheDir, service.id, id),
                    image: true
                });
            }
        }
    }

    function enqueuePoll(scope) {
        if (root.reqQueue.length)
            return;
        const downloaders = scope === "downloaders";
        function enqueueOne(svc) {
            if (!Model.isHttpUrl(svc.url))
                return;
            if (svc.kind === "sonarr" || svc.kind === "radarr")
                root.enqueueArr(svc);
            else if (svc.kind === "sabnzbd")
                root.enqueueSab(svc, downloaders);
            else if (svc.kind === "qbittorrent")
                root.enqueueQbit(svc);
            else if (downloaders)
                return;
            else if (svc.kind === "jellyfin")
                root.enqueueJellyfin(svc);
            else
                root.enqueueGeneric(svc);
        }
        for (let i = 0; i < root.services.length; i++) {
            const downloader = root.services[i];
            if (downloader.kind === "sabnzbd" || downloader.kind === "qbittorrent")
                enqueueOne(downloader);
        }
        if (downloaders)
            return;
        for (let j = 0; j < root.services.length; j++) {
            const other = root.services[j];
            if (other.kind === "sabnzbd" || other.kind === "qbittorrent")
                continue;
            enqueueOne(other);
        }
    }

    function forcePoll() {
        root.rebuildSnapshots();
        if (!root.reqQueue.length && !apiProc.running)
            root.enqueuePoll();
        root.pump();
    }

    function hasDownloaderRequest() {
        function isDl(req) {
            if (!req)
                return false;
            const k = String(req.kind || "");
            return k === "sab-queue" || k.indexOf("qbit-") === 0;
        }
        if (isDl(root.currentReq))
            return true;
        for (let i = 0; i < root.reqQueue.length; i++) {
            if (isDl(root.reqQueue[i]))
                return true;
        }
        return false;
    }

    function forceDownloaderPoll() {
        if (secretProc.running || root.writeQueue.length || root.hasDownloaderRequest())
            return;
        const rest = root.reqQueue;
        root.reqQueue = [];
        root.enqueuePoll("downloaders");
        root.reqQueue = root.reqQueue.concat(rest);
        root.pump();
    }

    function startScan() {
        root.scanning = true;
        root.scanResults = [];
        const targets = Model.scanTargets();
        for (let i = 0; i < targets.length; i++) {
            const t = targets[i];
            root.enqueue({
                kind: "scan",
                url: Model.scanUrl("127.0.0.1", t.port),
                port: t.port,
                name: t.name,
                scan: true
            });
        }
        root.pump();
    }

    function finishScanIfIdle() {
        if (!root.scanning)
            return;
        if (root.reqQueue.length || apiProc.running || secretProc.running || root.writeQueue.length)
            return;
        root.scanning = false;
    }

    function commandReq(service, spec) {
        const req = spec || {};
        req.kind = "command";
        req.serviceId = service.id;
        root.enqueue(req);
    }

    function runControl(serviceId, action, itemId) {
        const service = root.serviceById(serviceId);
        if (!service)
            return;
        const auth = root.cred(service.id);
        if (service.kind === "sabnzbd") {
            let extra = {};
            let mode = action;
            if (action === "pause-item") {
                mode = "queue";
                extra = { name: "pause", value: String(itemId || "") };
            } else if (action === "resume-item") {
                mode = "queue";
                extra = { name: "resume", value: String(itemId || "") };
            } else {
                return;
            }
            root.commandReq(service, {
                url: Model.sabApiUrl(service.url),
                method: "POST",
                bodyText: Model.sabBody(auth.apiKey, mode, extra)
            });
        }
        if (service.kind === "qbittorrent") {
            if (action !== "pause-item" && action !== "resume-item")
                return;
            const pause = action === "pause-item";
            const hashes = String(itemId || "");
            // qBittorrent renamed pause/resume to stop/start in 5.0; both are
            // sent, and the one a version does not know answers 404.
            root.commandReq(service, {
                url: pause ? Model.qbitPauseUrl(service.url) : Model.qbitResumeUrl(service.url),
                method: "POST",
                bodyText: Model.qbitHashesBody(hashes),
                cookieRead: root.cookiePath(service.id)
            });
            root.commandReq(service, {
                url: pause ? Model.qbitStopUrl(service.url) : Model.qbitStartUrl(service.url),
                method: "POST",
                bodyText: Model.qbitHashesBody(hashes),
                cookieRead: root.cookiePath(service.id)
            });
        }
        Qt.callLater(root.forcePoll);
    }

    function posterPath(serviceId, posterId) {
        return Model.posterCachePath(root.cacheDir, serviceId, posterId);
    }

    function fanartPath(serviceId, posterId) {
        return Model.fanartCachePath(root.cacheDir, serviceId, posterId);
    }

    function mediaPath(serviceId, itemId) {
        return Model.jellyfinCachePath(root.cacheDir, serviceId, itemId);
    }

    function copyMap(obj) {
        const next = {};
        if (!obj)
            return next;
        for (const k in obj)
            next[k] = obj[k];
        return next;
    }

    function enqueueArt(req) {
        const path = req && req.outputPath;
        if (!path || root.artReady[path] || root.artPending[path])
            return;
        const pending = root.copyMap(root.artPending);
        pending[path] = true;
        root.artPending = pending;
        root.enqueue(req);
    }

    function finishArt(path, ok) {
        if (!path)
            return;
        const pending = root.copyMap(root.artPending);
        delete pending[path];
        root.artPending = pending;
        if (!ok || root.artReady[path])
            return;
        const ready = root.copyMap(root.artReady);
        ready[path] = true;
        root.artReady = ready;
        const rev = root.copyMap(root.artRev);
        rev[path] = (rev[path] || 0) + 1;
        root.artRev = rev;
    }

    Process {
        id: settingsWriter

        stdinEnabled: true
        stdout: StdioCollector {}
        stderr: StdioCollector {
            id: settingsErr
        }
        onStarted: {
            write(JSON.stringify({ settings: root.settingsWriting }) + "\n");
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            root.finishSettingsWrite(code === 0);
        }
    }

    FileView {
        id: credsFile

        // Read synchronously when the path appears, so the first poll (started
        // in the same handler that sets dirsReady) already has the keys.
        path: root.dirsReady ? root.credsPath : ""
        blockLoading: true
        watchChanges: true
        printErrors: false
        onLoaded: root.credentials = Model.parseCredentials(text())
        onLoadFailed: root.credentials = ({})
        onFileChanged: reload()
    }

    FileView {
        id: seenFile

        path: root.dirsReady ? root.seenPath : ""
        blockLoading: true
        watchChanges: false
        printErrors: false
        onLoaded: root.seenIds = Model.parseSeenFile(text())
        onLoadFailed: root.seenIds = []
    }

    // Which state directory this HOME uses (Model.chooseStateDir), then the
    // 0700 state and cache directories, then what the cache already holds.
    Process {
        id: stateProbe

        command: Model.stateDirProbeCmd(root.haseenStateDir, root.legacyStateDir)
        stdout: StdioCollector {
            id: stateProbeOut
            waitForEnd: true
        }
        onExited: code => {
            root.stateDir = code === 0 && stateProbeOut.text !== "" ? stateProbeOut.text : root.haseenStateDir;
            ensureDirProc.command = Model.ensurePrivateDirsCmd(root.stateDir, root.cacheDir);
            ensureDirProc.running = true;
        }
    }

    Process {
        id: ensureDirProc

        onExited: code => {
            if (code !== 0) {
                console.warn("haseen.omarr: cannot make the private directories", root.stateDir, root.cacheDir);
                return;
            }
            cacheIndexProc.command = ["ls", "-1", "--", root.cacheDir];
            cacheIndexProc.running = true;
        }
    }

    Process {
        id: cacheIndexProc

        stdout: StdioCollector {
            id: cacheIndexOut
            waitForEnd: true
        }
        onExited: {
            const ready = {};
            const lines = String(cacheIndexOut.text || "").split("\n");
            for (let i = 0; i < lines.length; i++) {
                const name = String(lines[i] || "").trim();
                if (!name || name.indexOf(".jpg") === -1)
                    continue;
                ready[root.cacheDir + "/" + name] = true;
            }
            root.artReady = ready;
            root.dirsReady = true;
            root.rebuildSnapshots();
            root.forcePoll();
        }
    }

    Process {
        id: secretProc

        stdinEnabled: true
        onStarted: {
            write(root.pendingWriteText);
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            const thenKind = root.pendingWriteThen;
            root.pendingWriteText = "";
            root.pendingWriteThen = "";
            if (code !== 0) {
                if (thenKind === "body" || thenKind === "curl") {
                    root.handleFailure();
                    root.currentReq = null;
                }
                Qt.callLater(root.pumpWrites);
                Qt.callLater(root.pump);
                return;
            }
            if (thenKind === "body") {
                const req = root.currentReq;
                if (req && req.bodyText)
                    root.enqueueWrite(root.cacheDir, "body.txt", req.bodyText, "curl");
            } else if (thenKind === "curl") {
                root.runCurl(root.currentReq);
            }
            Qt.callLater(root.pumpWrites);
            Qt.callLater(root.pump);
        }
    }

    // The download card's sender (see syncProgressNote).
    Process {
        id: progressNote

        stdout: SplitParser {
            onRead: line => {
                const text = String(line).trim();
                if (root.progressNoteId === "" && /^[0-9]+$/.test(text))
                    root.progressNoteId = text;
            }
        }
        onExited: {
            const stopped = root.progressNoteStopping;
            root.progressNoteStopping = false;
            root.progressNoteId = "";
            root.progressNoteShown = "";
            // Closed by the user (or Hide): those jobs stay hidden until they end.
            if (!stopped)
                root.dismissProgressToast();
        }
    }

    Process {
        id: apiProc

        stdout: StdioCollector {
            id: apiOut
            waitForEnd: true
        }
        onExited: exitCode => {
            if (root.currentReq && root.currentReq.kind === "scan") {
                if (exitCode === 0)
                    root.handleSuccess(apiOut.text);
            } else if (exitCode !== 0) {
                root.handleFailure();
            } else {
                root.handleSuccess(apiOut.text);
            }
            root.currentReq = null;
            if (!root.reqQueue.length) {
                root.seeding = false;
                root.persistSeen();
                root.finishScanIfIdle();
            }
            Qt.callLater(root.pump);
        }
    }

    // The poll at the configured cadence (pollSeconds, at least 5 s): a
    // fixed 5 s tick counts towards it, because the timer rule wants a
    // literal interval (a cadence that is not a multiple of 5 rounds up).
    // haseen:sample
    Timer {
        interval: 5000
        running: root.dirsReady
        repeat: true
        onTriggered: {
            root.pollElapsed += 5;
            if (root.pollElapsed < Math.max(5, root.pollSeconds))
                return;
            root.pollElapsed = 0;
            root.forcePoll();
        }
    }

    // A faster full poll while the panel is open.
    // haseen:sample
    Timer {
        interval: 8000
        running: root.panelOpen && root.dirsReady
        repeat: true
        onTriggered: {
            if (!root.reqQueue.length && !apiProc.running)
                root.forcePoll();
        }
    }

    // SABnzbd and qBittorrent every 2 s (Model.DOWNLOAD_POLL_MS), so the
    // download card follows a job; only while one runs or the panel is open.
    // haseen:sample
    Timer {
        interval: 2000
        running: root.dirsReady && (root.downloadsActive || root.panelOpen)
        repeat: true
        onTriggered: root.forceDownloaderPoll()
    }

    onServicesChanged: root.rebuildSnapshots()
    onShowProgressToastChanged: root.syncProgressNote()
    onPanelOpenChanged: {
        if (root.panelOpen) {
            root.clearUnread();
            root.forcePoll();
        }
    }

    Component.onCompleted: stateProbe.running = true
    Component.onDestruction: {
        root.progressNoteStopping = true;
        progressNote.running = false;
    }

    // Test hook (settings.debugIpc): the service's state as JSON.
    IpcHandler {
        target: "haseen.omarr"
        enabled: root.debugIpc

        function state(): string {
            return JSON.stringify({
                stateDir: root.stateDir,
                cacheDir: root.cacheDir,
                dirsReady: root.dirsReady,
                configured: root.configured,
                services: root.services.length,
                badgeCount: root.badgeCount,
                badgeUrgent: root.badgeUrgent,
                statusText: root.statusText,
                unreadCount: root.unreadCount,
                notes: root.sentNotes
            });
        }

        function poll(): void {
            root.forcePoll();
        }
    }
}
