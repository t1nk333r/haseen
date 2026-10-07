import QtQuick
import Quickshell.Io
import qs.Haseen
import "Wallhaven.js" as Wh
import "../haseen.imagepicker" as Picker

// haseen.themegen's Wallhaven source (plan 072): sort chips, then a grid of
// wallhaven.cc thumbnails that loads the next page when it is scrolled to the
// end. Picking a thumbnail downloads the picture with `haseen wallhaven get`
// (its progress drawn under the grid) and hands the file to the panel, which
// previews and applies it like one of the user's own images. Every network
// call is the CLI's: SFW only without the user's key, 45 calls a minute,
// thumbnails from its cache. Nothing runs until the panel switches here.
Column {
    id: root

    required property string cli
    required property int columns
    required property int cardWidth
    property real pixelRatio: 1

    property string query: ""
    property string sort: Wh.SORTS[0]
    property var items: []
    property int page: 0
    property int lastPage: 0
    property string seed: ""
    property int currentIndex: -1
    property string downloading: ""
    // The id picked while a download ran: fetched once that one ends.
    property string queued: ""
    property int progress: -1
    readonly property bool busy: searchProc.running || getProc.running

    signal picked(string path, string id)
    signal said(string text, bool error)

    // A new search: page 1 of the query and sort, the grid emptied.
    function search(text: string): void {
        query = text;
        items = [];
        page = 0;
        lastPage = 0;
        seed = "";
        currentIndex = -1;
        load(1);
    }

    function setSort(value: string): void {
        if (Wh.SORTS.indexOf(value) < 0 || value === sort)
            return;
        sort = value;
        search(query);
    }

    function load(next: int): void {
        if (searchProc.running)
            return;
        said(next === 1 ? "searching wallhaven…" : "loading page " + next + "…", false);
        searchProc.command = Wh.searchArgv(cli, query, sort, next, seed);
        searchProc.running = true;
    }

    // The next page, when the grid reaches its end and there is one.
    function more(): void {
        if (!searchProc.running && Wh.hasMore(page, lastPage))
            load(page + 1);
    }

    function step(delta: int): void {
        if (items.length > 0)
            select(Math.max(0, Math.min(items.length - 1, currentIndex + delta)));
    }

    function select(index: int): void {
        const item = items[index];
        if (!item)
            return;
        currentIndex = index;
        grid.positionViewAtIndex(index, GridView.Contain);
        if (getProc.running) {
            queued = item.id;
            return;
        }
        fetch(item.id);
    }

    function fetch(id: string): void {
        downloading = id;
        progress = 0;
        getErr.last = "";
        said("downloading " + id + "…", false);
        getProc.command = Wh.getArgv(cli, id);
        getProc.running = true;
    }

    width: columns * (cardWidth + Theme.gap)
    spacing: Theme.gap

    Process {
        id: searchProc

        stdout: StdioCollector {
            id: searchOut
        }
        stderr: StdioCollector {
            id: searchErr
        }
        onExited: code => {
            const result = code === 0 ? Wh.parseSearch(searchOut.text) : null;
            if (!result || !result.ok) {
                const lines = searchErr.text.split("\n").filter(l => l.trim() !== "");
                root.said(lines.length > 0 ? lines[lines.length - 1].replace(/^Error: /, "") : "wallhaven search failed", true);
                return;
            }
            root.items = result.page === 1 ? result.items : Wh.append(root.items, result.items);
            root.page = result.page;
            root.lastPage = result.lastPage;
            if (result.seed !== "")
                root.seed = result.seed;
            root.said(root.items.length === 0 ? "nothing found on wallhaven" : root.items.length + " of " + result.total + " · page " + result.page + " of " + result.lastPage, root.items.length === 0);
        }
    }

    Process {
        id: getProc

        stdout: StdioCollector {
            id: getOut
        }
        // Progress lines as they come; the last other line is the error.
        stderr: SplitParser {
            id: getErr

            property string last: ""

            onRead: line => {
                const p = Wh.progressOf(line);
                if (p >= 0)
                    root.progress = p;
                else if (line.trim() !== "" && line.indexOf("[*]") !== 0)
                    last = line.replace(/^Error: /, "").trim();
            }
        }
        onExited: code => {
            const id = root.downloading;
            const path = code === 0 ? Wh.pathOf(getOut.text) : "";
            root.downloading = "";
            root.progress = -1;
            if (root.queued !== "" && root.queued !== id) {
                const next = root.queued;
                root.queued = "";
                root.fetch(next);
                return;
            }
            root.queued = "";
            if (path === "") {
                root.said(getErr.last !== "" ? getErr.last : "could not download " + id, true);
                return;
            }
            root.said("", false);
            root.picked(path, id);
        }
    }

    Flow {
        width: parent.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: Wh.SORTS

            Choice {
                required property string modelData

                text: Wh.sortLabel(modelData)
                active: root.sort === modelData
                onClicked: root.setSort(modelData)
            }
        }
    }

    GridView {
        id: grid

        width: parent.width
        height: cellHeight * 2
        cellWidth: root.cardWidth + Theme.gap
        cellHeight: Math.round(root.cardWidth * 9 / 16) + Theme.fontSize * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.items
        // Lazy paging: the next page when the view reaches its end.
        onAtYEndChanged: if (atYEnd)
            root.more()
        onCountChanged: if (atYEnd)
            root.more()

        delegate: Picker.ImageCard {
            required property var modelData
            required property int index

            width: root.cardWidth
            path: modelData.thumb
            label: root.downloading === modelData.id ? "downloading…" : modelData.label
            selected: index === root.currentIndex
            pixelRatio: root.pixelRatio
            onPicked: root.select(index)
        }
    }

    // The download's progress; an empty track while none runs.
    Rectangle {
        width: parent.width
        height: Math.max(2, Math.round(Theme.gap / 2))
        radius: height / 2
        color: Theme.surfaceAlt

        Rectangle {
            width: root.progress > 0 ? parent.width * root.progress / 100 : 0
            height: parent.height
            radius: parent.radius
            color: Theme.accent
        }
    }
}
