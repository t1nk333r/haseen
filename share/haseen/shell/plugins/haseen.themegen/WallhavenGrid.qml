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
//
// The grid's model is a ListModel that later pages are appended to: handing
// the view a new array per page rebuilt it and threw the scroll position back
// to the top (plan 083). `currentIndex` is the keyboard's cell; moving it
// downloads nothing, `select` (a click, or Enter in the panel) does.
Column {
    id: root

    required property string cli
    required property int columns
    required property int cardWidth
    property real pixelRatio: 1

    property string query: ""
    property string sort: Wh.SORTS[0]
    property int page: 0
    property int lastPage: 0
    property string seed: ""
    // The ids listed so far (id -> true): a later page repeats none.
    property var seen: ({})
    property int currentIndex: -1
    property string downloading: ""
    // The id picked while a download ran: fetched once that one ends.
    property string queued: ""
    property int progress: -1
    // A new search asked for while a page loaded: run once that one ends,
    // and that page is dropped.
    property bool restart: false
    readonly property int count: results.count
    readonly property bool fetching: getProc.running
    readonly property bool busy: searchProc.running || getProc.running
    // For the panel's debugIpc state: the view's scroll position.
    readonly property real scrollY: grid.contentY

    signal picked(string path, string id)
    signal said(string text, bool error)

    // A new search: page 1 of the query and sort, the grid emptied. The page
    // is reset first, so the emptied view asks for no next page.
    function search(text: string): void {
        query = text;
        page = 0;
        lastPage = 0;
        seed = "";
        currentIndex = -1;
        results.clear();
        seen = {};
        load(1);
    }

    function setSort(value: string): void {
        if (Wh.SORTS.indexOf(value) < 0 || value === sort)
            return;
        sort = value;
        search(query);
    }

    function load(next: int): void {
        if (searchProc.running) {
            if (next === 1)
                restart = true;
            return;
        }
        said(next === 1 ? "searching wallhaven…" : "loading page " + next + "…", false);
        searchProc.command = Wh.searchArgv(cli, query, sort, next, seed);
        searchProc.running = true;
    }

    // The next page, when the grid reaches its end and there is one.
    function more(): void {
        if (!searchProc.running && Wh.hasMore(page, lastPage))
            load(page + 1);
    }

    // The view shows its last row: scrolled there, or a page too short to
    // fill it. Worked out from the count, not read from the view's atYEnd,
    // which lags a count change until the new rows are laid out: read on a
    // count change, it loaded page 2 before page 1 was seen (plan 083).
    function atEnd(): bool {
        return grid.contentY + grid.height >= Math.ceil(results.count / Math.max(1, columns)) * grid.cellHeight - 1;
    }

    // The keyboard's cell: dx by one, dy by a row. Downloads nothing.
    function move(dx: int, dy: int): void {
        const next = Wh.gridStep(currentIndex, results.count, columns, dx, dy);
        if (next < 0)
            return;
        currentIndex = next;
        grid.positionViewAtIndex(next, GridView.Contain);
    }

    // Use the picture in cell `index`: download it.
    function select(index: int): void {
        if (index < 0 || index >= results.count)
            return;
        const id = results.get(index).wallId;
        currentIndex = index;
        grid.positionViewAtIndex(index, GridView.Contain);
        if (getProc.running) {
            queued = id;
            return;
        }
        fetch(id);
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

    ListModel {
        id: results
    }

    Process {
        id: searchProc

        stdout: StdioCollector {
            id: searchOut
        }
        stderr: StdioCollector {
            id: searchErr
        }
        onExited: code => {
            if (root.restart) {
                root.restart = false;
                root.load(1);
                return;
            }
            const result = code === 0 ? Wh.parseSearch(searchOut.text) : null;
            if (!result || !result.ok) {
                const lines = searchErr.text.split("\n").filter(l => l.trim() !== "");
                root.said(lines.length > 0 ? lines[lines.length - 1].replace(/^Error: /, "") : "wallhaven search failed", true);
                return;
            }
            const first = result.page === 1;
            if (first) {
                results.clear();
                root.seen = {};
            }
            for (const item of Wh.fresh(root.seen, result.items))
                results.append({
                    wallId: item.id,
                    thumb: item.thumb,
                    caption: item.label
                });
            root.page = result.page;
            root.lastPage = result.lastPage;
            if (result.seed !== "")
                root.seed = result.seed;
            if (first) {
                root.currentIndex = results.count > 0 ? 0 : -1;
                grid.positionViewAtBeginning();
            }
            root.said(results.count === 0 ? "nothing found on wallhaven" : results.count + " of " + result.total + " · page " + result.page + " of " + result.lastPage, results.count === 0);
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
        model: results
        // Lazy paging: the next page when the view is scrolled to its end, or
        // when a page leaves it short of filling the view.
        onAtYEndChanged: if (atYEnd && root.atEnd())
            root.more()
        onCountChanged: if (root.atEnd())
            root.more()

        delegate: Picker.ImageCard {
            // Not "label": that is the card's own required property.
            required property string wallId
            required property string thumb
            required property string caption
            required property int index

            width: root.cardWidth
            path: thumb
            label: root.downloading === wallId ? "downloading…" : caption
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
