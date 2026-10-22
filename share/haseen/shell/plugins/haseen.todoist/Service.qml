import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

// haseen.todoist service (role `todoist`): the task list, the bar count, the
// actions (complete, quick add, edit, delete) and the private settings, once
// per shell while the plugin is enabled and listed in `services`. The bar
// widget (one per screen) and the lazily loaded panel read it through
// Plugins.roles.todoist. Every request and every settings write goes through
// haseen-todoist.sh beside this file, which reads the API token from the
// settings file itself: the token is never a property here and never in argv.
//
// Adapted from Panel.qml and BarWidget.qml in omarchy-todoist (MIT, Copyright
// (c) 2026 aryan-techie), as the owner's fork t1nk33r.todoist 1.14.0; see
// LICENSE and UPSTREAM.md beside this file. haseen changes: the state the
// upstream panel kept for the bar lives in this service, so the count updates
// with no panel open and once for every screen; requests go through
// haseen-todoist.sh instead of curl with a header file the shell kept in sync;
// the keyboard-shortcut recorder is gone (it edited the user's Hyprland
// bindings); the rotating header phrases are gone (a 2.8 s cosmetic timer).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string helper: Paths.builtinPlugins + "/haseen.todoist/haseen-todoist.sh"
    readonly property bool debugIpc: settings.debugIpc === true

    // ---- Private settings (Model.readSettings). "" until `dir` answered.
    property string stateDir: ""
    property bool settingsLoaded: false
    property bool hasToken: false
    property string filterQuery: "today | overdue"
    // "today" | "inbox" | "all" | "custom" (the filter in Settings).
    property string quickView: "today"
    property string barCountMode: "hide"
    property int panelWidth: 340
    property int panelHeight: 480

    property bool panelOpen: false

    property var tasks: []
    readonly property int taskCount: tasks.length
    // The last list stopped at the page cap: its count is a floor.
    property bool listTruncated: false
    property bool loading: false
    // The last failure the panel shows ({text, args}, Model.failure), or
    // null; errorText is its line in the interface language.
    property var failure: null
    readonly property string errorText: Model.failureText(failure, I18n)
    property bool refreshPending: false
    property real lastSyncedAt: 0
    // A 401/403 from any request: the bar mark dims and its count hides.
    // Cleared by the next answer that is not an error.
    property bool tokenInvalid: false

    // Paginated fetches in flight (Model.mergeTaskPage); null when none runs.
    property var listFetch: null
    property var barCountFetch: null

    property int barCountValue: 0
    property bool barCountTruncated: false

    // Tasks being closed: struck through for a moment, then removed.
    property var completingTaskIds: []
    property var pendingRemovalIds: []
    property var actionQueue: []
    property bool quickAddSubmitting: false
    // Bumped when a quick add went through, so the panel can clear its field.
    property int quickAddDone: 0

    readonly property int overdueCount: {
        let n = 0;
        for (let i = 0; i < tasks.length; i++)
            if (Model.taskIsOverdue(tasks[i]))
                n++;
        return n;
    }
    readonly property string tooltipText: {
        if (!hasToken)
            return I18n.tr("Todoist: not connected");
        if (tokenInvalid)
            return I18n.tr("Todoist: the API token was rejected; paste a current one in the panel's settings");
        if (barCountMode === "hide")
            return taskCount > 0 ? I18n.tn("Todoist: %1 task", "Todoist: %1 tasks", taskCount) : I18n.tr("Todoist: all clear");
        const count = String(barCountValue) + (barCountTruncated ? "+" : "");
        if (barCountMode === "inbox")
            return I18n.tr("Todoist: %1 in Inbox", count);
        if (barCountMode === "all")
            return I18n.tr("Todoist: %1 total", count);
        return I18n.tr("Todoist: %1 today", count);
    }

    function setPanelOpen(open: bool): void {
        root.panelOpen = open;
        if (open && root.hasToken) {
            root.refresh();
            root.refreshBarCount();
        }
    }

    function api(proc: var, method: string, path: string, body: var): void {
        const cmd = [root.helper, "api", method, path];
        if (body !== undefined && body !== null)
            cmd.push(JSON.stringify(body));
        proc.command = cmd;
        proc.running = true;
    }

    // What a finished request means: null when it succeeded, else the failure
    // the panel shows (Model.failure). The status curl was asked for is the
    // signal (an error body arrives with exit 0); status 0 means no HTTP
    // answer, where the exit code and stderr speak. Keeps tokenInvalid
    // current as a side effect.
    function responseFailure(response: var, exitCode: int, stderrText: string): var {
        if (exitCode === 3 && response.status === 0) {
            root.hasToken = false;
            return Model.failure(I18n.mark("Add your Todoist API token in Settings."));
        }
        const failed = response.status === 0 ? Model.exitFailure(exitCode, stderrText) : Model.statusFailure(response.status, response.body);
        if (Model.tokenRejected(response.status))
            root.tokenInvalid = true;
        else if (failed === null)
            root.tokenInvalid = false;
        return failed;
    }

    // ---- Settings. One write at a time, in order, each a JSON object of the
    // keys that changed on the helper's stdin.
    property var writes: []
    property var writing: null

    function saveSettings(values: var): void {
        root.writes = root.writes.concat([{ verb: "set", values: values }]);
        root.startWrite();
    }

    function startWrite(): void {
        if (root.writing !== null || root.writes.length === 0 || root.stateDir === "")
            return;
        root.writing = root.writes[0];
        root.writes = root.writes.slice(1);
        writer.command = [root.helper, root.writing.verb];
        writer.running = true;
    }

    function saveToken(token: string): void {
        const value = Model.safeTrim(token);
        if (value === "")
            return;
        root.hasToken = true;
        root.tokenInvalid = false;
        root.failure = null;
        root.saveSettings({ apiToken: value });
        // The first request reads the file the write above creates.
        root.refreshAfterWrite = true;
    }

    function clearToken(): void {
        // A fetch in flight would refill the list for the account being
        // removed: stop it and reset everything that describes that account.
        listProc.running = false;
        barCountProc.running = false;
        root.listFetch = null;
        root.barCountFetch = null;
        root.loading = false;
        root.refreshPending = false;
        root.listTruncated = false;
        root.barCountValue = 0;
        root.barCountTruncated = false;
        root.lastSyncedAt = 0;
        root.hasToken = false;
        root.tasks = [];
        root.failure = null;
        root.tokenInvalid = false;
        root.writes = root.writes.concat([{ verb: "clear-token" }]);
        root.startWrite();
    }

    property bool refreshAfterWrite: false

    function applyFilter(value: string): void {
        root.filterQuery = Model.sanitizeFilter(value);
        root.quickView = "custom";
        root.saveSettings({ filter: root.filterQuery, quickView: "custom" });
        root.refresh();
    }

    function selectQuickView(view: string): void {
        if (view === root.quickView)
            return;
        root.quickView = view;
        root.saveSettings({ quickView: view });
        root.refresh();
    }

    function setBarCountMode(mode: string): void {
        if (mode === root.barCountMode)
            return;
        root.barCountMode = mode;
        root.saveSettings({ barCountMode: mode });
        root.refreshBarCount();
    }

    function setPanelSize(width: int, height: int): void {
        root.panelWidth = Model.clampPanelWidth(width);
        root.panelHeight = Model.clampPanelHeight(height);
        root.saveSettings({ panelWidth: root.panelWidth, panelHeight: root.panelHeight });
    }

    function loadSettings(text: string): void {
        // A reload between two queued writes holds the older of them; the
        // reload after the last write is the one to show.
        if (root.settingsLoaded && (root.writing !== null || root.writes.length > 0))
            return;
        const s = Model.readSettings(text);
        root.hasToken = s.hasToken;
        root.filterQuery = s.filterQuery;
        root.quickView = s.quickView;
        root.barCountMode = s.barCountMode;
        root.panelWidth = s.panelWidth;
        root.panelHeight = s.panelHeight;
        const first = !root.settingsLoaded;
        root.settingsLoaded = true;
        if (first && root.hasToken) {
            root.refresh();
            root.refreshBarCount();
        }
    }

    // ---- The task list. Every action and both poll timers come through
    // refresh(), so one fetch runs at a time: a refresh asked for while one is
    // in flight runs once that one ends (refreshPending). A fetch is a
    // sequence of pages (limit 200, next_cursor), at most Model.TASK_PAGE_CAP.
    function refresh(): void {
        if (!root.hasToken || root.stateDir === "")
            return;
        if (listProc.running) {
            root.refreshPending = true;
            return;
        }
        root.refreshPending = false;
        root.loading = true;
        root.failure = null;
        root.listFetch = Model.emptyFetch();
        root.fetchListPage("");
        openRefreshTimer.restart();
        backgroundRefreshTimer.restart();
    }

    function fetchListPage(cursor: string): void {
        root.api(listProc, "GET", Model.taskListPath(root.quickView, root.filterQuery, cursor), null);
    }

    // After each page, on a deferred tick (a Process cannot restart from its
    // own exit handler); a refresh asked for meanwhile wins over the next page.
    function continueList(): void {
        if (root.refreshPending) {
            root.refresh();
            return;
        }
        if (!root.loading || root.listFetch === null || root.listFetch.cursor === null)
            return;
        root.fetchListPage(root.listFetch.cursor);
    }

    function listExited(exitCode: int): void {
        // An answer that lands after the token was removed is for an account
        // that is gone: settle quietly.
        if (!root.hasToken) {
            root.loading = false;
            root.listFetch = null;
            return;
        }
        const response = Model.parseCurlResponse(String(listOut.text || ""));
        const failed = root.responseFailure(response, exitCode, String(listErr.text || ""));
        if (failed !== null) {
            root.failList(failed);
            return;
        }
        let page = null;
        try {
            page = Model.parseTaskPage(response.body);
        } catch (e) {
            root.failList(Model.failure(I18n.mark("Couldn't read the response from Todoist.")));
            return;
        }
        root.listFetch = Model.mergeTaskPage(root.listFetch, page);
        if (root.listFetch.cursor === null)
            root.finishList();
    }

    function failList(failed: var): void {
        root.loading = false;
        root.listFetch = null;
        root.failure = failed;
    }

    function finishList(): void {
        root.loading = false;
        root.tasks = Model.sortedTasks(root.listFetch.tasks);
        root.listTruncated = root.listFetch.truncated === true;
        root.listFetch = null;
        root.failure = null;
        root.lastSyncedAt = Date.now();
        root.refreshBarCount();
    }

    // ---- The bar count, independent of the panel's tab. When the mode is the
    // tab the list shows, the list's own count is used instead of a fetch.
    function refreshBarCount(): void {
        if (root.barCountMode === "hide" || !root.hasToken || root.stateDir === "")
            return;
        if (root.barCountMode === root.quickView && root.lastSyncedAt > 0) {
            root.barCountValue = root.taskCount;
            root.barCountTruncated = root.listTruncated;
            return;
        }
        if (barCountProc.running)
            return;
        root.barCountFetch = Model.emptyFetch();
        root.fetchBarCountPage("");
    }

    function fetchBarCountPage(cursor: string): void {
        root.api(barCountProc, "GET", Model.taskListPath(root.barCountMode, root.filterQuery, cursor), null);
    }

    function continueBarCount(): void {
        if (root.barCountFetch === null || root.barCountFetch.cursor === null)
            return;
        root.fetchBarCountPage(root.barCountFetch.cursor);
    }

    function barCountExited(exitCode: int): void {
        if (!root.hasToken) {
            root.barCountFetch = null;
            return;
        }
        const response = Model.parseCurlResponse(String(barCountOut.text || ""));
        // A failed count keeps the last value, but still feeds the token check:
        // with the panel closed this is the only request that runs.
        if (root.responseFailure(response, exitCode, String(barCountErr.text || "")) !== null) {
            root.barCountFetch = null;
            return;
        }
        let page = null;
        try {
            page = Model.parseTaskPage(response.body);
        } catch (e) {
            root.barCountFetch = null;
            return;
        }
        const next = Model.mergeTaskCountPage(root.barCountFetch, page);
        if (next.cursor !== null) {
            root.barCountFetch = next;
            return;
        }
        root.barCountFetch = null;
        root.barCountValue = next.count;
        root.barCountTruncated = next.truncated === true;
    }

    // ---- Quick add, through Todoist's own parser (/tasks/quick): p1-p4,
    // #Project, @label and natural dates work as in Todoist itself.
    function submitQuickAdd(content: string): void {
        const text = Model.quickAddText(content);
        if (text === "" || root.quickAddSubmitting || !root.hasToken)
            return;
        root.quickAddSubmitting = true;
        root.failure = null;
        root.api(createProc, "POST", "tasks/quick", { text: text });
    }

    // ---- Complete: struck through at once, removed 700 ms later, closed on
    // the server in order through one queue.
    function requestComplete(taskId: string): void {
        if (taskId === "" || root.completingTaskIds.indexOf(taskId) !== -1)
            return;
        root.completingTaskIds = root.completingTaskIds.concat([taskId]);
        root.pendingRemovalIds = root.pendingRemovalIds.concat([taskId]);
        root.actionQueue = root.actionQueue.concat([taskId]);
        root.processActionQueue();
        completionRemovalTimer.restart();
    }

    function undoCompleting(taskId: string): void {
        root.completingTaskIds = root.completingTaskIds.filter(id => id !== taskId);
        root.pendingRemovalIds = root.pendingRemovalIds.filter(id => id !== taskId);
    }

    function flushCompletedRemovals(): void {
        const ids = root.pendingRemovalIds;
        root.pendingRemovalIds = [];
        root.tasks = root.tasks.filter(t => !t || ids.indexOf(t.id) === -1);
        root.completingTaskIds = root.completingTaskIds.filter(id => ids.indexOf(id) === -1);
        root.refresh();
    }

    function processActionQueue(): void {
        if (actionProc.running || root.actionQueue.length === 0)
            return;
        const taskId = root.actionQueue[0];
        root.actionQueue = root.actionQueue.slice(1);
        actionProc.pendingTaskId = taskId;
        root.api(actionProc, "POST", "tasks/" + encodeURIComponent(taskId) + "/close", null);
    }

    function editTask(taskId: string, content: string): void {
        const text = Model.safeTrim(content);
        const index = root.tasks.findIndex(t => t && t.id === taskId);
        if (index < 0 || text === "" || text === root.tasks[index].content)
            return;
        const next = root.tasks.slice();
        next[index] = Object.assign({}, next[index], { content: text });
        root.tasks = next;
        root.api(editProc, "POST", "tasks/" + encodeURIComponent(taskId), { content: text });
    }

    function deleteTask(taskId: string): void {
        if (taskId === "")
            return;
        root.tasks = root.tasks.filter(t => !t || t.id !== taskId);
        root.api(deleteProc, "DELETE", "tasks/" + encodeURIComponent(taskId), null);
    }

    function openTask(task: var): void {
        if (task && task.id)
            Apps.launch(["xdg-open", "https://app.todoist.com/app/task/" + encodeURIComponent(task.id)]);
    }

    function openTodoist(): void {
        Apps.launch(["xdg-open", "https://app.todoist.com/app/today"]);
    }

    Component.onCompleted: dirProc.running = true

    Process {
        id: dirProc

        command: [root.helper, "dir"]
        stdout: StdioCollector {
            id: dirOut
            waitForEnd: true
        }
        onExited: code => {
            if (code !== 0) {
                root.failure = Model.failure(I18n.mark("The plugin's state directory could not be found."));
                return;
            }
            root.stateDir = dirOut.text.trim();
            root.startWrite();
        }
    }

    // The settings file, watched: a token saved from another screen's panel,
    // or by hand, is picked up. Missing means a fresh start (Settings opens).
    FileView {
        id: settingsFile

        path: root.stateDir === "" ? "" : root.stateDir + "/settings.json"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadSettings(text())
        onLoadFailed: root.loadSettings("")
        onFileChanged: reload()
    }

    Process {
        id: writer

        stdinEnabled: true
        stderr: StdioCollector {
            id: writerErr
        }
        onStarted: {
            if (root.writing && root.writing.values)
                write(JSON.stringify(root.writing.values) + "\n");
            stdinEnabled = false;
        }
        onExited: code => {
            stdinEnabled = true;
            if (code !== 0)
                root.failure = Model.failure(I18n.mark("Settings were not saved: %1"), [String(writerErr.text || "").trim()]);
            root.writing = null;
            settingsFile.reload();
            if (root.refreshAfterWrite && root.writes.length === 0) {
                root.refreshAfterWrite = false;
                root.refresh();
                root.refreshBarCount();
            }
            Qt.callLater(root.startWrite);
        }
    }

    Process {
        id: listProc

        stdout: StdioCollector {
            id: listOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: listErr
            waitForEnd: true
        }
        onExited: code => {
            root.listExited(code);
            Qt.callLater(root.continueList);
        }
    }

    Process {
        id: barCountProc

        stdout: StdioCollector {
            id: barCountOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: barCountErr
            waitForEnd: true
        }
        onExited: code => {
            root.barCountExited(code);
            Qt.callLater(root.continueBarCount);
        }
    }

    Process {
        id: createProc

        stdout: StdioCollector {
            id: createOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: createErr
            waitForEnd: true
        }
        onExited: code => {
            root.quickAddSubmitting = false;
            const failed = root.responseFailure(Model.parseCurlResponse(String(createOut.text || "")), code, String(createErr.text || ""));
            if (failed !== null) {
                root.failure = failed;
                return;
            }
            root.quickAddDone++;
            root.refresh();
        }
    }

    Process {
        id: actionProc

        // The task this run closes, so a failure undoes exactly that one.
        property string pendingTaskId: ""

        stdout: StdioCollector {
            id: actionOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionErr
            waitForEnd: true
        }
        onExited: code => {
            const failed = root.responseFailure(Model.parseCurlResponse(String(actionOut.text || "")), code, String(actionErr.text || ""));
            if (failed !== null) {
                root.failure = failed;
                root.undoCompleting(actionProc.pendingTaskId);
                root.refresh();
            }
            Qt.callLater(root.processActionQueue);
        }
    }

    Process {
        id: deleteProc

        stdout: StdioCollector {
            id: deleteOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: deleteErr
            waitForEnd: true
        }
        onExited: code => {
            const failed = root.responseFailure(Model.parseCurlResponse(String(deleteOut.text || "")), code, String(deleteErr.text || ""));
            if (failed !== null)
                root.failure = failed;
            root.refresh();
        }
    }

    Process {
        id: editProc

        stdout: StdioCollector {
            id: editOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: editErr
            waitForEnd: true
        }
        onExited: code => {
            const failed = root.responseFailure(Model.parseCurlResponse(String(editOut.text || "")), code, String(editErr.text || ""));
            if (failed !== null)
                root.failure = failed;
            root.refresh();
        }
    }

    // Lets a completed row read as done before it goes.
    // haseen:ui-timeout
    Timer {
        id: completionRemovalTimer

        interval: 700
        repeat: false
        onTriggered: root.flushCompletedRemovals()
    }

    // Upstream's cadence: every 20 minutes with the panel closed (the bar
    // count), every 2 minutes while it is open; actions refresh at once.
    // haseen:sample
    Timer {
        id: backgroundRefreshTimer

        interval: 1200000
        running: !root.panelOpen && root.hasToken
        repeat: true
        onTriggered: {
            root.refresh();
            root.refreshBarCount();
        }
    }

    // haseen:sample
    Timer {
        id: openRefreshTimer

        interval: 120000
        running: root.panelOpen && root.hasToken
        repeat: true
        onTriggered: {
            root.refresh();
            root.refreshBarCount();
        }
    }

    // The fork's local API: a keybinding, a script or an agent can list and
    // complete tasks without reading the token itself. `complete` goes the way
    // the panel's Space does; "queued" means accepted, the list carries the
    // outcome.
    IpcHandler {
        target: "haseen.todoist"

        function refresh(): void {
            root.refresh();
            root.refreshBarCount();
        }

        function tasks(): string {
            return JSON.stringify(root.tasks.map(task => ({
                id: String(task && task.id != null ? task.id : ""),
                content: String(task && task.content != null ? task.content : ""),
                due: task && task.due && task.due.string ? String(task.due.string) : ""
            })));
        }

        function complete(id: string): string {
            const taskId = String(id == null ? "" : id).trim();
            if (taskId === "")
                return "no task id given";
            if (!root.hasToken)
                return "not connected";
            if (root.completingTaskIds.indexOf(taskId) !== -1)
                return "already completing";
            root.requestComplete(taskId);
            return "queued";
        }

        // Test hook (settings.debugIpc): the service's state as JSON.
        function state(): string {
            if (!root.debugIpc)
                return "";
            return JSON.stringify({
                stateDir: root.stateDir,
                hasToken: root.hasToken,
                quickView: root.quickView,
                barCountMode: root.barCountMode,
                barCountValue: root.barCountValue,
                tasks: root.taskCount,
                truncated: root.listTruncated,
                tokenInvalid: root.tokenInvalid,
                errorText: root.errorText,
                tooltip: root.tooltipText
            });
        }
    }
}
