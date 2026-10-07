import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets
import "MenuModel.js" as Model

// haseen.menu: the command menu. A JSONC tree (default/menu.jsonc merged key
// by key with ~/.config/haseen/menu.jsonc), with providers that fill a
// submenu when it is entered and bash guards (`when`, `checked`, `disabled`)
// answered by one asynchronous batch per open. Type to search the current
// submenu and everything under it; arrows move, Enter or Right opens, Left
// or Backspace on an empty query goes back, Escape closes (panel host).
//
// Opened by `haseen menu [path]` (IPC `menu toggle(path)`); the panel
// registers the `menu` role while it exists so a second toggle reaches it.
// The special path ":about" shows the About view (`haseen about`).
//
// Engine adapted from Omarchy shell/plugins/menu/Menu.qml (MIT, Copyright (c)
// David Heinemeier Hansson): route resolution, provider queue, guard batch,
// search ranking. The UI is haseen's own.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string defaultMenuPath: Paths.haseenPath + "/default/menu.jsonc"
    readonly property string userMenuPath: Paths.userConfig + "/menu.jsonc"
    readonly property string catalogPath: Paths.haseenPath + "/default/catalog.json"
    // bin/ next to share/haseen first, so actions find `haseen` in a checkout too.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property int maxRows: typeof settings.maxRows === "number" && settings.maxRows >= 3 ? Math.round(settings.maxRows) : 10
    readonly property int rowHeight: Theme.fontSize * 2.6

    property var defaultItems: []
    property var userItems: []
    property var items: ({})
    property var itemOrder: []
    property bool loaded: false

    property string activeMenu: "root"
    property var navStack: []
    property string query: ""
    property int current: 0
    property var rows: []

    property var whenResults: ({})
    property var checkedResults: ({})
    property var disabledResults: ({})
    property var providersLoaded: ({})
    property string waitingRoute: ""
    property string waitingProvider: ""
    property var providerQueue: []
    property string pendingRoute: ""

    readonly property bool aboutView: activeMenu === ":about"
    readonly property var activeItem: items[activeMenu] || null
    readonly property string heading: aboutView ? "About" : (activeMenu === "root" ? "Menu" : (activeItem ? (activeItem.title || Model.pathFor(items, activeMenu)) : ""))

    // ---------------------------------------------------------------- open
    function close(): void {
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    // IPC `menu toggle(path)` while open: the same place (or no path) closes,
    // anywhere else navigates there.
    function toggle(path: string): void {
        if (path === "" || resolve(path) === activeMenu) {
            close();
            return;
        }
        open(path);
    }

    function resolve(path: string): string {
        if (path === ":about")
            return path;
        return Model.resolveRoute(items, itemOrder, path);
    }

    function open(path: string): void {
        if (!loaded) {
            pendingRoute = path;
            return;
        }
        const id = resolve(path);
        const entry = items[id];
        // A route naming a leaf (an alias like `remind`) runs it directly.
        if (entry && entry.kind === "action") {
            run(entry.action);
            return;
        }
        navStack = [];
        // A route into provider rows (install.browser) waits for the provider
        // of its nearest ancestor; the provider's submenu shows meanwhile.
        if (!entry && id !== ":about") {
            for (let p = id; p.indexOf(".") > 0;) {
                p = p.slice(0, p.lastIndexOf("."));
                if (items[p] && items[p].provider) {
                    waitingRoute = id;
                    waitingProvider = p;
                    enter(p, false);
                    return;
                }
            }
        }
        enter(entry && entry.kind === "link" ? entry.target : id, false);
    }

    function enter(id: string, push: bool): void {
        if (id !== ":about" && !items[id])
            id = "root";
        if (push && id !== activeMenu)
            navStack = navStack.concat([activeMenu]);
        activeMenu = id;
        input.text = "";
        query = "";
        current = 0;
        if (id === ":about")
            about.refresh();
        else
            loadProvider(id, true);
        rebuild();
    }

    function back(): bool {
        if (activeMenu === "root")
            return false;
        if (navStack.length > 0) {
            const prev = navStack[navStack.length - 1];
            navStack = navStack.slice(0, -1);
            enter(prev, false);
            return true;
        }
        const entry = items[activeMenu];
        enter(entry && entry.parent ? entry.parent : "root", false);
        return true;
    }

    // ---------------------------------------------------------------- rows
    function rebuild(): void {
        if (!loaded || aboutView) {
            rows = [];
            return;
        }
        const out = [];
        const q = query.trim();
        if (q !== "") {
            const scored = [];
            for (const id of itemOrder) {
                const e = items[id];
                if (!e || !Model.isDescendantOf(items, id, activeMenu) || !Model.matchesQuery(e, q))
                    continue;
                if (!Model.isVisible(items, itemOrder, whenResults, e, 0) || !parentsVisible(e))
                    continue;
                scored.push({
                    e: e,
                    s: Model.searchScore(items, e, q)
                });
            }
            scored.sort((a, b) => a.s - b.s);
            for (const x of scored.slice(0, 60))
                out.push(row(x.e, Model.parentPathFor(items, x.e.id)));
        } else {
            for (const id of itemOrder) {
                const e = items[id];
                if (e && e.parent === activeMenu && Model.isVisible(items, itemOrder, whenResults, e, 0))
                    out.push(row(e, e.description));
            }
            if (activeMenu === "apps")
                out.sort((a, b) => a.label.localeCompare(b.label));
        }
        rows = out;
        settle(1);
    }

    function parentsVisible(e: var): bool {
        let p = items[e.parent];
        for (let i = 0; p && p.id !== "root" && i < 32; i++) {
            if (!Model.whenAllows(whenResults, p))
                return false;
            p = items[p.parent];
        }
        return true;
    }

    function row(e: var, detail: string): var {
        return {
            id: e.id,
            kind: e.kind,
            icon: e.icon,
            appIcon: e.appIcon || "",
            label: Model.labelFor(e, checkedResults, disabledResults),
            detail: detail || "",
            disabled: Model.isDisabled(disabledResults, e),
            submenu: e.kind === "menu" || e.kind === "link"
        };
    }

    // Park the cursor on a selectable row, moving in direction dir.
    function settle(dir: int): void {
        const n = rows.length;
        if (n === 0) {
            current = 0;
            return;
        }
        let i = Math.max(0, Math.min(current, n - 1));
        for (let k = 0; k < n; k++) {
            if (!rows[i].disabled) {
                current = i;
                list.positionViewAtIndex(i, ListView.Contain);
                return;
            }
            i = (i + dir + n) % n;
        }
    }

    function shift(delta: int): void {
        if (rows.length === 0)
            return;
        current = (current + delta + rows.length) % rows.length;
        settle(delta);
    }

    function accept(index: int): void {
        const r = rows[index];
        if (!r || r.disabled)
            return;
        const e = items[r.id];
        if (!e)
            return;
        if (r.submenu) {
            enter(e.kind === "link" ? e.target : e.id, true);
        } else if (e.kind === "app") {
            const entry = DesktopEntries.byId(e.appId);
            close();
            if (entry)
                entry.execute();
        } else {
            run(e.action);
        }
    }

    // Actions run detached in bash with haseen's bin/ first on PATH. Two kinds
    // stay in-process: opening the About view, and toggling another panel
    // (which replaces this one, so close first).
    function run(action: string): void {
        if (action.trim() === "haseen about") {
            enter(":about", true);
            return;
        }
        close();
        const panel = Model.panelAction(action);
        if (panel !== "") {
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", panel]);
            return;
        }
        Quickshell.execDetached(["bash", "-c", "PATH=\"$1:$PATH\"; eval \"$2\"", "bash", binDir, action]);
    }

    // ---------------------------------------------------------------- data
    function reloadModel(): void {
        const merged = Model.mergeMenuSources(defaultItems, userItems);
        items = merged.items;
        itemOrder = merged.itemOrder;
        providersLoaded = ({});
        providerQueue = [];
        loaded = true;
        evaluateGuards();
        if (pendingRoute !== "") {
            const r = pendingRoute;
            pendingRoute = "";
            open(r);
        } else {
            if (!aboutView && !items[activeMenu])
                activeMenu = "root";
            loadProvider(activeMenu, true);
            rebuild();
        }
    }

    function applyRows(menuId: string, newRows: var): void {
        const merged = Model.swapProviderRows(items, itemOrder, menuId, newRows);
        items = merged.items;
        itemOrder = merged.itemOrder;
        // Catalog rows carry their own `when` (e.g. laptop-only entries).
        if (newRows.some(r => r.when))
            evaluateGuards();
        rebuild();
        if (waitingProvider === menuId) {
            const route = waitingRoute;
            waitingRoute = "";
            waitingProvider = "";
            if (items[route] && activeMenu === menuId)
                enter(route, true);
        }
    }

    // Shell providers: bash prints rows, parse(text) turns them into items.
    readonly property var providers: ({
            "fonts": {
                script: "cur=$(haseen font current 2>/dev/null); haseen font list 2>/dev/null | while IFS= read -r f; do [ -n \"$f\" ] && printf '%s\\t%s\\n' \"$f\" \"$cur\"; done",
                parse: (id, text) => tabRows(id, text, f => ({
                            label: f[0],
                            icon: "\ue659",
                            checkedNow: f[0] === f[1],
                            action: "haseen font set " + Model.shellQuote(f[0])
                        }))
            },
            "plugins-enable": {
                script: "haseen plugin list 2>/dev/null | awk 'NR > 1 && ($3 == \"available\" || $3 == \"disabled\") { print $1 }'",
                parse: (id, text) => tabRows(id, text, f => ({
                            label: f[0],
                            icon: "\u{f012c}",
                            action: "haseen plugin enable " + Model.shellQuote(f[0])
                        }))
            },
            "plugins-disable": {
                script: "haseen plugin list 2>/dev/null | awk 'NR > 1 && $3 == \"enabled\" { print $1 }'",
                parse: (id, text) => tabRows(id, text, f => ({
                            label: f[0],
                            icon: "\u{f0156}",
                            action: "haseen plugin disable " + Model.shellQuote(f[0])
                        }))
            },
            "plugins-remove": {
                script: "haseen config plugin list-removable 2>/dev/null",
                parse: (id, text) => tabRows(id, text, f => ({
                            label: f[0],
                            icon: "\u{f0b4c}",
                            action: "haseen config plugin remove " + Model.shellQuote(f[0])
                        }))
            },
            "catalog-install": {
                script: "cat \"$HASEEN_PATH/default/catalog.json\"; printf '\\n\\036\\n'; haseen install app --installed 2>/dev/null",
                parse: (id, text) => catalog(id, text, "install")
            },
            "catalog-remove": {
                script: "cat \"$HASEEN_PATH/default/catalog.json\"; printf '\\n\\036\\n'; haseen install app --installed 2>/dev/null",
                parse: (id, text) => catalog(id, text, "remove")
            }
        })

    function tabRows(menuId: string, text: string, make: var): var {
        const out = [];
        const seen = {};
        for (const line of text.split("\n")) {
            if (line.trim() === "")
                continue;
            const f = line.split("\t");
            const r = Model.providerRow(menuId, f[0], make(f));
            while (seen[r.id])
                r.id += "-";
            seen[r.id] = true;
            out.push(r);
        }
        return out;
    }

    function catalog(menuId: string, text: string, mode: string): var {
        const cut = text.indexOf("\x1e");
        let data = null;
        try {
            data = JSON.parse(cut >= 0 ? text.slice(0, cut) : text);
        } catch (e) {
            Plugins.warnOnce("menu-catalog", "menu: catalog.json unreadable: " + e);
            return [];
        }
        const installed = cut >= 0 ? text.slice(cut + 1).split("\n").map(s => s.trim()).filter(s => s !== "") : [];
        return Model.catalogRows(menuId, data, installed, mode);
    }

    function appRows(): var {
        return DesktopEntries.applications.values.filter(e => !e.noDisplay && e.id).map(e => {
            const r = Model.providerRow("apps", e.id, {
                label: e.name,
                description: e.genericName || e.comment || ""
            });
            r.kind = "app";
            r.appId = e.id;
            r.appIcon = e.icon || "";
            r.aliases = e.keywords ? Array.from(e.keywords).map(String) : [];
            return r;
        });
    }

    // Providers run when their submenu is entered (fresh: an install may have
    // changed the list) and, for search, once each.
    function loadProvider(id: string, fresh: bool): void {
        const e = items[id];
        if (!e || !e.provider || (!fresh && providersLoaded[id]))
            return;
        const next = Object.assign({}, providersLoaded);
        next[id] = true;
        providersLoaded = next;
        if (e.provider === "apps") {
            applyRows(id, appRows());
            return;
        }
        if (!providers[e.provider]) {
            Plugins.warnOnce("menu-provider:" + e.provider, "menu: unknown provider '" + e.provider + "' on " + id);
            return;
        }
        if (providerQueue.indexOf(id) < 0)
            providerQueue = providerQueue.concat([id]);
        startProvider();
    }

    function startProvider(): void {
        if (providerProc.running || providerQueue.length === 0)
            return;
        const id = providerQueue[0];
        providerQueue = providerQueue.slice(1);
        const e = items[id];
        if (!e || !providers[e.provider]) {
            startProvider();
            return;
        }
        providerProc.menuId = id;
        providerProc.kind = e.provider;
        providerProc.command = ["bash", "-c", "PATH=\"$1:$PATH\"; export HASEEN_PATH=\"$2\"; eval \"$3\"", "bash", binDir, Paths.haseenPath, providers[e.provider].script];
        providerProc.running = true;
    }

    function searchProviders(): void {
        for (const id of itemOrder) {
            const e = items[id];
            if (e && e.provider && Model.isDescendantOf(items, id, activeMenu))
                loadProvider(id, false);
        }
    }

    property bool guardsPending: false

    function evaluateGuards(): void {
        if (guardProc.running) {
            guardsPending = true;
            return;
        }
        guardsPending = false;
        const script = Model.guardScript(items);
        if (script === "")
            return;
        guardProc.command = ["bash", "-c", "PATH=\"$1:$PATH\"; eval \"$2\"", "bash", binDir, script];
        guardProc.running = true;
    }

    width: typeof settings.width === "number" && settings.width >= 260 ? settings.width : 280
    spacing: Theme.gap
    focus: true

    Component.onCompleted: {
        Plugins.registerRole("menu", pluginId, root);
        input.forceActiveFocus();
    }
    Component.onDestruction: Plugins.unregisterRole("menu", root)

    // DesktopEntries scans on first use and again when .desktop files change;
    // refill an Apps menu that was already entered.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            if (root.providersLoaded["apps"])
                root.applyRows("apps", root.appRows());
        }
    }

    Process {
        id: providerProc

        property string menuId
        property string kind

        stdout: StdioCollector {
            onStreamFinished: {
                const spec = root.providers[providerProc.kind];
                if (spec && root.items[providerProc.menuId])
                    root.applyRows(providerProc.menuId, spec.parse(providerProc.menuId, text));
                Qt.callLater(root.startProvider);
            }
        }
    }

    Process {
        id: guardProc

        stdout: StdioCollector {
            onStreamFinished: {
                const r = Model.parseGuardOutput(text);
                root.whenResults = r.w;
                root.checkedResults = r.c;
                root.disabledResults = r.d;
                root.rebuild();
                if (root.guardsPending)
                    Qt.callLater(root.evaluateGuards);
            }
        }
    }

    FileView {
        path: root.defaultMenuPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const parsed = Model.parseMenuJsonc(text());
            if (parsed === null) {
                console.warn("haseen: menu:", path, "is not valid JSONC, keeping the previous menu");
                return;
            }
            root.defaultItems = parsed;
            root.reloadModel();
        }
        onLoadFailed: error => console.warn("haseen: menu: cannot read", path, "-", FileViewError.toString(error))
    }

    FileView {
        path: root.userMenuPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            const parsed = Model.parseMenuJsonc(text());
            if (parsed === null) {
                console.warn("haseen: menu:", path, "is not valid JSONC, ignoring it");
                return;
            }
            root.userItems = parsed;
            if (root.defaultItems.length > 0)
                root.reloadModel();
        }
    }

    // Test hook (settings.debugIpc): drive the open menu without a keyboard.
    IpcHandler {
        target: "haseen.menu"
        enabled: root.settings.debugIpc === true

        function select(index: int): void {
            root.current = Math.max(0, Math.min(index, root.rows.length - 1));
        }

        function back(): void {
            root.back();
        }

        function accept(): void {
            root.accept(root.current);
        }

        function search(text: string): void {
            input.text = text;
        }

        function state(): string {
            return JSON.stringify({
                menu: root.activeMenu,
                heading: root.heading,
                query: root.query,
                current: root.current,
                rows: root.rows.map(r => (r.disabled ? "-" : "") + r.label + (r.submenu ? " >" : ""))
            });
        }
    }

    // ---------------------------------------------------------------- view
    Row {
        width: parent.width
        spacing: Theme.gap

        // haseen's mark where Omarchy shows its logo; submenus show the way back.
        BrandImage {
            visible: root.activeMenu === "root"
            height: 16 * Math.max(1, Math.round((Theme.fontSize + 2) / 16))
            path: Branding.symbolicPath
            color: Theme.accent
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.activeMenu !== "root"
            text: "\uf053"
            color: Theme.muted
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                anchors.margins: -Theme.gap
                onClicked: root.back()
            }
        }

        Text {
            width: parent.width - Theme.fontSize * 2
            anchors.verticalCenter: parent.verticalCenter
            text: root.heading
            color: Theme.foreground
            elide: Text.ElideLeft
            textFormat: Text.PlainText
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: Theme.accent
        border.width: Theme.borderWidth
        visible: !root.aboutView

        TextInput {
            id: input

            anchors.fill: parent
            anchors.leftMargin: Theme.gap * 1.5
            anchors.rightMargin: Theme.gap * 1.5
            verticalAlignment: TextInput.AlignVCenter
            focus: true
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            onTextChanged: {
                root.query = text;
                root.current = 0;
                if (text.trim() !== "")
                    root.searchProviders();
                root.rebuild();
            }
            onAccepted: root.accept(root.current)
            Keys.onUpPressed: root.shift(-1)
            Keys.onDownPressed: root.shift(1)
            Keys.onTabPressed: root.shift(1)
            Keys.onBacktabPressed: root.shift(-1)
            Keys.onRightPressed: event => {
                if (text === "" && root.rows[root.current] && root.rows[root.current].submenu)
                    root.accept(root.current);
                else
                    event.accepted = false;
            }
            Keys.onLeftPressed: event => {
                event.accepted = text === "" && root.back();
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Backspace && text === "")
                    event.accepted = root.back();
            }
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gap * 1.5
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "Search"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
        }
    }

    ListView {
        id: list

        width: parent.width
        height: Math.max(1, Math.min(root.rows.length, root.maxRows)) * root.rowHeight
        visible: !root.aboutView
        clip: true
        model: root.rows
        currentIndex: root.current
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0

        delegate: Rectangle {
            id: rowItem

            required property var modelData
            required property int index

            width: ListView.view.width
            height: root.rowHeight
            radius: Theme.radius
            color: index === root.current && !modelData.disabled ? Theme.selection : "transparent"
            opacity: modelData.disabled ? 0.5 : 1

            Item {
                id: iconBox

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.fontSize * 1.8
                height: width

                IconImage {
                    anchors.fill: parent
                    visible: rowItem.modelData.appIcon !== ""
                    source: rowItem.modelData.appIcon === "" ? "" : Quickshell.iconPath(rowItem.modelData.appIcon, true)
                }

                Text {
                    anchors.centerIn: parent
                    visible: rowItem.modelData.appIcon === ""
                    text: rowItem.modelData.icon
                    color: Theme.accent
                    font.family: Theme.fontMono
                    font.pixelSize: Theme.fontSize + 2
                }
            }

            Column {
                anchors.left: iconBox.right
                anchors.leftMargin: Theme.gap
                anchors.right: chevron.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: rowItem.modelData.label
                    color: Theme.foreground
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: rowItem.modelData.detail
                    color: Theme.muted
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            Text {
                id: chevron

                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                text: rowItem.modelData.submenu ? "\uf054" : ""
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 2
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: {
                    if (!rowItem.modelData.disabled)
                        root.current = rowItem.index;
                }
                onClicked: root.accept(rowItem.index)
            }
        }
    }

    Text {
        width: parent.width
        visible: !root.aboutView && root.rows.length === 0
        text: root.loaded ? "Nothing here" : "Loading"
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    About {
        id: about

        width: parent.width
        visible: root.aboutView
        binDir: root.binDir
    }
}
