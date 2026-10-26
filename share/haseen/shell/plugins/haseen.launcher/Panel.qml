import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui
import qs.Haseen
import qs.Haseen.Widgets
import "Fuzzy.js" as Fuzzy

// haseen.launcher: type to fuzzy-filter DesktopEntries.applications, arrows
// (or Tab) to move, Enter to launch, Escape to close (the panel host handles
// Escape). Input that starts with an enabled launcher-provider's prefix is
// sent to that provider's query() instead; a provider with no prefix is asked
// beside the apps on every non-empty query (plan 132), so a word the owner
// types finds it without a prefix. Providers are created when the launcher
// opens and destroyed with it, so they cost nothing while closed; their
// prefixes are listed under the empty input (plan 081).
// Opened by `haseen shell ipc launcher toggle` (the `launcher` role).
//
// Look (plan 117): Omarchy's menu, shell/plugins/menu/Menu.qml:99-110,1199-1330
// — a plain heading-size query line (the empty one dimmed to 0.58, no input
// box), menu rows with the `[launcher]` selected fill and selected border
// over a 36 px icon column, a heading-weight Medium label and a body-small
// detail line. The card is the
// menu's size (plan 122): the width, padding, header, row height and ten rows
// of `haseen.menu`'s card, so SUPER + D and SUPER + SPACE open the same box.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // Ten rows at rest: the default root menu's list (apps, learn, trigger,
    // style, setup, install, remove, update, about, system), so the launcher
    // and the menu open at the same height.
    readonly property int maxResults: typeof settings.maxResults === "number" && settings.maxResults >= 1 ? Math.round(settings.maxResults) : 10
    // Omarchy's menu geometry, from MenuMetrics so the two cards cannot drift:
    // a row that holds a label and a detail line, and a header tall enough for
    // a heading.
    readonly property int rowHeight: MenuMetrics.baseRowHeight
    readonly property int headerHeight: MenuMetrics.headerHeight
    readonly property int iconColumn: MenuMetrics.iconColumn
    // The menu's card is space(300) wide with contentMargin inside a 2 px
    // border; a panel card is padded by popup-padding instead. The launcher
    // takes the difference as its own inset, so the two cards are the same
    // size and their interiors sit on the same line.
    readonly property int menuWidth: typeof settings.width === "number" && settings.width >= 260 ? settings.width : 300
    readonly property int cardWidth: screen ? Math.min(MenuMetrics.space(menuWidth), screen.width - Theme.gapsOut * 2) : MenuMetrics.space(menuWidth)
    readonly property int cardInset: Math.max(0, MenuMetrics.contentMargin - Theme.spacing.popupPadding)
    readonly property int contentWidth: Math.max(1, cardWidth - (MenuMetrics.contentMargin + MenuMetrics.borderWidth) * 2)
    // The selected border's width can change with the theme, so reserve it on
    // every row: a selected row must not push its label sideways.
    readonly property real rowReservedBorder: Border.left(Theme.launcher.selectedBorderSpec)
    property var providers: []
    // Subtitles: the foreground at Omarchy's description alpha, raised to read
    // at 3:1 on the panel and on the selection (Theme.subtle). Theme.muted
    // was below 2:1 on the panel and near 1:1 on the selection in most themes.
    readonly property color subtitleColor: Theme.subtle(Theme.popups.background)
    readonly property color selectedSubtitleColor: subtitleColor
    property string query: ""
    // The enabled providers' prefixes, shown under the empty input:
    // "= Calculator    > Clipboard    : Emoji search".
    readonly property string prefixHelp: providers.filter(p => typeof p.prefix === "string" && p.prefix !== "").map(p => {
        const rec = Plugins.registry[p.pluginId];
        return p.prefix + " " + (rec && rec.name ? rec.name : p.pluginId);
    }).join("    ")

    // [{ title, subtitle, icon, glyph, run }]: `glyph` is drawn in the icon
    // column when `icon` is empty or does not resolve in the icon theme, so
    // no row shows a blank cell.
    readonly property var results: {
        const text = query;
        for (const p of providers) {
            if (typeof p.prefix === "string" && p.prefix !== "" && text.startsWith(p.prefix))
                return providerRows(p, text.slice(p.prefix.length));
        }
        const q = text.trim().toLowerCase();
        const apps = DesktopEntries.applications.values.filter(e => !e.noDisplay);
        let ranked;
        if (q === "") {
            ranked = apps.slice().sort((a, b) => a.name.localeCompare(b.name));
        } else {
            ranked = apps.map(e => ({
                        e: e,
                        s: Fuzzy.entryScore(q, e)
                    })).filter(x => x.s >= 0).sort((a, b) => b.s - a.s || a.e.name.localeCompare(b.e.name)).map(x => x.e);
        }
        const appRows = ranked.map(e => ({
                    title: e.name,
                    subtitle: e.genericName || e.comment || "",
                    icon: e.icon,
                    glyph: "\u{f003b}",
                    run: () => Apps.launchEntry(e)
                }));
        // A provider with no prefix is searched beside the apps (plan 132):
        // typing `account` finds the agent accounts, and the owner never has
        // to remember a prefix for the words they mean. Only on a query — at
        // rest the launcher stays the menu's ten app rows (plan 122, 125).
        if (q === "")
            return appRows;
        const beside = [];
        for (const p of providers) {
            if (typeof p.prefix === "string" && p.prefix === "")
                beside.push(...providerRows(p, text));
        }
        return beside.concat(appRows);
    }

    function providerRows(provider: var, text: string): var {
        try {
            const rows = provider.query(text);
            if (!Array.isArray(rows))
                return [];
            return rows.map(r => ({
                        title: String(r.title || ""),
                        subtitle: String(r.subtitle || ""),
                        icon: String(r.icon || ""),
                        glyph: String(r.glyph || ""),
                        run: typeof r.exec === "function" ? r.exec : () => {}
                    }));
        } catch (e) {
            Plugins.warnOnce("launcher-provider:" + provider.pluginId, "launcher provider " + provider.pluginId + " failed: " + e);
            return [];
        }
    }

    function iconSource(icon: string): string {
        if (icon === "")
            return "";
        return icon.startsWith("/") || icon.indexOf("://") >= 0 ? icon : Quickshell.iconPath(icon, true);
    }

    function launch(index: int): void {
        const row = results[index];
        if (!row)
            return;
        row.run();
        // The panel host (PanelPopup) closes on closeRequested.
        const win = QsWindow.window;
        if (win && typeof win.closeRequested === "function")
            win.closeRequested();
    }

    function shift(delta: int): void {
        if (results.length === 0)
            return;
        list.currentIndex = (list.currentIndex + delta + results.length) % results.length;
    }

    onResultsChanged: list.currentIndex = 0

    width: root.contentWidth + root.cardInset * 2
    leftPadding: root.cardInset
    rightPadding: root.cardInset
    topPadding: root.cardInset
    bottomPadding: root.cardInset
    spacing: MenuMetrics.contentSpacing

    Component.onCompleted: {
        const created = [];
        for (const id in Plugins.registry) {
            const url = Plugins.componentUrl(id, "launcher-provider");
            if (url === "" || !Config.isEnabled(id))
                continue;
            const component = Qt.createComponent(url);
            if (component.status !== Component.Ready) {
                Plugins.reportError(id, component.errorString().trim());
                continue;
            }
            const obj = component.createObject(root, {
                pluginId: id,
                settings: Plugins.settingsFor(id),
                screen: root.screen
            });
            if (obj)
                created.push(obj);
        }
        providers = created;
        input.forceActiveFocus();
    }

    Component.onDestruction: {
        for (const p of providers)
            p.destroy();
    }

    // Test hook (settings.debugIpc): drives the open launcher over IPC, so a
    // smoke test never injects keys into the live session. Exists only
    // while the launcher is open: `qs ipc call haseen.launcher setQuery fire`.
    IpcHandler {
        target: "haseen.launcher"
        enabled: root.settings.debugIpc === true

        function setQuery(text: string): void {
            input.text = text;
        }

        function down(): void {
            root.shift(1);
        }

        function accept(): void {
            root.launch(list.currentIndex);
        }

        function state(): string {
            return JSON.stringify({
                query: root.query,
                current: list.currentIndex,
                results: root.results.slice(0, root.maxResults).map(r => r.title),
                prefixes: root.prefixHelp
            });
        }
    }

    // The query line: Omarchy's menu header is a heading-size line of text,
    // dimmed to 0.58 while empty (Menu.qml:1153-1168), not a bordered field.
    // The enabled providers' prefixes sit at its right edge rather than on a
    // line of their own, so the card keeps the menu's height.
    Item {
        width: root.contentWidth
        height: root.headerHeight

        Text {
            id: placeholder

            anchors.fill: parent
            verticalAlignment: Text.AlignVCenter
            visible: input.text === ""
            text: I18n.tr("Search applications") + "…"
            color: Theme.launcher.text
            opacity: 0.58
            font.family: Theme.font.menuFamily
            font.pixelSize: MenuMetrics.headingSize
        }

        TextInput {
            id: input

            anchors.fill: parent
            verticalAlignment: TextInput.AlignVCenter
            focus: true
            color: Theme.launcher.text
            selectionColor: Theme.selection
            selectedTextColor: Theme.launcher.selectedText
            font.family: Theme.font.menuFamily
            font.pixelSize: MenuMetrics.headingSize
            onTextChanged: root.query = text
            onAccepted: root.launch(list.currentIndex)
            Keys.onUpPressed: root.shift(-1)
            Keys.onDownPressed: root.shift(1)
            Keys.onTabPressed: root.shift(1)
            Keys.onBacktabPressed: root.shift(-1)
        }

        // Hidden when it would not fit beside the query line: the same list
        // is in the IPC state as `prefixes`.
        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: MenuMetrics.space(12)
            visible: input.text === "" && implicitWidth <= parent.width * 0.6
            text: root.prefixHelp
            color: root.subtitleColor
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.family: Theme.font.menuFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    ListView {
        id: list

        width: root.contentWidth
        height: root.results.length === 0 ? 0 : Math.min(root.results.length, root.maxResults) * root.rowHeight + (Math.min(root.results.length, root.maxResults) - 1) * spacing
        visible: root.results.length > 0
        clip: true
        model: root.results
        spacing: MenuMetrics.rowSpacing
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        currentIndex: 0

        delegate: BorderSurface {
            id: row

            required property var modelData
            required property int index

            readonly property bool current: ListView.isCurrentItem
            readonly property real side: root.rowReservedBorder + MenuMetrics.space(8)

            width: ListView.view.width
            height: root.rowHeight
            radius: Theme.radius
            color: row.current ? Theme.launcher.selectedBackground : "transparent"
            borderSpec: row.current ? Theme.launcher.selectedBorderSpec : Border.none()
            Behavior on color {
                ColorAnimation {
                    duration: Theme.duration(120)
                }
            }

            Item {
                id: iconCell

                anchors.left: parent.left
                anchors.leftMargin: row.side
                anchors.verticalCenter: parent.verticalCenter
                width: root.iconColumn
                height: root.iconColumn

                IconImage {
                    id: icon

                    anchors.centerIn: parent
                    implicitSize: MenuMetrics.iconSize
                    source: root.iconSource(row.modelData.icon)
                    visible: source.toString() !== "" && status === Image.Ready
                }

                Glyph {
                    anchors.centerIn: parent
                    visible: !icon.visible
                    glyph: row.modelData.glyph
                    color: row.current ? Theme.launcher.selectedText : root.subtitleColor
                    font.pixelSize: MenuMetrics.iconSize
                }
            }

            Column {
                anchors.left: iconCell.right
                anchors.leftMargin: MenuMetrics.space(6)
                anchors.right: parent.right
                anchors.rightMargin: row.side
                anchors.verticalCenter: parent.verticalCenter
                spacing: MenuMetrics.space(3)

                Text {
                    width: parent.width
                    text: row.modelData.title
                    color: row.current ? Theme.launcher.selectedText : Theme.launcher.text
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.font.menuFamily
                    font.pixelSize: MenuMetrics.headingSize
                    font.weight: Font.Medium
                }

                Text {
                    width: parent.width
                    text: row.modelData.subtitle
                    visible: text !== ""
                    color: root.selectedSubtitleColor
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.font.menuFamily
                    font.pixelSize: Theme.font.bodySmall
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: list.currentIndex = row.index
                onClicked: root.launch(row.index)
            }
        }
    }

    // One row tall, as the menu draws its empty state.
    Text {
        width: root.contentWidth
        height: root.rowHeight
        visible: root.results.length === 0
        text: I18n.tr("No matches")
        color: root.subtitleColor
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: Theme.font.menuFamily
        font.pixelSize: Theme.font.body
    }
}
