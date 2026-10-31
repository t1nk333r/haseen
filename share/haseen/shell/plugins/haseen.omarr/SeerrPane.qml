import QtQuick
import qs.Haseen
import "Model.js" as Model

// The Seerr detail, under its name and status (OmarrDetail), in four tabs:
// - REQUESTS: the ones waiting for approval (approve, or decline after a
//   second click), then the answered ones page by page with their state;
// - TRENDING and UPCOMING: Seerr's discover lists, upcoming movies and
//   series as one list;
// - SEARCH: movies and series by name.
// The last three sort their page by Seerr's order, rating, name or year; a
// second click on the key shown reverses it.
// A title Seerr does not have can be requested, a series for every season it
// lacks, after a second click. A row opens the title in Seerr. Only the
// requests are polled; the other tabs ask for their page when shown.
// `panel` is the Panel that owns it, `snap` the Seerr service's snapshot.
//
// Written for haseen (plan 097, follow-up 2026-10-31), on the Omarr*
// controls adapted from omARR (MIT, Copyright (c) 2026 luccast).
Column {
    id: root

    required property var panel
    required property var snap

    readonly property var service: panel.service
    readonly property string snapId: snap ? snap.id : ""
    readonly property var pending: snap ? (snap.pending || []) : []
    readonly property int pendingTotal: snap ? (snap.pendingTotal || 0) : 0
    // The page of every request; the ones waiting show above, not again here.
    readonly property var queue: panel.detailQueueModel || []
    readonly property var answered: Model.seerrAnswered(queue)
    readonly property var pager: panel.detailPager
    readonly property var browse: service ? service.seerrBrowse : ({})
    readonly property bool browseShown: tab !== "requests" && browse.serviceId === snapId && browse.tab === tab
    readonly property var sort: service ? service.seerrSort : ({
            key: "seerr",
            ascending: false
        })
    readonly property var results: browseShown ? Model.sortSeerrResults(browse.items || [], sort.key, sort.ascending) : []
    readonly property color dim: Theme.subtle(Theme.surface)
    readonly property var tabModel: [
        {
            id: "requests",
            label: I18n.mark("REQUESTS")
        },
        {
            id: "trending",
            label: I18n.mark("TRENDING")
        },
        {
            id: "upcoming",
            label: I18n.mark("UPCOMING")
        },
        {
            id: "search",
            label: I18n.mark("SEARCH")
        }
    ]

    // The key shown carries its direction: up for A to Z, oldest or lowest
    // first.
    readonly property var sortModel: [
        {
            id: "seerr",
            label: I18n.mark("DEFAULT"),
            suffix: ""
        },
        {
            id: "rating",
            label: I18n.mark("RATING"),
            suffix: sortArrow("rating")
        },
        {
            id: "name",
            label: I18n.mark("NAME"),
            suffix: sortArrow("name")
        },
        {
            id: "year",
            label: I18n.mark("YEAR"),
            suffix: sortArrow("year")
        }
    ]

    property string tab: "requests"
    // A request's id whose decline, or a title's media key whose request,
    // waits for a second click.
    property string confirmId: ""
    property string confirmMedia: ""

    function approveRequest(id: string): void {
        confirmId = "";
        if (service)
            service.runControl(snapId, "approve-item", id);
    }

    function declineRequest(id: string): void {
        confirmMedia = "";
        if (confirmId !== id) {
            confirmId = id;
            return;
        }
        confirmId = "";
        if (service)
            service.runControl(snapId, "decline-item", id);
    }

    function requestMedia(key: string): void {
        confirmId = "";
        if (confirmMedia !== key) {
            confirmMedia = key;
            return;
        }
        confirmMedia = "";
        if (service)
            service.runControl(snapId, "request-media", key);
    }

    function sortArrow(key: string): string {
        return sort.key === key ? (sort.ascending ? " \u2191" : " \u2193") : "";
    }

    function asked(key: string): string {
        return service ? service.seerrAskedFor(snapId, key) : "";
    }

    function showTab(id: string): void {
        tab = id;
        confirmId = "";
        confirmMedia = "";
        if (id === "trending" || id === "upcoming")
            load(1);
        else if (id === "search" && searchField.text.trim() !== "")
            load(1);
    }

    function load(page: int): void {
        confirmMedia = "";
        if (service)
            service.browseSeerr(snapId, tab, tab === "search" ? searchField.text : "", page);
    }

    function search(): void {
        load(1);
        // The keys move the fleet again; a click on the field types anew.
        panel.restoreKeys();
    }

    function requestColor(item: var): color {
        return item && item.status === "failed" ? Theme.urgent : item && item.status === "available" ? Theme.success : dim;
    }

    // A request from the panel that Seerr refused or never got.
    function refused(outcome: string): bool {
        return outcome !== "" && outcome !== "sending" && outcome !== "requested" && outcome !== "nothing";
    }

    function mediaQuestion(item: var): string {
        return item && item.mediaType === "tv" ? I18n.tr("Request every season it lacks?") : I18n.tr("Request this movie?");
    }

    onSnapIdChanged: {
        tab = "requests";
        confirmId = "";
        confirmMedia = "";
    }

    spacing: Theme.gap * 2

    OmarrTabs {
        width: parent.width
        model: root.tabModel
        current: root.tab
        onPicked: id => root.showTab(id)
    }

    // ---- REQUESTS
    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.tab === "requests" && root.pending.length > 0

        OmarrSectionHeader {
            text: I18n.tr("WAITING FOR APPROVAL")
        }

        Repeater {
            model: root.tab === "requests" ? root.pending : []

            SeerrRow {
                required property var modelData

                item: modelData
                posterUrl: root.panel.seerrPosterSource(root.snapId, modelData.posterPath)
                line: Model.requestLine(modelData, I18n)
                confirming: root.confirmId !== "" && root.confirmId === modelData.id
                question: I18n.tr("Decline this request? It cannot be approved later")
                canApprove: true
                canDecline: true
                onOpened: root.panel.openCard(modelData, root.snapId)
                onApproved: root.approveRequest(modelData.id)
                onDeclined: root.declineRequest(modelData.id)
                onCancelled: root.confirmId = ""
            }
        }

        // The rest wait in Seerr, past the page size.
        Text {
            width: parent.width
            visible: root.pendingTotal > root.pending.length
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            text: I18n.tn("%1 more waiting in Seerr", "%1 more waiting in Seerr", root.pendingTotal - root.pending.length)
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
            font.italic: true
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.tab === "requests" && (root.answered.length > 0 || root.pager.hasPrev || root.pager.hasNext)

        OmarrSectionHeader {
            text: I18n.tr("RECENT")
        }

        Repeater {
            model: root.tab === "requests" ? root.answered : []

            SeerrRow {
                required property var modelData

                item: modelData
                posterUrl: root.panel.seerrPosterSource(root.snapId, modelData.posterPath)
                line: Model.requestLine(modelData, I18n)
                lineColor: root.requestColor(modelData)
                onOpened: root.panel.openCard(modelData, root.snapId)
            }
        }

        Row {
            // Spans the width, so a right-to-left panel starts it at the right.
            width: parent.width
            visible: root.pager.hasPrev || root.pager.hasNext
            spacing: Theme.gap

            // The page arrows point the way the mirrored row runs.
            OmarrButton {
                glyph: I18n.rightToLeft ? "\u{f0054}" : "\u{f004d}"
                tooltipText: I18n.tr("Previous page")
                enabled: root.pager.hasPrev
                onClicked: {
                    if (root.service)
                        root.service.turnQueuePage(root.snapId, -1);
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.pager.label
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }

            OmarrButton {
                glyph: I18n.rightToLeft ? "\u{f004d}" : "\u{f0054}"
                tooltipText: I18n.tr("Next page")
                enabled: root.pager.hasNext
                onClicked: {
                    if (root.service)
                        root.service.turnQueuePage(root.snapId, 1);
                }
            }
        }
    }

    Text {
        width: parent.width
        visible: root.tab === "requests" && root.pending.length === 0 && root.answered.length === 0 && !root.pager.hasPrev && !root.pager.hasNext
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("No requests yet.")
        color: root.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.italic: true
    }

    // ---- SEARCH: the field, Enter or the button searches.
    Item {
        width: parent.width
        height: Math.max(searchField.height, searchButton.height)
        visible: root.tab === "search"

        OmarrField {
            id: searchField

            anchors.left: parent.left
            anchors.right: searchButton.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            placeholderText: I18n.tr("Search movies and series")
            maximumLength: 100
            onAccepted: root.search()
        }

        OmarrButton {
            id: searchButton

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\u{f0349}"
            tooltipText: I18n.tr("Search")
            onClicked: root.search()
        }
    }

    // ---- TRENDING, UPCOMING and SEARCH results, in the order picked here
    Row {
        width: parent.width
        visible: root.browseShown && root.browse.state === "ok" && root.results.length > 1
        spacing: Theme.gap * 2

        Text {
            id: sortLabel

            textFormat: Text.PlainText
            text: I18n.tr("Sort by")
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }

        OmarrTabs {
            width: parent.width - sortLabel.width - parent.spacing
            model: root.sortModel
            current: root.sort.key
            onPicked: id => {
                if (root.service)
                    root.service.sortSeerr(id);
            }
        }
    }

    Text {
        width: parent.width
        visible: root.browseShown && (root.browse.state === "loading" || root.browse.state === "error")
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: root.browse.state === "loading" ? I18n.tr("Loading…") : root.browse.state === "error" ? I18n.tr("Seerr did not answer (%1)", root.browse.error === "unreachable" ? I18n.tr("Unreachable") : root.browse.error) : ""
        color: root.browse.state === "error" ? Theme.urgent : root.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.italic: true
        wrapMode: Text.WordWrap
    }

    Text {
        width: parent.width
        visible: root.browseShown && root.browse.state === "ok" && root.results.length === 0
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("Nothing found.")
        color: root.dim
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.bodySmall
        font.italic: true
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.results.length > 0

        Repeater {
            model: root.results

            SeerrRow {
                id: resultRow

                required property var modelData
                readonly property string outcome: root.asked(modelData.id)

                item: modelData
                posterUrl: root.panel.seerrPosterSource(root.snapId, modelData.posterPath)
                line: Model.seerrMediaLine(modelData, I18n, outcome)
                lineColor: root.refused(outcome) ? Theme.urgent : root.dim
                confirming: root.confirmMedia !== "" && root.confirmMedia === modelData.id
                question: root.mediaQuestion(modelData)
                // Once asked, until Seerr refused it.
                canRequest: modelData.requestable === true && (outcome === "" || root.refused(outcome))
                requestTip: modelData.mediaType === "tv" ? I18n.tr("Request every season") : I18n.tr("Request")
                onOpened: root.panel.openCard(modelData, root.snapId)
                onRequested: root.requestMedia(modelData.id)
                onCancelled: root.confirmMedia = ""
            }
        }
    }

    Row {
        width: parent.width
        visible: root.browseShown && root.browse.pages > 1
        spacing: Theme.gap

        OmarrButton {
            glyph: I18n.rightToLeft ? "\u{f0054}" : "\u{f004d}"
            tooltipText: I18n.tr("Previous page")
            enabled: root.browse.page > 1 && root.browse.state !== "loading"
            onClicked: root.load(root.browse.page - 1)
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: I18n.tr("Page %1 of %2", root.browse.page, root.browse.pages)
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }

        OmarrButton {
            glyph: I18n.rightToLeft ? "\u{f004d}" : "\u{f0054}"
            tooltipText: I18n.tr("Next page")
            enabled: root.browse.page < root.browse.pages && root.browse.state !== "loading"
            onClicked: root.load(root.browse.page + 1)
        }
    }
}
