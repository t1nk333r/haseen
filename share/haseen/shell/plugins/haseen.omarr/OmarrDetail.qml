import QtQuick
import qs.Haseen
import "Model.js" as Model

// One service's detail, beside the fleet: its name, status and a button to
// open it. A media server (Jellyfin) shows what is playing, on deck and
// recently added; the others their queue page by page, with pause and resume
// on a downloader's rows, SABnzbd its history, and Sonarr or Radarr their
// calendar. `panel` is the Panel that owns it.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: its own file, theme tokens, Omarr* controls.
Column {
    id: root

    required property var panel

    readonly property var service: panel.service
    readonly property var snap: panel.detailSnap
    readonly property string snapId: snap ? snap.id : ""
    readonly property bool media: !!snap && Model.isMediaKind(snap.kind)
    readonly property bool downloader: !!snap && (snap.kind === "sabnzbd" || snap.kind === "qbittorrent")
    readonly property var queue: !snap || media ? [] : (panel.detailQueueModel || [])
    readonly property var pager: panel.detailPager
    readonly property var sessions: media ? (snap.sessions || []) : []
    readonly property var onDeck: media ? (snap.onDeck || []) : []
    readonly property var recent: media ? (snap.recent || []) : []
    readonly property var history: snap && snap.kind === "sabnzbd" ? (snap.activity || []) : []
    readonly property var calendarGroups: snap && !media && snap.calendar && snap.calendar.length > 0 ? Model.groupedCalendar(snap.calendar) : []
    readonly property color dim: Theme.subtle(Theme.surface)

    spacing: Theme.gap * 2.5

    Column {
        width: parent.width
        spacing: Theme.gap

        Item {
            width: parent.width
            height: Math.max(detailTitle.implicitHeight, openButton.height, detailIcon.height)

            ServiceIcon {
                id: detailIcon

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                service: root.snap || ({})
                health: root.snap ? (root.snap.health || "") : ""
                healthColor: root.panel.healthColor(root.snap ? root.snap.health : "")
            }

            OmarrSectionHeader {
                id: detailTitle

                anchors.left: detailIcon.right
                anchors.leftMargin: Theme.gap
                anchors.right: openButton.left
                anchors.rightMargin: Theme.gap
                anchors.verticalCenter: parent.verticalCenter
                text: root.snap ? String(root.snap.name).toUpperCase() : ""
                color: Theme.foreground
            }

            OmarrButton {
                id: openButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "\u{f059f}"
                tooltipText: "Open in browser"
                tooltipBelow: true
                onClicked: root.panel.openService(root.snapId)
            }
        }

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.snap ? (root.snap.statusText || Model.fleetLine(root.snap)) : ""
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
            wrapMode: Text.WordWrap
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.sessions.length > 0

        OmarrSectionHeader {
            text: "NOW PLAYING"
        }

        Repeater {
            model: root.sessions

            OmarrMediaRow {
                required property var modelData

                title: modelData.title || ""
                subtitle: modelData.subtitle || ""
                progress: modelData.progress || 0
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.onDeck.length > 0

        OmarrSectionHeader {
            text: "ON DECK"
        }

        Repeater {
            model: root.onDeck

            CalendarCard {
                required property var modelData

                item: modelData
                posterUrl: root.panel.mediaSource(root.snapId, modelData.id)
                fanartUrl: posterUrl
                onClicked: root.panel.openCard(modelData, root.snapId)
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.recent.length > 0

        OmarrSectionHeader {
            text: "RECENTLY ADDED"
        }

        Repeater {
            model: root.recent

            CalendarCard {
                required property var modelData

                item: modelData
                posterUrl: root.panel.mediaSource(root.snapId, modelData.id)
                fanartUrl: posterUrl
                onClicked: root.panel.openCard(modelData, root.snapId)
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: !!root.snap && !root.media && (root.queue.length > 0 || root.pager.hasPrev || root.pager.hasNext)

        Repeater {
            model: root.queue

            OmarrRow {
                id: queueRow

                required property var modelData

                width: parent.width
                implicitHeight: queueCol.implicitHeight + Theme.gap * 1.5
                hasCursor: queueMouse.containsMouse

                MouseArea {
                    id: queueMouse

                    anchors.fill: parent
                    hoverEnabled: true
                }

                Row {
                    anchors.fill: parent
                    anchors.margins: Math.round(Theme.gap * 0.75)
                    spacing: Theme.gap

                    OmarrMediaRow {
                        id: queueCol

                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - (root.downloader ? queueActions.width + parent.spacing : 0)
                        title: queueRow.modelData.title || ""
                        subtitle: Model.queueLine(queueRow.modelData)
                        subtitleColor: queueRow.modelData.status === "warning" || queueRow.modelData.status === "error" ? Theme.urgent : root.dim
                        progress: queueRow.modelData.progress || 0
                    }

                    Row {
                        id: queueActions

                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.downloader
                        spacing: 2

                        OmarrButton {
                            glyph: "\u{f03e4}"
                            tooltipText: "Pause"
                            onClicked: {
                                if (root.service)
                                    root.service.runControl(root.snapId, "pause-item", queueRow.modelData.id);
                            }
                        }

                        OmarrButton {
                            glyph: "\u{f040a}"
                            tooltipText: "Resume"
                            onClicked: {
                                if (root.service)
                                    root.service.runControl(root.snapId, "resume-item", queueRow.modelData.id);
                            }
                        }
                    }
                }
            }
        }

        Row {
            visible: root.pager.hasPrev || root.pager.hasNext
            spacing: Theme.gap

            OmarrButton {
                glyph: "\u{f004d}"
                tooltipText: "Previous page"
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
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
            }

            OmarrButton {
                glyph: "\u{f0054}"
                tooltipText: "Next page"
                enabled: root.pager.hasNext
                onClicked: {
                    if (root.service)
                        root.service.turnQueuePage(root.snapId, 1);
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.history.length > 0

        OmarrSectionHeader {
            text: "HISTORY"
        }

        Repeater {
            model: root.history

            Column {
                id: historyRow

                required property var modelData

                width: parent.width
                spacing: 1

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: historyRow.modelData.title || ""
                    color: Theme.foreground
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: historyRow.modelData.status || ""
                    color: historyRow.modelData.status === "failed" ? Theme.urgent : root.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    elide: Text.ElideRight
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.calendarGroups.length > 0

        Repeater {
            model: root.calendarGroups

            Column {
                id: day

                required property var modelData

                width: parent.width
                spacing: Theme.gap

                Text {
                    visible: day.modelData.heading !== ""
                    width: parent.width
                    textFormat: Text.PlainText
                    text: day.modelData.heading
                    color: root.dim
                    font.family: Theme.fontFamily
                    font.pixelSize: Math.max(1, Theme.fontSize - 1)
                    font.bold: true
                }

                Repeater {
                    model: day.modelData.items

                    CalendarCard {
                        required property var modelData

                        item: modelData
                        posterUrl: root.panel.posterSource(root.snapId, modelData.posterId)
                        fanartUrl: root.panel.fanartSource(root.snapId, modelData.posterId)
                        onClicked: root.panel.openCard(modelData, root.snapId)
                    }
                }
            }
        }
    }
}
