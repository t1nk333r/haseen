import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The omARR panel: the fleet on the left (health dot, name, one-line state,
// grouped), and beside it the overview (OmarrOverview) or the selected
// service's detail (OmarrDetail); the settings (SettingsView) load in its
// place on demand. Data and actions come from the haseen.omarr service (role
// `omarr`), which polls faster and fetches art while the panel is open.
// Open with `haseen shell ipc panel toggle haseen.omarr` or a bar click.
//
// Keys (while no settings field has the keyboard): j/k or Down/Up move the
// fleet cursor, l/Right open its detail, h/Left back to the overview, Space
// toggles the detail (or opens the settings with no services), Enter or o
// open the selected service in the browser, s the settings, Tab and
// Shift+Tab the overview tabs. Escape closes (PanelPopup).
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: hosted by PanelPopup (no KeyboardPanel, open/close,
// reveal or popout-switch code), theme tokens, overview and detail in files
// of their own, Tab cycles the overview tabs, opening a page closes the panel.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.omarr;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }
    // The service this panel told it is open, told again when it goes.
    property var openedService: null

    property bool showSettings: false
    property string pendingSettings: ""
    property int selectedIndex: -1
    property string detailId: ""
    property string homeTab: "ondeck"

    readonly property color dim: Theme.subtle(Theme.surface)
    readonly property var snapshots: service && service.snapshots ? service.snapshots : []
    readonly property string fleetKey: Model.fleetOrderKey(snapshots)
    readonly property var nowFeed: service && service.nowFeed ? service.nowFeed : ({
            downloads: [],
            calendar: [],
            warnings: [],
            sessions: [],
            onDeck: [],
            recent: [],
            downloadingCount: 0,
            downCount: 0,
            showQueue: false,
            showCalendar: false
        })
    readonly property var calendarGroups: Model.groupedCalendar(service && service.calendarFeed ? service.calendarFeed : [], null, I18n)
    readonly property var homeTabModel: {
        const tabs = [
            {
                id: "ondeck",
                label: I18n.mark("ON DECK")
            },
            {
                id: "recent",
                label: I18n.mark("RECENTLY ADDED")
            }
        ];
        if (nowFeed.showCalendar)
            tabs.push({
                id: "calendar",
                label: I18n.mark("CALENDAR")
            });
        return tabs;
    }
    readonly property string shownHomeTab: {
        for (let i = 0; i < homeTabModel.length; i++) {
            if (homeTabModel[i].id === homeTab)
                return homeTab;
        }
        return homeTabModel.length ? homeTabModel[0].id : "ondeck";
    }
    readonly property bool compact: !!service && service.density === "compact"
    readonly property int rowPad: compact ? Math.round(Theme.gap / 2) : Theme.gap
    readonly property int fleetWidth: Theme.fontSize * 14
    readonly property var selectedSnap: selectedIndex >= 0 && selectedIndex < snapshots.length ? snapshots[selectedIndex] : null
    readonly property var detailSnap: Model.snapshotById(snapshots, detailId)
    readonly property bool settingsBlocked: settingsLoader.item ? settingsLoader.item.editorOpen === true : false
    readonly property bool pagedQueue: !!detailSnap && !!service && service.detailQueueId === detailSnap.id && service.detailQueuePage > 1
    readonly property int detailQueuePage: !!detailSnap && !!service && service.detailQueueId === detailSnap.id ? service.detailQueuePage : 1
    readonly property var detailQueueModel: pagedQueue ? service.detailQueue : detailSnap && detailSnap.queue ? detailSnap.queue : []
    readonly property var detailPager: {
        const total = pagedQueue ? service.detailQueueTotal : detailSnap ? (detailSnap.queueTotal || 0) : 0;
        return Model.listPager(detailQueuePage, detailQueueModel, total, service ? service.pageSize : 0, I18n);
    }

    // Height: the header, then the body at its content's height, never
    // shorter than a few cards (so the popup does not jump with every tab)
    // and never taller than the cap; past the cap the body scrolls.
    readonly property real maxHeight: Math.min(Theme.fontSize * 56, screen && screen.height > 0 ? screen.height * 0.8 : Theme.fontSize * 56)
    readonly property real naturalBody: {
        if (showSettings)
            return settingsLoader.item ? settingsLoader.item.implicitHeight : 0;
        if (snapshots.length === 0)
            return emptyState.implicitHeight;
        return Math.max(fleetContent.implicitHeight + fleetActions.height + Theme.gap, pane.implicitHeight);
    }
    readonly property real minBody: showSettings || snapshots.length > 0 ? Theme.fontSize * 20 : 0
    readonly property real bodyHeight: Math.max(minBody, Math.min(naturalBody, maxHeight - header.height - separator.height - shell.spacing * 2))

    implicitWidth: Theme.fontSize * 48
    implicitHeight: header.height + separator.height + shell.spacing * 2 + bodyHeight

    function claimService(): void {
        if (service && openedService !== service) {
            service.setPanelOpen(true);
            openedService = service;
        }
    }

    function closePanel(): void {
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    function clampSelection(): void {
        if (snapshots.length === 0) {
            selectedIndex = -1;
            return;
        }
        if (selectedIndex < -1)
            selectedIndex = -1;
        if (selectedIndex >= snapshots.length)
            selectedIndex = snapshots.length - 1;
    }

    function indexOfId(id: string): int {
        for (let i = 0; i < snapshots.length; i++) {
            if (snapshots[i].id === id)
                return i;
        }
        return -1;
    }

    function goOverview(): void {
        detailId = "";
        selectedIndex = -1;
    }

    function openAddService(): void {
        pendingSettings = "add";
        showSettings = true;
        if (settingsLoader.item) {
            settingsLoader.item.startAdd();
            pendingSettings = "";
        }
    }

    function openFleetSettings(): void {
        pendingSettings = "fleet";
        showSettings = true;
        if (settingsLoader.item) {
            settingsLoader.item.showFleet();
            pendingSettings = "";
        }
    }

    function moveCursor(dx: int, dy: int): void {
        if (showSettings)
            return;
        if (dx > 0) {
            if (selectedSnap)
                detailId = selectedSnap.id;
            return;
        }
        if (dx < 0) {
            goOverview();
            return;
        }
        selectedIndex += dy;
        clampSelection();
    }

    function activateCursor(): void {
        if (showSettings)
            return;
        if (snapshots.length === 0) {
            showSettings = true;
            return;
        }
        if (selectedIndex < 0) {
            goOverview();
            return;
        }
        if (!selectedSnap)
            return;
        if (detailId === selectedSnap.id)
            goOverview();
        else
            detailId = selectedSnap.id;
    }

    function cycleHomeTab(delta: int): void {
        if (showSettings || detailSnap || homeTabModel.length === 0)
            return;
        let at = 0;
        for (let i = 0; i < homeTabModel.length; i++) {
            if (homeTabModel[i].id === shownHomeTab)
                at = i;
        }
        homeTab = homeTabModel[(at + delta + homeTabModel.length) % homeTabModel.length].id;
    }

    // The page opens in the browser behind the popup, so the popup goes.
    function openService(id: string): void {
        if (!service || !id)
            return;
        service.openService(id);
        closePanel();
    }

    function openSelected(): void {
        if (!showSettings && selectedSnap)
            openService(selectedSnap.id);
    }

    function openCard(item: var, serviceId: string): void {
        if (!service)
            return;
        service.openItem(item, serviceId);
        closePanel();
    }

    function healthColor(health: string): color {
        if (health === "down")
            return Theme.urgent;
        if (health === "up")
            return Theme.foreground;
        return dim;
    }

    function artUrl(path: string): string {
        const rev = service ? service.artRev : null;
        return Model.fileUrl(path, rev && rev[path]);
    }

    function posterSource(serviceId: string, posterId: var): string {
        return service && posterId ? artUrl(service.posterPath(serviceId, posterId)) : "";
    }

    function fanartSource(serviceId: string, posterId: var): string {
        return service && posterId ? artUrl(service.fanartPath(serviceId, posterId)) : "";
    }

    function mediaSource(serviceId: string, itemId: var): string {
        return service && itemId ? artUrl(service.mediaPath(serviceId, itemId)) : "";
    }

    function handleKey(event: var): void {
        if (settingsBlocked || (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)))
            return;
        const key = event.key;
        const t = event.text;
        if (key === Qt.Key_Down || t === "j")
            moveCursor(0, 1);
        else if (key === Qt.Key_Up || t === "k")
            moveCursor(0, -1);
        // The arrows follow the mirrored layout: in a right-to-left panel the
        // detail opens on the left. h and l stay vim's.
        else if ((key === Qt.Key_Right && !I18n.rightToLeft) || (key === Qt.Key_Left && I18n.rightToLeft) || t === "l")
            moveCursor(1, 0);
        else if (key === Qt.Key_Left || key === Qt.Key_Right || t === "h")
            moveCursor(-1, 0);
        else if (key === Qt.Key_Return || key === Qt.Key_Enter || t === "o" || t === "O")
            openSelected();
        else if (key === Qt.Key_Space)
            activateCursor();
        else if (key === Qt.Key_Tab)
            cycleHomeTab(1);
        else if (key === Qt.Key_Backtab)
            cycleHomeTab(-1);
        else if (t === "s" || t === "S")
            showSettings = !showSettings;
        else
            return;
        event.accepted = true;
    }

    onServiceChanged: claimService()
    onSnapshotsChanged: clampSelection()
    onDetailIdChanged: {
        if (service)
            service.clearDetailQueue();
        contentFlick.contentY = 0;
    }
    onShownHomeTabChanged: contentFlick.contentY = 0
    onShowSettingsChanged: {
        if (!showSettings)
            keyCatcher.forceActiveFocus();
    }
    Component.onCompleted: {
        claimService();
        keyCatcher.forceActiveFocus();
    }
    // The service polls its downloaders fast and fetches art only while a
    // panel is open, and clears the unread badge when one opens.
    Component.onDestruction: {
        if (openedService)
            openedService.setPanelOpen(false);
    }

    Item {
        id: keyCatcher

        anchors.fill: parent
        focus: true
        Keys.onPressed: event => root.handleKey(event)

        Column {
            id: shell

            width: parent.width
            spacing: root.rowPad

            Item {
                id: header

                width: parent.width
                height: Math.max(hero.implicitHeight, headerActions.implicitHeight)

                Row {
                    id: hero

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Math.round(Theme.gap * 0.75)

                    Glyph {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "\u{f048d}"
                        color: Theme.foreground
                        font.pixelSize: Theme.font.display
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        textFormat: Text.PlainText
                        text: "omARR" // i18n-ignore: the plugin's name
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.title
                        font.bold: true
                    }
                }

                Text {
                    anchors.left: hero.right
                    anchors.right: headerActions.left
                    anchors.leftMargin: Theme.gap
                    anchors.rightMargin: Theme.gap
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    textFormat: Text.PlainText
                    text: root.service ? String(root.service.statusLabel || "").toUpperCase() : ""
                    color: root.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.font.bodySmall
                    font.bold: true
                    font.letterSpacing: 1.2
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }

                Row {
                    id: headerActions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    OmarrButton {
                        glyph: "\u{f02dc}"
                        tooltipText: I18n.tr("Overview")
                        tooltipBelow: true
                        foreground: !root.showSettings && root.detailId === "" ? Theme.accent : Theme.foreground
                        onClicked: {
                            root.showSettings = false;
                            root.goOverview();
                        }
                    }

                    OmarrButton {
                        glyph: "\u{f0493}"
                        tooltipText: root.showSettings ? I18n.tr("Back") : I18n.tr("Settings")
                        tooltipBelow: true
                        foreground: root.showSettings ? Theme.accent : Theme.foreground
                        onClicked: root.showSettings = !root.showSettings
                    }
                }
            }

            Rectangle {
                id: separator

                width: parent.width
                height: Math.max(1, Theme.borderWidth)
                color: Theme.border
            }

            Item {
                id: body

                width: parent.width
                height: root.bodyHeight

                Flickable {
                    id: settingsFlick

                    anchors.fill: parent
                    visible: root.showSettings
                    clip: true
                    contentWidth: width
                    contentHeight: settingsLoader.item ? settingsLoader.item.implicitHeight : 0
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    interactive: contentHeight > height

                    Loader {
                        id: settingsLoader

                        // The gap is the scroll mark's side, which mirrors.
                        x: LayoutMirroring.enabled ? Theme.gap : 0
                        width: settingsFlick.width - Theme.gap
                        active: root.showSettings
                        source: "SettingsView.qml"
                        onLoaded: {
                            item.service = Qt.binding(() => root.service);
                            item.compact = Qt.binding(() => root.compact);
                            item.closeSettings.connect(() => {
                                root.showSettings = false;
                            });
                            item.editingDone.connect(() => keyCatcher.forceActiveFocus());
                            if (root.pendingSettings === "add")
                                item.startAdd();
                            else if (root.pendingSettings === "fleet")
                                item.showFleet();
                            root.pendingSettings = "";
                        }
                    }

                    OmarrScrollMark {
                        view: settingsFlick
                    }
                }

                Column {
                    id: emptyState

                    width: parent.width
                    visible: !root.showSettings && root.snapshots.length === 0
                    spacing: root.rowPad

                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        // Set rather than implicit: a right-to-left panel then aligns
                        // Latin text and numbers to the right too (plan 109).
                        horizontalAlignment: Text.AlignLeft
                        text: I18n.tr("Nothing on the overview yet. Open settings to add Sonarr, Radarr, SABnzbd, qBittorrent, or any local URL, or scan this machine.")
                        wrapMode: Text.WordWrap
                        color: root.dim
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.body
                        font.italic: true
                    }

                    // A Column does not mirror x: the anchor puts it at the start edge.
                    Pill {
                        anchors.left: parent.left
                        text: I18n.tr("Open settings")
                        onClicked: root.showSettings = true
                    }
                }

                Row {
                    anchors.fill: parent
                    spacing: Theme.gap
                    visible: !root.showSettings && root.snapshots.length > 0

                    Item {
                        width: root.fleetWidth
                        height: parent.height

                        Flickable {
                            id: fleetFlick

                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: fleetActions.top
                            anchors.bottomMargin: Math.round(Theme.gap / 2)
                            clip: true
                            contentWidth: width
                            contentHeight: fleetContent.implicitHeight
                            boundsBehavior: Flickable.StopAtBounds
                            flickableDirection: Flickable.VerticalFlick
                            interactive: contentHeight > height

                            Column {
                                id: fleetContent

                                width: fleetFlick.width
                                spacing: Math.round(Theme.gap / 2)

                                OmarrSectionHeader {
                                    text: I18n.tr("FLEET")
                                }

                                Repeater {
                                    model: {
                                        root.fleetKey;
                                        return Model.groupedServices(root.snapshots);
                                    }

                                    Column {
                                        id: fleetGroup

                                        required property var modelData

                                        width: parent.width
                                        spacing: 2

                                        Text {
                                            visible: fleetGroup.modelData.group !== ""
                                            width: parent.width
                                            textFormat: Text.PlainText
                                            horizontalAlignment: Text.AlignLeft
                                            text: Model.groupLabel(fleetGroup.modelData.group, I18n)
                                            color: root.dim
                                            font.family: Theme.fontFamily
                                            font.pixelSize: Theme.font.bodySmall
                                            font.bold: true
                                        }

                                        Repeater {
                                            model: fleetGroup.modelData.services

                                            OmarrRow {
                                                id: fleetRow

                                                required property var modelData

                                                width: parent.width
                                                implicitHeight: fleetCol.implicitHeight + root.rowPad + 2
                                                hasCursor: fleetMouse.containsMouse || root.indexOfId(modelData.id) === root.selectedIndex
                                                current: root.detailId === modelData.id
                                                opacity: hasCursor || current ? 1 : 0.85

                                                MouseArea {
                                                    id: fleetMouse

                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.selectedIndex = root.indexOfId(fleetRow.modelData.id);
                                                        root.detailId = fleetRow.modelData.id;
                                                    }
                                                    onDoubleClicked: root.openService(fleetRow.modelData.id)
                                                }

                                                Row {
                                                    anchors.left: parent.left
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    anchors.margins: Math.round(Theme.gap * 0.6)
                                                    spacing: Math.round(Theme.gap * 0.75)

                                                    ServiceIcon {
                                                        id: fleetIcon

                                                        anchors.verticalCenter: parent.verticalCenter
                                                        service: fleetRow.modelData
                                                        health: fleetRow.modelData.health || ""
                                                        healthColor: root.healthColor(fleetRow.modelData.health || "")
                                                    }

                                                    Column {
                                                        id: fleetCol

                                                        width: parent.width - fleetIcon.width - parent.spacing
                                                        spacing: 1

                                                        Text {
                                                            width: parent.width
                                                            textFormat: Text.PlainText
                                                            horizontalAlignment: Text.AlignLeft
                                                            text: fleetRow.modelData.name
                                                            color: Theme.foreground
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: Theme.font.body
                                                            font.bold: true
                                                            elide: Text.ElideRight
                                                        }

                                                        Text {
                                                            width: parent.width
                                                            textFormat: Text.PlainText
                                                            horizontalAlignment: Text.AlignLeft
                                                            text: Model.fleetLine(fleetRow.modelData, I18n)
                                                            color: root.dim
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: Theme.font.bodySmall
                                                            elide: Text.ElideRight
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            OmarrScrollMark {
                                view: fleetFlick
                            }
                        }

                        Row {
                            id: fleetActions

                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            spacing: 2

                            OmarrButton {
                                glyph: "\u{f0415}"
                                tooltipText: I18n.tr("Add service")
                                onClicked: root.openAddService()
                            }

                            OmarrButton {
                                glyph: "\u{f035c}"
                                tooltipText: I18n.tr("Fleet")
                                onClicked: root.openFleetSettings()
                            }
                        }
                    }

                    Flickable {
                        id: contentFlick

                        width: parent.width - root.fleetWidth - parent.spacing
                        height: parent.height
                        clip: true
                        contentWidth: width
                        contentHeight: pane.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        interactive: contentHeight > height

                        Column {
                            id: pane

                            // The gap is the scroll mark's side, which mirrors.
                            x: LayoutMirroring.enabled ? Theme.gap : 0
                            width: contentFlick.width - Theme.gap
                            topPadding: Math.round(Theme.gap / 2)
                            bottomPadding: Theme.gap

                            OmarrOverview {
                                width: parent.width
                                visible: !root.detailSnap
                                panel: root
                            }

                            OmarrDetail {
                                width: parent.width
                                visible: !!root.detailSnap
                                panel: root
                            }
                        }

                        OmarrScrollMark {
                            view: contentFlick
                        }
                    }
                }
            }
        }
    }
}
