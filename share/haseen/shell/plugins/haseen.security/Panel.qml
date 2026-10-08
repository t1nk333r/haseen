import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Model.js" as Model

Item {
    id: root
    property string pluginId
    property var settings: ({})
    property var screen: null
    readonly property string cli: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin/haseen"
    readonly property real scale: Math.max(1 / 11, Theme.fontSize / 11)
    readonly property int clearance: Math.max(Theme.gap * 2, Math.round(12 * scale))
    readonly property int frame: Config.frameEnabled ? Config.frameThickness : 0
    readonly property bool refreshing: menuRead.running || statusRead.running || sourcesRead.running || toolsRead.running || servicesRead.running || doctorRead.running
    property int generation: 0
    property var snapshots: ({})
    property var errors: ({})
    property int page: 0
    property string view: ""
    property string selectedId: ""
    property string entryId: ""
    property string query: ""
    property string group: ""
    property bool includeMissing: false
    property string notice: ""
    onNoticeChanged: if (notice !== "") Accessible.announce(notice, Accessible.Polite)
    property var draft: ({address: "", port: "", path: ""})
    property var inspection: null
    property var anchor: null
    property var addresses: []
    property var intentArgv: []
    property string intentCopy: ""
    property string returnView: ""
    property string previewOutput: ""
    property int previewCode: -1
    property bool previewThenReview: false
    property int previewGeneration: 0
    property var menuRoute: null
    readonly property var tools: snapshots.tools ? Model.filterTools(snapshots.tools.tools, query, group) : []
    readonly property var services: snapshots.services ? Model.families.map(id => snapshots.services.services.find(s => s.id === id)).filter(s => s && s.installed) : []
    readonly property var capabilities: snapshots.doctor ? snapshots.doctor.workflow.capabilities : []
    readonly property var selectedTool: snapshots.tools ? snapshots.tools.tools.find(t => t.id === selectedId) : null
    readonly property var selectedService: services.find(s => s.id === selectedId)
    readonly property var selectedCapability: capabilities.find(c => c.id === selectedId)
    readonly property bool sectionLoading: [statusRead, toolsRead, servicesRead, doctorRead][page].running
    readonly property string section: ["status", "tools", "services", "doctor"][page]
    readonly property var groups: snapshots.tools ? Model.groups(snapshots.tools.tools) : ["All groups"]
    function reveal(item: var): void {
        const f = scroll.contentItem;
        const point = item.mapToItem(f.contentItem, 0, 0);
        if (point.y < f.contentY) f.contentY = point.y;
        else if (point.y + item.height > f.contentY + f.height) f.contentY = point.y + item.height - f.height;
    }

    function close(): void {
        Model.consume();
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function") win.closeRequested();
    }
    function back(): void {
        intentArgv = [];
        if (view === "preview" || view === "review") view = returnView;
        else if (view === "picker") view = "tool";
        else if (view !== "") view = "";
        else if (query !== "") query = "";
        else close();
    }
    function readAnchor(): void {
        if (!anchorRead.running) { anchorRead.generation = generation; anchorRead.running = true; }
    }
    function choosePage(index: int): void {
        page = index; view = ""; selectedId = ""; entryId = ""; intentArgv = [];
        if (index === 3) readAnchor();
    }
    function refresh(): void {
        if (refreshing) return;
        generation++;
        intentArgv = []; inspection = null;
        previewThenReview = false;
        if (view === "review" || view === "preview") view = returnView;
        for (const read of [menuRead, statusRead, sourcesRead, toolsRead, servicesRead, doctorRead]) {
            read.generation = generation;
            read.running = true;
        }
        if (page === 3) readAnchor();
    }
    function apply(kind: string, gen: int, data: var, error: string): void {
        if (gen !== generation) return;
        const nextErrors = Object.assign({}, errors);
        nextErrors[kind] = error; errors = nextErrors;
        if (error !== "") Accessible.announce(error, Accessible.Assertive);
        else if (data && kind === "tools") Accessible.announce("Loaded " + data.tools.length + " tools", Accessible.Polite);
        else if (data && kind === "services") Accessible.announce("Loaded " + data.services.filter(s => s.installed).length + " installed service families", Accessible.Polite);
        if (kind === "menu" && (!data || !data.enabled)) { close(); return; }
        const previous = kind === "tools" ? selectedTool : kind === "services" ? selectedService : kind === "doctor" ? selectedCapability : null;
        const next = Object.assign({}, snapshots);
        next[kind] = data; snapshots = next;
        const current = kind === "tools" ? selectedTool : kind === "services" ? selectedService : kind === "doctor" ? selectedCapability : null;
        if (previous && JSON.stringify(previous) !== JSON.stringify(current)) {
            intentArgv = []; entryId = "";
            notice = "This item changed since it was listed. Refresh and choose again.";
        }
        if (menuRoute && ((menuRoute.page === "tools" && kind === "tools") || (menuRoute.page === "services" && kind === "services") || (menuRoute.page === "local" && kind === "doctor"))) {
            const route = menuRoute; menuRoute = null;
            inspect(route.itemId);
        }
    }
    function inspect(id: string): void {
        selectedId = id; intentArgv = []; entryId = "";
        if (page === 1) {
            if (!selectedTool) { notice = "This item changed since it was listed. Refresh and choose again."; return; }
            if (selectedTool.entrypoints.length > 1) view = "picker";
            else { entryId = selectedTool.entrypoints.length === 1 ? selectedTool.entrypoints[0].id : ""; view = "tool"; }
        } else if (page === 2) view = "service";
        else if (page === 3) {
            if (!selectedCapability) { notice = "Prerequisite evidence unavailable. Refresh local status."; return; }
            const config = snapshots.doctor.workflow.settings;
            draft = {address: config.bindAddress, port: "", path: id === "enumeration-host" ? (config.enumerationScript || "") : ""};
            inspection = null;
            if (id === "proxy-ca") { view = "certificate"; readAnchor(); }
            else if (id === "remmina") prepare(Model.localArgv(cli, selectedCapability, draft, ""), "client", false);
            else view = "endpoint";
        }
    }
    function launch(): void {
        if (refreshing || intentArgv.length === 0) return;
        // No detached result exists. The foreground CLI is confirmation authority.
        Apps.launch(selectedId === "remmina" ? intentArgv : Model.terminal(cli, intentArgv), {desktopId: "haseen-security"});
        notice = selectedId === "remmina" ? "Client launch requested — completion has not been checked." : "Opened in terminal — completion has not been checked. Helpers run until stopped with Ctrl+C.";
        intentArgv = [];
        view = returnView;
    }
    function prepare(argv: var, source: string, preview: bool): void {
        if (refreshing || argv.length === 0) { notice = "Refused: current verified evidence or explicit selection is unavailable."; return; }
        intentArgv = argv;
        returnView = source === "client" ? "" : source;
        intentCopy = source === "service" ? "May expose network ports according to local configuration. haseen does not change bindings or firewall rules and does not enable this service." : source === "certificate" ? "Machine-wide CA trust change. The terminal re-inspects current bytes and requires the full typed SHA-256 fingerprint for trust; foreign/modified removal is refused." : source === "client" ? "Open the installed remote desktop client. No address, saved connection or credentials are passed." : "Runs in a foreground terminal; stop with Ctrl+C. " + (selectedId === "listener" ? "Receives bytes only. It does not execute received data." : selectedId === "http-server" ? "Serves readable files within this selected directory; escapes outside it are refused." : "Serves only this file as bytes at /file; does not execute it or expose its containing directory.") + "\n" + (draft.address === "::1" || /^127\./.test(draft.address) ? "Loopback only — accessible from this workstation." : "Network exposure — other machines may reach this endpoint. The terminal requires exposure confirmation.");
        previewThenReview = source === "endpoint" && !preview;
        if (preview || previewThenReview) capturePreview(); else view = "review";
    }
    function capturePreview(): void {
        if (!intentArgv.length || previewProc.running) return;
        view = "preview"; previewOutput = ""; previewCode = -1;
        previewGeneration = generation;
        previewProc.command = Model.dryRun(intentArgv);
        previewProc.running = true;
    }
    function endpoint(value: var, preview: bool): void {
        draft = value;
        prepare(Model.localArgv(cli, selectedCapability, draft, ""), "endpoint", preview);
    }
    function certificate(operation: string, preview: bool): void {
        if (operation === "trust" && (!inspection || inspection.state !== "valid")) return;
        if (operation === "remove" && (!anchor || anchor.state !== "owned" || !anchor.anchor || !anchor.anchor.unchanged)) return;
        prepare(Model.localArgv(cli, selectedCapability, {path: draft.path, fingerprint: anchor && anchor.anchor ? anchor.anchor.sha256 : ""}, operation), "certificate", preview);
    }

    Component.onCompleted: {
        menuRoute = Model.consume();
        if (menuRoute) page = Model.pages.indexOf(menuRoute.page);
        refresh();
        Qt.callLater(nav.focusSelected);
    }
    Connections {
        target: Config
        function onMergedChanged() { if (Config.pluginEntry("haseen.security").enabled !== true) root.close(); }
    }
    Keys.onEscapePressed: event => { root.back(); event.accepted = true; }
    // Text inputs consume their own editing keys before these navigation keys.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_H || event.key === Qt.Key_Left) { root.back(); event.accepted = true; }
    }

    Read { id: menuRead; cli: root.cli; kind: "menu"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: statusRead; cli: root.cli; kind: "status"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: sourcesRead; cli: root.cli; kind: "sources"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: toolsRead; cli: root.cli; kind: "tools"; operands: root.includeMissing ? ["--all"] : []; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: servicesRead; cli: root.cli; kind: "services"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: doctorRead; cli: root.cli; kind: "doctor"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: addressesRead; cli: root.cli; kind: "addresses"; onReceived: (kind, gen, data, error) => { if (gen !== root.generation) return; root.addresses = data ? data.addresses : []; if (error) root.notice = error; } }
    Read { id: anchorRead; cli: root.cli; kind: "anchor"; operands: ["status"]; onReceived: (kind, gen, data, error) => { if (gen !== root.generation) return; root.anchor = data; if (error) root.notice = error; } }
    Read { id: certificateRead; cli: root.cli; kind: "certificate"; onReceived: (kind, gen, data, error) => { if (gen !== root.generation) return; if (operands[1] === root.draft.path) root.inspection = data; if (error) root.notice = error; } }
    Process {
        id: previewProc
        stdout: StdioCollector { id: previewOut }
        stderr: StdioCollector { id: previewErr }
        onExited: code => {
            if (root.previewGeneration !== root.generation || root.intentArgv.length === 0) return;
            root.previewCode = code;
            const output = previewOut.text + "\n" + previewErr.text;
            root.previewOutput = Model.output(output).slice(0, 65536);
            if (output.length > 65536) { root.previewOutput += "\nOutput overflow — preview refused."; root.previewCode = 1; }
            if (root.previewThenReview && root.previewCode === 0 && root.view === "preview") root.view = "review";
            root.previewThenReview = false;
        }
    }

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.background, 0.5); MouseArea { anchors.fill: parent; onClicked: root.close() } }
    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Config.barVertical ? (Config.barPosition === "left" ? 1 : -1) * Config.barThickness / 2 : 0
        anchors.verticalCenterOffset: !Config.barVertical ? (Config.barPosition === "top" ? 1 : -1) * Config.barThickness / 2 : 0
        width: Math.max(1, Math.min(720 * root.scale, root.width - 2 * (root.clearance + root.frame) - (Config.barVertical ? Config.barThickness : 0)))
        height: Math.max(1, Math.min(640 * root.scale, root.height - 2 * (root.clearance + root.frame) - (Config.barVertical ? 0 : Config.barThickness)))
        color: Theme.surface
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.border
        MouseArea { anchors.fill: parent; onClicked: {} }
        Column {
            anchors.fill: parent
            anchors.margins: Theme.gap * 2
            spacing: Theme.gap
            Header { width: parent.width; nested: root.view !== ""; refreshing: root.refreshing; backPage: ["Overview", "Tools", "Services", "Local actions"][root.page]; onBack: root.back(); onRefresh: root.refresh(); onClose: root.close() }
            Navigation { id: nav; width: parent.width; selected: root.page; onChosen: index => root.choosePage(index) }
            Controls.ScrollView {
                id: scroll
                width: parent.width
                height: Math.max(1, parent.height - y - footer.height - parent.spacing)
                clip: true
                contentWidth: availableWidth
                Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
                Column {
                    width: scroll.availableWidth
                    spacing: Theme.gap * 2
                    StateMessage { width: parent.width; visible: root.errors[root.section] !== undefined && root.errors[root.section] !== ""; state: "error"; message: "Could not read " + root.section; description: root.errors[root.section] || ""; action: "Retry"; onActivated: root.refresh() }
                    StateMessage { width: parent.width; visible: root.sectionLoading; state: root.snapshots[root.section] ? "stale" : "loading"; message: root.snapshots[root.section] ? "Refreshing local snapshot…" : "Reading " + root.section + "…"; description: root.snapshots[root.section] ? "Previous snapshot — actions disabled until refreshed." : "Nothing runs during discovery." }
                    Loader {
                        id: body
                        width: parent.width
                        sourceComponent: root.view === "tool" ? toolDetail : root.view === "picker" ? picker : root.view === "service" ? serviceDetail : root.view === "endpoint" ? endpointForm : root.view === "certificate" ? certificateForm : root.view === "review" ? review : root.view === "preview" ? preview : [overview, toolList, serviceList, localList][root.page]
                        onLoaded: {
                            if (root.view !== "" && root.view !== "review") item.forceActiveFocus();
                            scroll.contentItem.contentY = 0;
                        }
                    }
                }
            }
            Column {
                id: footer
                width: parent.width
                spacing: Theme.gap
                Label { width: parent.width; text: "Local status • no network access" }
                Label { width: parent.width; visible: root.notice !== ""; text: root.notice }
                ActionButton { visible: root.notice !== ""; text: "Refresh status"; enabled: !root.refreshing; onClicked: root.refresh() }
            }
        }
    }
    Component { id: overview; Overview { status: root.snapshots.status || null; sources: root.snapshots.sources || null; serviceCount: root.services.length } }
    Component {
        id: toolList
        Column {
            spacing: Theme.gap
            Field { width: parent.width; label: "Search installed tools"; text: root.query; onEdited: value => root.query = value }
            GroupFilter { width: parent.width; model: root.groups; currentIndex: Math.max(0, root.groups.indexOf(root.group || "All groups")); onActivated: root.group = currentIndex === 0 ? "" : root.groups[currentIndex] }
            IncludeMissing { checked: root.includeMissing; enabled: !toolsRead.running; onToggled: { root.includeMissing = checked; toolsRead.generation = root.generation; toolsRead.running = true; } }
            StateMessage { id: emptyTools; width: parent.width; visible: !root.sectionLoading && root.tools.length === 0; message: root.query || root.group ? "No tools match this filter." : "No installed VAPT tools found."; description: "Provisioning reports are not proof of installed entrypoints."; action: root.query || root.group ? "Clear filters" : "Show inventory"; onActivated: { const filtered = root.query !== "" || root.group !== ""; root.query = ""; root.group = ""; if (!filtered) { root.includeMissing = true; if (!toolsRead.running) toolsRead.running = true; } } }
            Inventory { width: parent.width; rows: root.tools; onInspected: itemId => root.inspect(itemId); onReveal: item => root.reveal(item); onEmptyFocused: emptyTools.focusAction() }
        }
    }
    Component { id: serviceList; Column { spacing: Theme.gap; StateMessage { width: parent.width; visible: !root.sectionLoading && root.services.length === 0; message: "No supported installed service packages found."; description: "Supported families: SSH, PostgreSQL, Apache, Nginx, BeEF. No service is installed or enabled here."; action: "Refresh"; onActivated: root.refresh() } Inventory { width: parent.width; rows: root.services; services: true; onInspected: itemId => root.inspect(itemId); onReveal: item => root.reveal(item) } } }
    Component { id: localList; QuickActions { capabilities: root.capabilities; onChosen: itemId => root.inspect(itemId) } }
    Component { id: toolDetail; ToolDetail { tool: root.selectedTool || null; entryId: root.entryId; stale: root.refreshing; onPick: root.view = "picker"; onRequested: (verb, preview) => { const argv = Model.toolArgv(root.cli, root.selectedTool, root.entryId, verb); if (preview) root.prepare(argv, "tool", true); else { root.prepare(argv, "tool", false); root.launch(); } } } }
    Component { id: picker; EntryPicker { entries: root.selectedTool ? root.selectedTool.entrypoints : []; selected: root.entryId; onChosen: entryId => { root.entryId = entryId; root.view = "tool"; } } }
    Component { id: serviceDetail; ServiceDetail { service: root.selectedService || null; stale: root.refreshing; onRequested: (verb, preview) => { root.prepare(Model.serviceArgv(root.cli, root.selectedService, verb), "service", preview); if (!preview && verb === "service-stop") root.launch(); } } }
    Component { id: endpointForm; EndpointForm { capability: root.selectedCapability || null; draft: root.draft; addresses: root.addresses; files: root.snapshots.doctor && root.selectedId === "enumeration-host" ? Model.ownedFiles(root.snapshots.doctor.tools) : []; onChanged: value => root.draft = value; onChooseAddresses: { if (!addressesRead.running) { addressesRead.generation = root.generation; addressesRead.running = true; } } onRequested: (value, preview) => root.endpoint(value, preview) } }
    Component { id: certificateForm; CertificateForm { path: root.draft.path; inspection: root.inspection; anchor: root.anchor; checking: certificateRead.running; anchorChecking: anchorRead.running; onPathChangedByUser: value => { if (root.draft.path !== value) root.inspection = null; root.draft = {path: value}; } onInspect: value => { if (!certificateRead.running) { certificateRead.generation = root.generation; certificateRead.operands = ["inspect", value]; certificateRead.running = true; } } onRequested: (operation, preview) => root.certificate(operation, preview) } }
    Component { id: review; Review { intent: root.intentArgv.map(Model.text).join("\n"); consequences: root.intentCopy; allowed: !root.refreshing && root.intentArgv.length > 0; onCancel: root.back(); onPreview: root.capturePreview(); onProceed: root.launch() } }
    Component { id: preview; Preview { output: root.previewOutput; exitCode: root.previewCode; loading: previewProc.running; onBack: root.back(); onReview: root.view = "review" } }
}
