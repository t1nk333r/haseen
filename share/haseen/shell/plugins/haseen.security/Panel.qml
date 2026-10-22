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
    readonly property real textScale: Math.max(1 / 11, Theme.fontSize / 11)
    readonly property int clearance: Math.max(Theme.gap * 2, Math.round(12 * textScale))
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
    property var draft: ({address: "", port: "", path: ""})
    property var inspection: null
    property var anchor: null
    property var addresses: []
    property var intentArgv: []
    property string intentSource: ""
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
    readonly property var groups: snapshots.tools ? Model.groups(snapshots.tools.tools) : [I18n.mark("All groups")]
    function reveal(item: var): void {
        const f = scroll.contentItem;
        const point = item.mapToItem(f.contentItem, 0, 0);
        const top = Math.max(0, point.y);
        if (item.height > f.height || top < f.contentY) f.contentY = top;
        else if (top + item.height > f.contentY + f.height) f.contentY = top + item.height - f.height;
    }
    function revealFocused(): void {
        const item = root.Window.window ? root.Window.window.activeFocusItem : null;
        for (let ancestor = item; ancestor; ancestor = ancestor.parent) {
            if (ancestor === scroll) { reveal(item); return; }
        }
    }

    function close(): void {
        SecurityRoute.take();
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function") win.closeRequested();
    }
    // Back on a list nothing is selected, so a later read that reshapes the
    // records (Include missing adds `resolution`) is not a changed selection.
    function setView(next: string): void {
        view = next;
        if (next === "") { selectedId = ""; entryId = ""; }
    }
    function back(): void {
        if (view === "endpoint" && body.item && body.item.cancelChoices()) return;
        intentArgv = [];
        if (view === "preview" || view === "review") setView(returnView);
        else if (view === "picker") view = "tool";
        else if (view !== "") setView("");
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
        if (view === "review" || view === "preview") setView(returnView);
        for (const read of [menuRead, statusRead, sourcesRead, toolsRead, servicesRead, doctorRead]) {
            read.generation = generation;
            read.running = true;
        }
        if (page === 3) readAnchor();
    }
    function apply(kind: string, gen: int, data: var, error: string): void {
        if (gen !== generation) return;
        // Qt may marshal signal payload arrays as QVariantList sequences.
        // Retain the already-validated transport as plain JSON for the model.
        data = data === null ? null : JSON.parse(JSON.stringify(data));
        const nextErrors = Object.assign({}, errors);
        nextErrors[kind] = error; errors = nextErrors;
        if (error !== "") Accessible.announce(error, Accessible.Assertive);
        else if (data && kind === "tools") Accessible.announce(I18n.tn("Loaded %1 tool", "Loaded %1 tools", data.tools.length), Accessible.Polite);
        else if (data && kind === "services") Accessible.announce(I18n.tn("Loaded %1 installed service family", "Loaded %1 installed service families", data.services.filter(s => s.installed).length), Accessible.Polite);
        if (kind === "menu" && (!data || !data.enabled)) { close(); return; }
        const previous = kind === "tools" ? selectedTool : kind === "services" ? selectedService : kind === "doctor" ? selectedCapability : null;
        const next = Object.assign({}, snapshots);
        next[kind] = data; snapshots = next;
        const current = kind === "tools" ? selectedTool : kind === "services" ? selectedService : kind === "doctor" ? selectedCapability : null;
        if (previous && JSON.stringify(previous) !== JSON.stringify(current)) {
            intentArgv = []; entryId = "";
            // Notices are transient: written in the language of the moment.
            notice = I18n.tr("This item changed since it was listed. Refresh and choose again.");
        }
        if (menuRoute && ((menuRoute.page === "tools" && kind === "tools") || (menuRoute.page === "services" && kind === "services") || (menuRoute.page === "local" && kind === "doctor"))) {
            const route = menuRoute; menuRoute = null;
            inspect(route.itemId);
        }
    }
    function inspect(id: string): void {
        selectedId = id; intentArgv = []; entryId = "";
        if (page === 1) {
            if (!selectedTool) { notice = I18n.tr("This item changed since it was listed. Refresh and choose again."); return; }
            if (selectedTool.entrypoints.length > 1) view = "picker";
            else { entryId = selectedTool.entrypoints.length === 1 ? selectedTool.entrypoints[0].id : ""; view = "tool"; }
        } else if (page === 2) view = "service";
        else if (page === 3) {
            if (!selectedCapability) { notice = I18n.tr("Prerequisite evidence unavailable. Refresh local status."); return; }
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
        // A detached launch reports nothing back: the command revalidates in
        // its terminal and reports refusals there. Only the remote desktop
        // client starts without one; a tool may share its id.
        const direct = intentSource === "client";
        Apps.launch(direct ? intentArgv : Model.terminal(cli, intentArgv), {desktopId: "haseen-security"});
        notice = direct ? I18n.tr("Launch requested — completion has not been checked.") : I18n.tr("Opened in terminal — completion has not been checked. Helpers run until stopped with Ctrl+C.");
        Accessible.announce(notice, Accessible.Polite);
        intentArgv = [];
        setView(returnView);
    }
    function prepare(argv: var, source: string, preview: bool): void {
        if (refreshing || argv.length === 0) { notice = I18n.tr("Refused: current verified evidence or explicit selection is unavailable."); return; }
        intentArgv = argv;
        intentSource = source;
        returnView = source === "client" ? "" : source;
        // Whole sentences, each translated on its own; rebuilt on every prepare.
        intentCopy = source === "service" ? I18n.tr("May expose network ports according to local configuration. haseen does not change bindings or firewall rules and does not enable this service. The terminal asks before it starts or restarts the service.") : source === "certificate" ? I18n.tr("Machine-wide CA trust change. The terminal re-inspects current bytes and requires the full typed SHA-256 fingerprint for trust; foreign/modified removal is refused.") : source === "client" ? I18n.tr("Open the installed remote desktop client. No address, saved connection or credentials are passed.") : I18n.tr("Runs in a foreground terminal; stop with Ctrl+C.") + " " + (selectedId === "listener" ? I18n.tr("Receives bytes only. It does not execute received data.") : selectedId === "http-server" ? I18n.tr("Serves readable files within this selected directory; escapes outside it are refused.") : I18n.tr("Serves only this file as bytes at /file; does not execute it or expose its containing directory.")) + "\n" + (draft.address === "::1" || /^127\./.test(draft.address) ? I18n.tr("Loopback only — accessible from this workstation.") : I18n.tr("Network exposure — other machines may reach this endpoint. The terminal requires exposure confirmation."));
        previewThenReview = source === "endpoint" && !preview;
        if (preview || previewThenReview) capturePreview();
        else if (argv[2] !== "service-stop") view = "review";
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
        if (operation === "trust" && !Model.anchorTrust(anchor, inspection)) return;
        if (operation === "remove" && !Model.anchorRemoval(anchor)) return;
        prepare(Model.localArgv(cli, selectedCapability, {path: draft.path, fingerprint: anchor && anchor.anchor ? anchor.anchor.sha256 : ""}, operation), "certificate", preview);
        if (operation === "remove") {
            const fp = Model.fingerprint(anchor.anchor.sha256);
            intentCopy += "\n" + (anchor.anchor.transaction === "removing" ? I18n.tr("Complete removal of owned anchor SHA-256: %1", fp) : anchor.anchor.transaction === "pending" ? I18n.tr("Roll back the interrupted trust of owned anchor SHA-256: %1", fp) : I18n.tr("Remove existing unchanged owned anchor SHA-256: %1", fp)) + "\n" + I18n.tr("Transaction: %1", Model.text(anchor.anchor.transaction || "created"));
        }
    }

    Component.onCompleted: {
        // The generic panel host accepts unset/malformed enablement. This
        // optional surface needs literal consent before starting any reads.
        if (Config.pluginEntry("haseen.security").enabled !== true) {
            Qt.callLater(root.close);
            return;
        }
        menuRoute = SecurityRoute.take();
        if (menuRoute) page = Model.pages.indexOf(menuRoute.page);
        refresh();
        Qt.callLater(nav.focusSelected);
    }
    Connections {
        target: Config
        function onMergedChanged() { if (Config.pluginEntry("haseen.security").enabled !== true) root.close(); }
    }
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() { Qt.callLater(root.revealFocused); }
    }
    Connections {
        target: scroll.contentItem
        function onContentHeightChanged() { Qt.callLater(root.revealFocused); }
    }
    Keys.onEscapePressed: event => { root.back(); event.accepted = true; }

    Read { id: menuRead; cli: root.cli; kind: "menu"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: statusRead; cli: root.cli; kind: "status"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: sourcesRead; cli: root.cli; kind: "sources"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: toolsRead; cli: root.cli; kind: "tools"; operands: root.includeMissing ? ["--all"] : []; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: servicesRead; cli: root.cli; kind: "services"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: doctorRead; cli: root.cli; kind: "doctor"; onReceived: (kind, gen, data, error) => root.apply(kind, gen, data, error) }
    Read { id: addressesRead; cli: root.cli; kind: "addresses"; onReceived: (kind, gen, data, error) => { if (gen !== root.generation) return; root.addresses = data ? data.addresses : []; if (error) { root.notice = error; root.Accessible.announce(error, Accessible.Assertive); } } }
    Read { id: anchorRead; cli: root.cli; kind: "anchor"; operands: ["status"]; onReceived: (kind, gen, data, error) => { if (gen !== root.generation) return; root.anchor = data; if (error) { root.notice = error; root.Accessible.announce(error, Accessible.Assertive); } else if (data && data.state === "refused") root.Accessible.announce(data.reason, Accessible.Assertive); } }
    Read { id: certificateRead; cli: root.cli; kind: "certificate"; onReceived: (kind, gen, data, error) => { if (gen !== root.generation || operands[1] !== root.draft.path) return; root.inspection = data; if (error) { root.notice = error; root.Accessible.announce(error, Accessible.Assertive); } else if (data && data.state !== "valid") root.Accessible.announce(data.reason, Accessible.Assertive); } }
    Process {
        id: previewProc
        stdout: StdioCollector { id: previewOut }
        stderr: StdioCollector { id: previewErr }
        onExited: code => {
            if (root.previewGeneration !== root.generation || root.intentArgv.length === 0) return;
            root.previewCode = code;
            const output = previewOut.text + "\n" + previewErr.text;
            root.previewOutput = Model.output(output).slice(0, 65536);
            if (output.length > 65536) { root.previewOutput += "\n" + I18n.tr("Output overflow — preview refused."); root.previewCode = 1; }
            if (root.previewCode !== 0) root.Accessible.announce(I18n.tr("Preview refused or helper error. %1", root.previewOutput), Accessible.Assertive);
            if (root.previewThenReview && root.previewCode === 0 && root.view === "preview") root.view = "review";
            root.previewThenReview = false;
        }
    }

    Rectangle { anchors.fill: parent; color: Qt.alpha(Theme.background, 0.5); MouseArea { anchors.fill: parent; onClicked: root.close() } }
    Rectangle {
        id: card
        anchors.centerIn: parent
        // Away from a vertical bar, which is never mirrored: a mirrored
        // layout negates a horizontal offset, so negate it back.
        anchors.horizontalCenterOffset: Config.barVertical ? (Config.barPosition === "left" ? 1 : -1) * (card.LayoutMirroring.enabled ? -1 : 1) * Config.barThickness / 2 : 0
        anchors.verticalCenterOffset: !Config.barVertical ? (Config.barPosition === "top" ? 1 : -1) * Config.barThickness / 2 : 0
        width: Math.max(1, Math.min(720 * root.textScale, root.width - 2 * (root.clearance + root.frame) - (Config.barVertical ? Config.barThickness : 0)))
        height: Math.max(1, Math.min(640 * root.textScale, root.height - 2 * (root.clearance + root.frame) - (Config.barVertical ? 0 : Config.barThickness)))
        color: Theme.surface
        radius: Theme.radius
        border.width: Theme.borderWidth
        border.color: Theme.border
        Accessible.role: Accessible.Pane
        Accessible.name: I18n.tr("Security workstation")
        MouseArea { anchors.fill: parent; onClicked: {} }
        // Header, navigation and footer share the viewport with the body so
        // narrow windows and fallback fonts cannot collapse it to one pixel.
        Controls.ScrollView {
            id: scroll
            anchors.fill: parent
            anchors.margins: Theme.gap * 2
            clip: true
            contentWidth: availableWidth
            Controls.ScrollBar.horizontal.policy: Controls.ScrollBar.AlwaysOff
            // Left and h go back outside a text editor; Right and l in a
            // mirrored (right-to-left) layout, where the back arrow points
            // right. Handled before the ScrollView, which would take the
            // arrow for its hidden horizontal bar.
            Keys.onPressed: event => {
                const mirrored = scroll.LayoutMirroring.enabled;
                if (mirrored ? event.key !== Qt.Key_L && event.key !== Qt.Key_Right : event.key !== Qt.Key_H && event.key !== Qt.Key_Left) return;
                const focused = root.Window.window ? root.Window.window.activeFocusItem : null;
                if (focused && focused.cursorPosition !== undefined && focused.readOnly === false) return;
                root.back();
                event.accepted = true;
            }
            Column {
                width: scroll.availableWidth
                spacing: Theme.gap
                Header { width: parent.width; nested: root.view !== ""; refreshing: root.refreshing; backPage: [I18n.mark("Overview"), I18n.mark("Tools"), I18n.mark("Services"), I18n.mark("Local actions")][root.page]; onBack: root.back(); onRefresh: root.refresh(); onClose: root.close() }
                Navigation { id: nav; width: parent.width; selected: root.page; onChosen: index => root.choosePage(index) }
                Column {
                    width: parent.width
                    spacing: Theme.gap * 2
                    StateMessage { width: parent.width; visible: root.errors[root.section] !== undefined && root.errors[root.section] !== ""; kind: "error"; message: ({status: I18n.tr("Could not read status"), tools: I18n.tr("Could not read tools"), services: I18n.tr("Could not read services"), doctor: I18n.tr("Could not read doctor")})[root.section]; description: root.errors[root.section] || ""; action: I18n.tr("Retry"); onActivated: root.refresh() }
                    StateMessage { width: parent.width; visible: root.errors.sources !== undefined && root.errors.sources !== ""; kind: "error"; message: I18n.tr("Could not read repository sources (repo-status)"); description: root.errors.sources || ""; action: I18n.tr("Retry source read / Refresh"); onActivated: root.refresh() }
                    StateMessage { width: parent.width; visible: root.sectionLoading; kind: root.snapshots[root.section] ? "stale" : "loading"; message: root.snapshots[root.section] ? I18n.tr("Refreshing local snapshot…") : ({status: I18n.tr("Reading status…"), tools: I18n.tr("Reading tools…"), services: I18n.tr("Reading services…"), doctor: I18n.tr("Reading doctor…")})[root.section]; description: root.snapshots[root.section] ? I18n.tr("Previous snapshot — actions disabled until refreshed.") : I18n.tr("Nothing runs during discovery.") }
                    SelectableText { width: parent.width; visible: root.notice !== ""; text: root.notice; Accessible.name: I18n.tr("Security request notice or read diagnostics") }
                    Loader {
                        id: body
                        width: parent.width
                        sourceComponent: root.view === "tool" ? toolDetail : root.view === "picker" ? picker : root.view === "service" ? serviceDetail : root.view === "endpoint" ? endpointForm : root.view === "certificate" ? certificateForm : root.view === "review" ? review : root.view === "preview" ? preview : [overview, toolList, serviceList, localList][root.page]
                        onLoaded: {
                            scroll.contentItem.contentY = 0;
                            if (root.view !== "" && root.view !== "review" && typeof item.focusHeading === "function") item.focusHeading();
                        }
                    }
                }
                Column {
                    id: footer
                    width: parent.width
                    spacing: Theme.gap
                    Label { width: parent.width; text: I18n.tr("Local status • no network access") }
                    // A Column never moves a narrower child: anchoring it to the
                    // start puts it on the right in a mirrored (right-to-left) panel.
                    ActionButton { anchors.left: parent.left; visible: root.notice !== ""; text: I18n.tr("Refresh status"); enabled: !root.refreshing; onClicked: root.refresh() }
                }
            }
        }
    }
    Component { id: overview; Overview { status: root.snapshots.status || null; sources: root.snapshots.sources || null; serviceCount: root.services.length } }
    Component {
        id: toolList
        Column {
            spacing: Theme.gap
            Field { width: parent.width; label: I18n.tr("Search installed tools"); text: root.query; onEdited: value => root.query = value }
            GroupFilter { width: parent.width; model: root.groups.map((g, i) => i === 0 ? I18n.tr(g) : g); currentIndex: Math.max(0, root.groups.indexOf(root.group || "All groups")); onActivated: root.group = currentIndex === 0 ? "" : root.groups[currentIndex] }
            IncludeMissing { anchors.left: parent.left; checked: root.includeMissing; enabled: !toolsRead.running; onToggled: { root.includeMissing = checked; toolsRead.generation = root.generation; toolsRead.running = true; } }
            StateMessage { id: emptyTools; width: parent.width; visible: !root.sectionLoading && root.tools.length === 0; message: root.query || root.group ? I18n.tr("No tools match this filter.") : I18n.tr("No installed VAPT tools found."); description: I18n.tr("Provisioning reports are not proof of installed entrypoints."); action: root.query || root.group ? I18n.tr("Clear filters") : I18n.tr("Show inventory"); onActivated: { const filtered = root.query !== "" || root.group !== ""; root.query = ""; root.group = ""; if (!filtered) { root.includeMissing = true; if (!toolsRead.running) toolsRead.running = true; } } }
            Inventory { width: parent.width; rows: root.tools; viewportHeight: scroll.height; onInspected: itemId => root.inspect(itemId); onReveal: item => root.reveal(item); onEmptyFocused: emptyTools.focusAction() }
        }
    }
    Component { id: serviceList; Column { spacing: Theme.gap; StateMessage { id: emptyServices; width: parent.width; visible: !root.sectionLoading && root.services.length === 0; message: I18n.tr("No supported installed service packages found."); description: I18n.tr("Supported families: SSH, PostgreSQL, Apache, Nginx, BeEF. No service is installed or enabled here."); action: I18n.tr("Refresh"); onActivated: root.refresh() } Inventory { width: parent.width; rows: root.services; services: true; viewportHeight: scroll.height; onInspected: itemId => root.inspect(itemId); onReveal: item => root.reveal(item); onEmptyFocused: emptyServices.focusAction() } } }
    Component { id: localList; QuickActions { capabilities: root.capabilities; viewportHeight: scroll.height; onReveal: item => root.reveal(item); onChosen: itemId => root.inspect(itemId) } }
    Component { id: toolDetail; ToolDetail { tool: root.selectedTool || null; entryId: root.entryId; stale: root.refreshing; onPick: root.view = "picker"; onRequested: (verb, preview) => { const argv = Model.toolArgv(root.cli, root.selectedTool, root.entryId, verb); if (preview) root.prepare(argv, "tool", true); else { root.prepare(argv, "tool", false); root.launch(); } } } }
    Component { id: picker; EntryPicker { entries: root.selectedTool ? root.selectedTool.entrypoints : []; selected: root.entryId; viewportHeight: scroll.height; onReveal: item => root.reveal(item); onChosen: entryId => { root.entryId = entryId; root.view = "tool"; } } }
    Component { id: serviceDetail; ServiceDetail { service: root.selectedService || null; stale: root.refreshing; onRequested: (verb, preview) => { root.prepare(Model.serviceArgv(root.cli, root.selectedService, verb), "service", preview); if (!preview && verb === "service-stop") root.launch(); } } }
    Component { id: endpointForm; EndpointForm { capability: root.selectedCapability || null; draft: root.draft; addresses: root.addresses; viewportHeight: scroll.height; onReveal: item => root.reveal(item); files: root.snapshots.doctor && root.selectedId === "enumeration-host" ? Model.ownedFiles(root.snapshots.doctor.tools) : []; onChanged: value => root.draft = value; onChooseAddresses: { if (!addressesRead.running) { addressesRead.generation = root.generation; addressesRead.running = true; } } onRequested: (value, preview) => root.endpoint(value, preview) } }
    Component { id: certificateForm; CertificateForm { path: root.draft.path; inspection: root.inspection; anchor: root.anchor; checking: certificateRead.running; anchorChecking: anchorRead.running; onPathChangedByUser: value => { if (root.draft.path !== value) root.inspection = null; root.draft = {path: value}; } onInspect: value => { if (!certificateRead.running) { certificateRead.generation = root.generation; certificateRead.operands = ["inspect", value]; certificateRead.running = true; } } onRequested: (operation, preview) => root.certificate(operation, preview) } }
    Component { id: review; Review { intent: root.intentArgv.map(Model.text).join("\n"); consequences: root.intentCopy; allowed: !root.refreshing && root.intentArgv.length > 0; onCancel: root.back(); onPreview: root.capturePreview(); onProceed: root.launch() } }
    Component { id: preview; Preview { output: root.previewOutput; exitCode: root.previewCode; loading: previewProc.running; onBack: root.back(); onReview: root.view = "review" } }
}
