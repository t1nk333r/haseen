import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.Haseen
import "Fuzzy.js" as Fuzzy

// haseen.launcher: type to fuzzy-filter DesktopEntries.applications, arrows
// (or Tab) to move, Enter to launch, Escape to close (the panel host handles
// Escape). Input that starts with an enabled launcher-provider's prefix is
// sent to that provider's query() instead. Providers are created when the
// launcher opens and destroyed with it, so they cost nothing while closed.
// Opened by `haseen shell ipc launcher toggle` (the `launcher` role).
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int maxResults: typeof settings.maxResults === "number" && settings.maxResults >= 1 ? Math.round(settings.maxResults) : 8
    readonly property int rowHeight: Theme.fontSize * 3
    property var providers: []
    property string query: ""

    // [{ title, subtitle, icon, run }]
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
        return ranked.map(e => ({
                    title: e.name,
                    subtitle: e.genericName || e.comment || "",
                    icon: e.icon,
                    run: () => e.execute()
                }));
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

    width: typeof settings.width === "number" && settings.width >= 240 ? settings.width : 520
    spacing: Theme.gap

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
                results: root.results.slice(0, root.maxResults).map(r => r.title)
            });
        }
    }

    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.8
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: Theme.accent
        border.width: Theme.borderWidth

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
            font.pixelSize: Theme.fontSize + 2
            onTextChanged: root.query = text
            onAccepted: root.launch(list.currentIndex)
            Keys.onUpPressed: root.shift(-1)
            Keys.onDownPressed: root.shift(1)
            Keys.onTabPressed: root.shift(1)
            Keys.onBacktabPressed: root.shift(-1)
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: Theme.gap * 1.5
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: "Search applications"
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }
    }

    ListView {
        id: list

        width: parent.width
        height: Math.min(root.results.length, root.maxResults) * root.rowHeight
        visible: root.results.length > 0
        clip: true
        model: root.results
        boundsBehavior: Flickable.StopAtBounds
        highlightMoveDuration: 0
        currentIndex: 0

        delegate: Rectangle {
            id: row

            required property var modelData
            required property int index

            width: ListView.view.width
            height: root.rowHeight
            radius: Theme.radius
            color: ListView.isCurrentItem ? Theme.selection : "transparent"

            IconImage {
                id: icon

                anchors.left: parent.left
                anchors.leftMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                implicitSize: Theme.fontSize * 2
                source: root.iconSource(row.modelData.icon)
                visible: source.toString() !== ""
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: Theme.gap * 2 + Theme.fontSize * 2
                anchors.right: parent.right
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    width: parent.width
                    text: row.modelData.title
                    color: Theme.foreground
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize
                }

                Text {
                    width: parent.width
                    text: row.modelData.subtitle
                    visible: text !== ""
                    color: Theme.muted
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 2
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: list.currentIndex = row.index
                onClicked: root.launch(row.index)
            }
        }
    }

    Text {
        width: parent.width
        visible: root.results.length === 0
        text: "No matches"
        color: Theme.muted
        horizontalAlignment: Text.AlignHCenter
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }
}
