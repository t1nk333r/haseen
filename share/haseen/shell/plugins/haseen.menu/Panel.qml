import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Haseen
import qs.Haseen.Widgets
import "MenuModel.js" as Model
import "MenuStyle.js" as Style

// haseen.menu: the command menu, a port of Omarchy's menu in look and
// behaviour on haseen's data. A JSONC tree (default/menu.jsonc merged key by
// key with ~/.config/haseen/menu.jsonc), with providers that fill a submenu
// when it is entered and bash guards (`when`, `checked`, `disabled`)
// answered by one asynchronous batch per open.
//
// Omarchy's menu: a card centred over a dimmed screen (placement "overlay",
// PanelPopup), no fade. haseen's mark leads the header, which reads "Go…"
// or the submenu's title until you type; typing filters the current submenu
// and everything under it, with a divider before the rows of deeper
// submenus and each row's path under
// it. Up/Down (PageUp/PageDown by six) move, Enter or Right opens or runs,
// Left or Backspace on an empty query goes back, Backspace, Ctrl+Backspace
// and Ctrl+U edit the query, Escape clears it and then closes. The first
// search or submenu step freezes the card's top edge and height; a longer
// list scrolls with the next row peeking past the fold.
//
// Asynchronous answers (guards, providers, desktop entries, a menu file
// edited while open) update the rows in place (MenuModel.syncRows), keep the
// selected row by identity and never move the card's top edge. The last
// answers live on across opens (MenuModel.memory), so a reopened menu draws
// its final rows at once.
//
// Opened by `haseen menu [path]` (IPC `menu toggle(path)`); the panel
// registers the `menu` role while it exists so a second toggle reaches it.
// The special path ":about" shows the About view (`haseen about`).
//
// `haseen menu select` (IPC `menu select(request)`) turns the card into
// Omarchy's dmenu (omarchy-menu-select): the request file's options, filtered
// by the query, at its width and maximum rows height; Enter writes the row
// back to the caller, and any other way out answers "nothing chosen".
//
// Adapted from Omarchy shell/plugins/menu/Menu.qml (MIT, Copyright (c)
// David Heinemeier Hansson): route resolution, provider queue, guard batch,
// search, layout, keys and look. haseen's: the data side (menu.jsonc, its
// overlay, providers, `disabled`, the About view), in-place updates and
// colours mapped onto Theme (MenuStyle.js).
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string defaultMenuPath: Paths.haseenPath + "/default/menu.jsonc"
    readonly property string userMenuPath: Paths.userConfig + "/menu.jsonc"
    // bin/ next to share/haseen first, so actions find `haseen` in a checkout too.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"

    // The whole screen to draw on (placement "overlay", the default). In a
    // plain popup ("center" or "bar") the card alone, in the popup's border.
    readonly property bool overlay: settings.placement === "overlay"
    readonly property real areaHeight: overlay ? height : (screen ? screen.height : 0)

    // ------------------------------------------------------------ look
    readonly property color background: Theme.background
    readonly property color foreground: Theme.foreground
    readonly property color scrim: Qt.alpha(Theme.background, Style.SCRIM)
    readonly property color selectedBackground: Qt.alpha(Theme.foreground, Style.SELECTED_FILL)
    readonly property color selectedText: Theme.accent
    // Row descriptions: Omarchy's 0.52 foreground, raised where a theme needs
    // it to read at 3:1 (Theme.subtle), on the card and on the selected row.
    readonly property color detailOnCard: Theme.subtle(Theme.background)
    readonly property color detailOnSelected: Theme.subtle(Theme.over(Theme.foreground, Style.SELECTED_FILL, Theme.background))
    readonly property string fontFamily: Theme.fontMono
    // Omarchy rounds the menu like the windows (Style.cornerRadius is
    // Hyprland's decoration:rounding); Theme.windowRadius is that value.
    readonly property int cornerRadius: Theme.windowRadius
    readonly property int gapsOut: Math.round(Theme.gap / 2)
    readonly property int borderWidth: overlay ? space(2) : 0
    readonly property int contentMargin: space(18)
    readonly property int headerHeight: Math.max(space(34), fontPx(1.167) + space(6) * 2)
    readonly property int contentSpacing: space(6)
    readonly property int baseRowHeight: Math.max(space(50), fontPx(1) + space(12) * 2)
    readonly property int detailRowHeight: Math.max(space(58), fontPx(1) + fontPx(0.833) + space(12) * 2)
    // How much of the first hidden row stays visible at the fold: enough to
    // read as a cut-off row rather than a bottom border.
    readonly property int rowPeek: Math.round(baseRowHeight * 0.55)
    readonly property int rowSpacing: space(3)
    readonly property int dividerHeight: space(17)
    readonly property int headingSize: fontPx(1.333)
    readonly property int iconSize: fontPx(1.5)
    readonly property int iconColumn: space(36)
    readonly property bool wide: Style.WIDE_MENUS.indexOf(activeMenu) >= 0
    readonly property int baseWidth: typeof settings.width === "number" && settings.width >= 260 ? settings.width : Style.WIDTH
    readonly property int cardWidth: {
        const w = picking ? space(pickWidth) : space(wide ? Style.WIDE : baseWidth);
        return overlay ? Math.min(w, width - gapsOut * 2) : w;
    }
    readonly property int visibleRowsHeight: rowListHeight(layoutSerial, displayModel.count, filterText, searchDivider)
    readonly property int bodyHeight: aboutView ? about.implicitHeight : visibleRowsHeight
    readonly property int cardHeight: {
        const h = (contentMargin + borderWidth) * 2 + headerHeight + contentSpacing + bodyHeight;
        return overlay ? Math.min(h, areaHeight - gapsOut * 2) : h;
    }

    function space(px: real): int {
        return Style.space(Theme.fontSize, px);
    }

    function fontPx(mult: real): int {
        return Style.fontPx(Theme.fontSize, mult);
    }

    // ------------------------------------------------------------ state
    property var defaultItems: []
    property var userItems: []
    property var items: ({})
    property var itemOrder: []
    property bool loaded: false

    property string activeMenu: "root"
    property var navStack: []
    property string filterText: ""
    property int selectedIndex: 0
    // The selected row's itemId: rows draw their cursor from it, so the tint
    // stays on its row while rows move in the model during a refresh.
    property string selectedId: ""
    onSelectedIndexChanged: syncSelectedId()
    property bool cursorActive: true
    property bool searchDivider: false
    property int layoutSerial: 0

    property var whenResults: ({})
    property var checkedResults: ({})
    property var disabledResults: ({})
    property bool guardsPending: false
    property var providersLoaded: ({})
    property var providerQueue: []
    property string waitingRoute: ""
    property string waitingProvider: ""
    property string pendingRoute: ""

    // pick(): the open `haseen menu select` request.
    property bool picking: false
    property string pickPrompt: ""
    property var pickOptions: []
    property int pickWidth: Style.WIDTH
    property int pickHeight: 0
    property string pickSelectionFile: ""
    property string pickDoneFile: ""

    // The card opens centred. The first search keystroke or submenu step
    // freezes its top edge where it sits, and the rows' height with it, so
    // from then on the card grows and shrinks downward instead of
    // re-centring on every change (Omarchy). An asynchronous answer freezes
    // the top edge only: the rows it adds grow the card downward, and the
    // rows already shown stay where they are.
    property int cardTop: -1
    property int maxRowsHeight: -1
    readonly property int centeredTop: Math.max(gapsOut, Math.round((areaHeight - cardHeight) / 2))
    readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop

    readonly property bool aboutView: activeMenu === ":about"
    readonly property var activeItem: items[activeMenu] || null
    readonly property string heading: picking ? pickPrompt : aboutView ? "About" : (activeMenu !== "root" && activeItem ? (activeItem.title || activeItem.label) : "Go")

    implicitWidth: cardWidth
    implicitHeight: cardHeight

    // Not before the compositor has sized the window: a top taken then is the
    // margin, and the card would stay stuck to the screen's top edge.
    function freezeCardTop(withHeight: bool): void {
        if (!overlay || areaHeight <= 0)
            return;
        if (cardTop < 0)
            cardTop = effectiveCardTop;
        if (withHeight && maxRowsHeight < 0)
            maxRowsHeight = visibleRowsHeight;
    }

    // ------------------------------------------------------------ open
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
                    enter(p, false, false, "");
                    return;
                }
            }
        }
        enter(entry && entry.kind === "link" ? entry.target : id, false, false, "");
    }

    // A step taken inside the open menu freezes the card first (Omarchy); a
    // route opened from outside (open()) shows the menu centred as it is.
    function setActiveMenu(id: string, push: bool, fromPointer: bool, rowId: string): void {
        freezeCardTop(true);
        enter(id, push, fromPointer, rowId);
    }

    function enter(id: string, push: bool, fromPointer: bool, rowId: string): void {
        finishPick(null);
        if (id !== ":about" && !items[id])
            id = "root";
        if (push && id !== activeMenu)
            navStack = navStack.concat([{ menu: activeMenu, row: rowId }]);
        activeMenu = id;
        filterText = "";
        selectedIndex = 0;
        cursorActive = true;
        if (fromPointer)
            pointerGate.allowInitialSample();
        else
            pointerGate.reset();
        if (id === ":about")
            about.refresh();
        rebuildDisplay(false);
        loadProvider(id, true);
    }

    // Back restores the row used to enter the parent menu. Routes opened from
    // outside have no origin row, so fall back to the child menu's row.
    function goBack(): bool {
        if (picking || activeMenu === "root")
            return false;
        const child = activeMenu;
        if (navStack.length > 0) {
            const frame = navStack[navStack.length - 1];
            navStack = navStack.slice(0, -1);
            setActiveMenu(frame.menu, false, false, "");
            selectRow(frame.row || child);
        } else {
            const entry = items[activeMenu];
            setActiveMenu(entry && entry.parent ? entry.parent : "root", false, false, "");
            selectRow(child);
        }
        return true;
    }
    // Select the visible row for an item id; nothing changes when it is not shown.
    function selectRow(id: string): void {
        for (let i = 0; i < displayModel.count; i++) {
            if (displayModel.get(i).itemId === id) {
                selectedIndex = i;
                syncSelectedId();
                Qt.callLater(revealCursor);
                return;
            }
        }
    }

    function setFilter(text: string): void {
        if (aboutView)
            return;
        freezeCardTop(true);
        filterText = text;
        selectedIndex = 0;
        cursorActive = true;
        pointerGate.reset();
        if (text.trim() !== "")
            searchProviders();
        rebuildDisplay(false);
    }

    // ------------------------------------------------------------ rows
    // keep: an asynchronous refresh, which keeps the selected row by identity.
    // Otherwise (a new query or submenu) the selection is where the caller
    // put it.
    function rebuildDisplay(keep: bool): void {
        const keepId = keep && selectedIndex >= 0 && selectedIndex < displayModel.count ? displayModel.get(selectedIndex).itemId : "";
        const rows = [];
        searchDivider = false;
        if (picking) {
            for (const r of Model.pickRows(pickOptions, filterText))
                rows.push(r);
        } else if (loaded && !aboutView) {
            const active = items[activeMenu] ? activeMenu : "root";
            const q = filterText.trim();
            if (q !== "") {
                const here = [];
                const deeper = [];
                for (const id of itemOrder) {
                    const e = items[id];
                    if (!e || !Model.isDescendantOf(items, id, active) || !Model.matchesQuery(e, q))
                        continue;
                    if (!Model.isVisible(items, itemOrder, whenResults, e, 0) || !parentsVisible(e))
                        continue;
                    const r = Model.displayRow(items, itemOrder, checkedResults, disabledResults, e, Model.parentPathFor(items, id), "");
                    r.score = Model.searchScore(items, e, q);
                    (e.parent === active ? here : deeper).push(r);
                }
                const bySearch = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path);
                here.sort(bySearch);
                deeper.sort(bySearch);
                searchDivider = here.length > 0 && deeper.length > 0;
                if (searchDivider)
                    for (const r of deeper)
                        r.section = "drilldown";
                for (const r of here.concat(deeper)) {
                    delete r.score;
                    rows.push(r);
                }
            } else {
                for (const id of itemOrder) {
                    const e = items[id];
                    if (e && e.parent === active && Model.isVisible(items, itemOrder, whenResults, e, 0))
                        rows.push(Model.displayRow(items, itemOrder, checkedResults, disabledResults, e, e.description, ""));
                }
                // DesktopEntries can reorder its values when an application
                // starts: keep Apps alphabetical whatever the provider order.
                if (active === "apps")
                    rows.sort((a, b) => {
                        const al = a.label.toLowerCase(), bl = b.label.toLowerCase();
                        return al < bl ? -1 : al > bl ? 1 : (a.itemId < b.itemId ? -1 : a.itemId > b.itemId ? 1 : 0);
                    });
            }
        }
        Model.syncRows(displayModel, rows);
        layoutSerial += 1;
        selectedIndex = settle(Model.selectionAfter(rows, keepId, selectedIndex), 1);
        syncSelectedId();
        if (!keep)
            pointerGate.reset();
        Qt.callLater(revealCursor);
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

    function syncSelectedId(): void {
        selectedId = selectedIndex >= 0 && selectedIndex < displayModel.count ? displayModel.get(selectedIndex).itemId : "";
    }

    // The nearest selectable row from index on, moving in direction dir.
    function settle(index: int, dir: int): int {
        const n = displayModel.count;
        if (n === 0)
            return 0;
        let i = Math.max(0, Math.min(index, n - 1));
        for (let k = 0; k < n; k++) {
            if (!displayModel.get(i).disabled)
                return i;
            i = (i + dir + n) % n;
        }
        return Math.max(0, Math.min(index, n - 1));
    }

    function select(delta: int): void {
        const n = displayModel.count;
        if (n === 0)
            return;
        pointerGate.reset();
        if (!cursorActive) {
            cursorActive = true;
            selectedIndex = settle(delta < 0 ? n - 1 : 0, delta < 0 ? -1 : 1);
        } else {
            const step = ((selectedIndex + delta) % n + n) % n;
            selectedIndex = settle(step, delta < 0 ? -1 : 1);
        }
        revealCursor();
    }

    function selectFromPointer(index: int, item: Item, mouse: var): void {
        if (!pointerGate.moved(item, mouse))
            return;
        if (index < 0 || index >= displayModel.count || displayModel.get(index).disabled)
            return;
        cursorActive = true;
        selectedIndex = index;
    }

    // A description shows under the label while a search runs, and always in
    // a pick list, where it is part of the row.
    function detailShown(detail: string): bool {
        return (filterText !== "" || picking) && detail !== "";
    }

    function rowHeightForDetail(detail: string): int {
        return detailShown(detail) ? detailRowHeight : baseRowHeight;
    }

    // Height the card can give its rows before running off the screen, or
    // past the frozen top edge.
    function availableRowsHeight(): int {
        const top = cardTop >= 0 ? cardTop : gapsOut;
        let available = areaHeight - top - gapsOut - (contentMargin + borderWidth) * 2 - headerHeight - contentSpacing;
        // The starting menu sets the ceiling with the top edge: a longer
        // submenu scrolls behind the fold instead of growing the card.
        if (maxRowsHeight >= 0)
            available = Math.min(available, maxRowsHeight);
        // The caller of a pick list sets its own ceiling (Omarchy's --height).
        if (picking && pickHeight > 0)
            available = Math.min(available, space(pickHeight));
        // A card that swallows the whole screen reads as a page, not a menu.
        return Math.min(available, Math.round(areaHeight * 0.7));
    }

    // When every row fits, the list gets its full height. When they do not,
    // the card ends mid-row: a clipped row tells the eye there is more below
    // the fold, so never come out even on a row boundary.
    function foldedListHeight(totals: var, available: int): int {
        const count = totals.length;
        if (count === 0)
            return baseRowHeight;
        if (totals[count - 1] <= available)
            return totals[count - 1];
        let full = 0;
        while (full < count && totals[full] <= available)
            full++;
        while (full > 1 && totals[full - 1] + rowSpacing + rowPeek > available)
            full--;
        if (full < 1)
            return Math.max(available, baseRowHeight);
        return totals[full - 1] + rowSpacing + rowPeek;
    }

    // The arguments only make the binding above re-evaluate.
    function rowListHeight(_serial: int, _count: int, _filter: string, _divider: bool): int {
        if (displayModel.count === 0)
            return baseRowHeight;
        const totals = [];
        let total = 0;
        let previous = "";
        for (let i = 0; i < displayModel.count; i++) {
            const row = displayModel.get(i);
            if (i > 0)
                total += rowSpacing;
            if (row.section === "drilldown" && previous !== "drilldown")
                total += dividerHeight;
            total += rowHeightForDetail(row.detail);
            previous = row.section;
            totals.push(total);
        }
        return foldedListHeight(totals, availableRowsHeight());
    }

    // ListView.Contain alone parks the cursor row flush with the edge and
    // hides its neighbour; keep the next hidden row peeking past the cursor
    // in the direction of travel.
    function revealCursor(): void {
        if (displayModel.count === 0)
            return;
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
        const item = list.itemAtIndex(selectedIndex);
        if (!item)
            return;
        const reach = rowPeek + rowSpacing;
        if (selectedIndex < displayModel.count - 1) {
            const maxY = Math.max(list.originY, list.originY + list.contentHeight - list.height);
            const overhang = item.y + item.height + reach - (list.contentY + list.height);
            if (overhang > 0)
                list.contentY = Math.min(list.contentY + overhang, maxY);
        }
        if (selectedIndex > 0) {
            const underhang = list.contentY - (item.y - reach);
            if (underhang > 0)
                list.contentY = Math.max(list.contentY - underhang, list.originY);
        }
    }

    function activateIndex(index: int, fromPointer: bool): void {
        if (index < 0 || index >= displayModel.count)
            return;
        const r = displayModel.get(index);
        if (r.disabled)
            return;
        if (r.kind === "pick") {
            finishPick(r.action);
            close();
            return;
        }
        const e = items[r.itemId];
        if (!e)
            return;
        if (r.kind === "menu" || r.kind === "link") {
            setActiveMenu(r.target || r.itemId, true, fromPointer, r.itemId);
        } else if (r.kind === "app") {
            close();
            launchApp(r.appId);
        } else {
            run(r.action);
        }
    }

    // Apps and actions start through Apps, in their own scope (plan 074), so
    // a shell restart does not take them down.
    function launchApp(appId: string): void {
        Apps.launchEntry(DesktopEntries.byId(appId));
    }

    // Actions run in bash with haseen's bin/ first on PATH, in their own
    // scope. Two kinds stay in-process: opening the About view, and toggling
    // another panel (which replaces this one, so close first).
    function run(action: string): void {
        if (action.trim() === "haseen about") {
            setActiveMenu(":about", true, false, "");
            return;
        }
        close();
        const panel = Model.panelAction(action);
        if (panel !== "") {
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", panel]);
            return;
        }
        Apps.launch(["bash", "-c", "PATH=\"$1:$PATH\"; eval \"$2\"", "bash", binDir, action], {
            desktopId: "haseen-menu"
        });
    }

    // IPC `menu select(request)`: REQUEST is a JSON file
    // {prompt, options, selectionFile, doneFile, width, height}. An open pick
    // list it replaces answers "nothing chosen" first.
    function pick(request: string): void {
        finishPick(null);
        pickReader.command = ["cat", "--", request];
        pickReader.running = true;
    }

    function startPick(text: string): void {
        let req = null;
        try {
            req = JSON.parse(text);
        } catch (e) {
            console.warn("haseen: menu: unreadable select request -", e);
            return;
        }
        pickPrompt = String(req.prompt || "Select");
        pickOptions = Array.isArray(req.options) ? req.options : [];
        pickWidth = Number(req.width) > 0 ? Number(req.width) : Style.WIDTH;
        pickHeight = Number(req.height) > 0 ? Number(req.height) : 0;
        pickSelectionFile = String(req.selectionFile || "");
        pickDoneFile = String(req.doneFile || "");
        picking = true;
        navStack = [];
        activeMenu = "root";
        filterText = "";
        selectedIndex = 0;
        cursorActive = true;
        cardTop = -1;
        maxRowsHeight = -1;
        pointerGate.reset();
        rebuildDisplay(false);
        keyCatcher.forceActiveFocus();
    }

    // Answers the caller once: the chosen row, or null for nothing chosen.
    // The done file is the caller's FIFO; opened read-write, a write never
    // blocks, even when the caller has gone.
    function finishPick(selection: var): void {
        if (!picking)
            return;
        const args = ["sh", "-c", "[ $# -gt 2 ] && printf '%s\\n' \"$3\" > \"$1\"; printf 'x\\n' 1<>\"$2\"", "sh", pickSelectionFile, pickDoneFile];
        picking = false;
        pickOptions = [];
        if (pickDoneFile !== "")
            Quickshell.execDetached(selection === null ? args : args.concat([String(selection)]));
        pickDoneFile = "";
        pickSelectionFile = "";
    }

    // Omarchy's query editing keys (Util.editsFilter/editedFilter).
    function editsFilter(event: var): bool {
        if (filterText === "" || (event.modifiers & (Qt.AltModifier | Qt.MetaModifier)))
            return false;
        if (event.key === Qt.Key_U)
            return event.modifiers === Qt.ControlModifier;
        return event.key === Qt.Key_Backspace;
    }

    function editedFilter(event: var): string {
        if (event.key === Qt.Key_U)
            return "";
        if (event.modifiers & Qt.ControlModifier)
            return filterText.replace(/\s+$/, "").replace(/\S+$/, "");
        return filterText.slice(0, -1);
    }

    function handleKey(event: var): void {
        const k = event.key;
        event.accepted = true;
        if (k === Qt.Key_Escape) {
            if (filterText !== "")
                setFilter("");
            else
                close();
        } else if (editsFilter(event)) {
            setFilter(editedFilter(event));
        } else if ((k === Qt.Key_Backspace || k === Qt.Key_Left) && filterText === "") {
            goBack();
        } else if (k === Qt.Key_Up || k === Qt.Key_Backtab) {
            select(-1);
        } else if (k === Qt.Key_Down || k === Qt.Key_Tab) {
            select(1);
        } else if (k === Qt.Key_PageUp) {
            select(-6);
        } else if (k === Qt.Key_PageDown) {
            select(6);
        } else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Right) {
            if (cursorActive)
                activateIndex(selectedIndex, false);
            else if (displayModel.count > 0)
                cursorActive = true;
        } else if (event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
            setFilter(filterText + event.text);
        } else {
            event.accepted = false;
        }
    }

    // ------------------------------------------------------------ data
    function reloadModel(): void {
        const merged = Model.mergeMenuSources(defaultItems, userItems);
        let next = {
            items: merged.items,
            itemOrder: merged.itemOrder
        };
        // Provider rows from earlier opens, until their provider answers again.
        for (const menuId in Model.memory.providerRows)
            if (next.items[menuId])
                next = Model.swapProviderRows(next.items, next.itemOrder, menuId, Model.memory.providerRows[menuId]);
        items = next.items;
        itemOrder = next.itemOrder;
        providersLoaded = ({});
        providerQueue = [];
        const first = !loaded;
        loaded = true;
        evaluateGuards();
        if (pendingRoute !== "") {
            const r = pendingRoute;
            pendingRoute = "";
            open(r);
        } else {
            if (!aboutView && !items[activeMenu])
                activeMenu = "root";
            if (!first)
                freezeCardTop(false);
            rebuildDisplay(!first);
            loadProvider(activeMenu, true);
        }
    }

    // late: the rows answered after the menu was drawn (a provider process,
    // a desktop entry change); the Apps rows come at once on entering.
    function applyRows(menuId: string, newRows: var, late: bool): void {
        const memory = Object.assign({}, Model.memory.providerRows);
        memory[menuId] = newRows;
        Model.memory.providerRows = memory;
        const merged = Model.swapProviderRows(items, itemOrder, menuId, newRows);
        items = merged.items;
        itemOrder = merged.itemOrder;
        // Catalog rows carry their own `when` (e.g. laptop-only entries).
        if (newRows.some(r => r.when))
            evaluateGuards();
        if (late)
            freezeCardTop(false);
        rebuildDisplay(true);
        if (waitingProvider === menuId) {
            const route = waitingRoute;
            waitingRoute = "";
            waitingProvider = "";
            if (items[route] && activeMenu === menuId)
                setActiveMenu(route, true, false, "");
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
            applyRows(id, appRows(), false);
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

    function loadSource(user: bool, text: string): void {
        const parsed = Model.parseMenuJsonc(text);
        const path = user ? userMenuPath : defaultMenuPath;
        if (parsed === null) {
            console.warn("haseen: menu:", path, user ? "is not valid JSONC, ignoring it" : "is not valid JSONC, keeping the previous menu");
            return;
        }
        if (user) {
            Model.memory.userText = text;
            userItems = parsed;
        } else {
            Model.memory.defaultText = text;
            defaultItems = parsed;
        }
        if (defaultItems.length > 0)
            reloadModel();
    }

    Component.onCompleted: {
        Plugins.registerRole("menu", pluginId, root);
        // A reopened menu starts from what the last one knew; the files and
        // the guard batch then confirm it in place.
        const memory = Model.memory;
        if (memory.guards) {
            whenResults = memory.guards.w;
            checkedResults = memory.guards.c;
            disabledResults = memory.guards.d;
        }
        if (memory.defaultText !== null) {
            if (memory.userText !== null)
                userItems = Model.parseMenuJsonc(memory.userText) || [];
            loadSource(false, memory.defaultText);
        }
        keyCatcher.forceActiveFocus();
    }
    Component.onDestruction: {
        finishPick(null);
        Plugins.unregisterRole("menu", root);
    }

    // DesktopEntries scans on first use and again when .desktop files change;
    // refill an Apps menu that was already entered.
    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            if (root.providersLoaded["apps"])
                root.applyRows("apps", root.appRows(), true);
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
                    root.applyRows(providerProc.menuId, spec.parse(providerProc.menuId, text), true);
                Qt.callLater(root.startProvider);
            }
        }
    }

    Process {
        id: pickReader

        stdout: StdioCollector {
            onStreamFinished: root.startPick(text)
        }
    }

    Process {
        id: guardProc

        stdout: StdioCollector {
            onStreamFinished: {
                const r = Model.parseGuardOutput(text);
                Model.memory.guards = r;
                root.whenResults = r.w;
                root.checkedResults = r.c;
                root.disabledResults = r.d;
                root.freezeCardTop(false);
                root.rebuildDisplay(true);
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
            if (text() !== Model.memory.defaultText || !root.loaded)
                root.loadSource(false, text());
        }
        onLoadFailed: error => console.warn("haseen: menu: cannot read", path, "-", FileViewError.toString(error))
    }

    FileView {
        path: root.userMenuPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (text() !== Model.memory.userText)
                root.loadSource(true, text());
        }
        onLoadFailed: {
            if (Model.memory.userText !== null && Model.memory.userText !== "")
                root.loadSource(true, "");
        }
    }

    // Test hook (settings.debugIpc): drive the open menu without a keyboard.
    IpcHandler {
        target: "haseen.menu"
        enabled: root.settings.debugIpc === true

        function select(index: int): void {
            root.selectedIndex = root.settle(index, 1);
            root.revealCursor();
        }

        function back(): void {
            root.goBack();
        }

        function accept(): void {
            root.activateIndex(root.selectedIndex, false);
        }

        function search(text: string): void {
            root.setFilter(text);
        }

        function state(): string {
            const rows = [];
            for (let i = 0; i < displayModel.count; i++) {
                const r = displayModel.get(i);
                rows.push((r.disabled ? "-" : "") + r.label + (r.kind === "menu" || r.kind === "link" ? " >" : ""));
            }
            return JSON.stringify({
                menu: root.activeMenu,
                heading: root.heading,
                picking: root.picking,
                query: root.filterText,
                current: root.selectedIndex,
                rows: rows
            });
        }
    }

    ListModel {
        id: displayModel
    }

    PointerGate {
        id: pointerGate

        referenceItem: card
    }

    // ------------------------------------------------------------ view
    Rectangle {
        anchors.fill: parent
        visible: root.overlay
        color: root.scrim
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.overlay
        onClicked: root.close()
    }

    Rectangle {
        id: card

        x: root.overlay ? Math.round((root.width - width) / 2) : 0
        y: root.overlay ? root.effectiveCardTop : 0
        width: root.cardWidth
        height: root.overlay ? Math.min(root.cardHeight, root.areaHeight - root.gapsOut - root.effectiveCardTop) : root.cardHeight
        radius: root.cornerRadius
        color: root.overlay ? root.background : "transparent"
        border.color: root.foreground
        border.width: root.borderWidth

        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: keyCatcher

            anchors.fill: parent
            focus: true
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => root.handleKey(event)
        }

        Column {
            anchors.fill: parent
            anchors.margins: root.contentMargin + root.borderWidth
            spacing: root.contentSpacing

            // Omarchy's header (no search field, the query in the heading),
            // with haseen's mark in the rows' icon column: the text starts
            // where the row labels do.
            Item {
                width: parent.width
                height: root.headerHeight

                BrandImage {
                    x: root.space(8) + (root.iconColumn - width) / 2
                    anchors.verticalCenter: parent.verticalCenter
                    height: root.headingSize
                    path: Branding.symbolicPath
                    color: Theme.accent
                }

                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: root.space(8) + root.iconColumn + root.space(6)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.filterText || root.heading + "…"
                    color: root.foreground
                    opacity: root.filterText ? 1 : Style.HEADER
                    textFormat: Text.PlainText
                    elide: Text.ElideRight
                    font.family: root.fontFamily
                    font.pixelSize: root.headingSize
                }
            }

            Item {
                width: parent.width
                height: root.visibleRowsHeight
                visible: !root.aboutView

                ListView {
                    id: list

                    anchors.fill: parent
                    model: displayModel
                    clip: true
                    spacing: root.rowSpacing
                    boundsBehavior: Flickable.StopAtBounds

                    section.property: "section"
                    section.criteria: ViewSection.FullString
                    section.delegate: Item {
                        required property string section

                        width: ListView.view.width
                        height: section === "drilldown" ? root.dividerHeight : 0
                        visible: section === "drilldown"

                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: root.space(4)
                            anchors.right: parent.right
                            anchors.rightMargin: root.space(4)
                            anchors.verticalCenter: parent.verticalCenter
                            height: root.space(1)
                            color: Qt.alpha(root.foreground, Style.DIVIDER)
                        }
                    }

                    delegate: MenuRow {
                        required property int index

                        width: ListView.view.width
                        menu: root
                        hasCursor: root.cursorActive && itemId === root.selectedId
                        onHovered: (item, mouse) => root.selectFromPointer(index, item, mouse)
                        onClicked: {
                            if (disabled)
                                return;
                            root.cursorActive = true;
                            root.selectedIndex = index;
                            root.activateIndex(index, true);
                        }
                    }
                }

                // Scroll scrims: once the list has scrolled, content hides above
                // the card top as well as below. Their strength follows the
                // distance still hidden past each edge rather than a clock, so a
                // jump (wrapping from the last row to the first) lands faded.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: Math.min(root.space(28), parent.height / 2)
                    visible: root.overlay && opacity > 0
                    opacity: list.contentHeight > list.height ? Math.max(0, Math.min(1, (list.contentY - list.originY) / height)) : 0
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: root.background
                        }
                        GradientStop {
                            position: 1
                            color: Qt.alpha(root.background, 0)
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(root.space(28), parent.height / 2)
                    visible: root.overlay && opacity > 0
                    opacity: list.contentHeight > list.height ? Math.max(0, Math.min(1, (list.originY + list.contentHeight - list.height - list.contentY) / height)) : 0
                    gradient: Gradient {
                        GradientStop {
                            position: 0
                            color: Qt.alpha(root.background, 0)
                        }
                        GradientStop {
                            position: 1
                            color: root.background
                        }
                    }
                }

                Column {
                    anchors.centerIn: parent
                    spacing: root.space(8)
                    visible: displayModel.count === 0

                    Text {
                        width: root.space(320)
                        text: "\u{f0209}"
                        color: root.selectedText
                        opacity: Style.EMPTY_GLYPH
                        horizontalAlignment: Text.AlignHCenter
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPx(2.333)
                    }

                    Text {
                        width: root.space(320)
                        text: root.filterText ? "No matches for “" + root.filterText + "”" : "Nothing here yet"
                        color: root.foreground
                        opacity: Style.EMPTY_TEXT
                        horizontalAlignment: Text.AlignHCenter
                        textFormat: Text.PlainText
                        font.family: root.fontFamily
                        font.pixelSize: root.fontPx(1.167)
                    }
                }
            }

            About {
                id: about

                width: parent.width
                visible: root.aboutView
                binDir: root.binDir
            }
        }
    }
}
