import QtQuick
import qs.Haseen
import "Model.js" as Model

// The panel's overview, beside the fleet while no service is selected:
// services that are down, the downloads of services that show their queue
// (with a quiet-queue line), what is playing, then the ON DECK / RECENTLY
// ADDED / CALENDAR tabs of media cards. `panel` is the Panel that owns it.
//
// Adapted from Panel.qml in omARR (MIT, Copyright (c) 2026 luccast), as the
// owner's fork t1nk33r.omarr 1.0.0; see LICENSE and UPSTREAM.md beside this
// file. haseen changes: its own file, theme tokens, Omarr* controls.
Column {
    id: root

    required property var panel

    readonly property var service: panel.service
    readonly property var nowFeed: panel.nowFeed
    readonly property var downloads: nowFeed.downloads || []
    readonly property var sessions: nowFeed.sessions || []
    readonly property var warnings: nowFeed.warnings || []
    readonly property string tab: panel.shownHomeTab
    readonly property var onDeck: service && service.onDeckFeed ? service.onDeckFeed : []
    readonly property var recent: service && service.recentFeed ? service.recentFeed : []
    readonly property var calendar: service && service.calendarFeed ? service.calendarFeed : []
    readonly property color dim: Theme.subtle(Theme.surface)

    spacing: Theme.gap * 2.5

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.warnings.length > 0

        OmarrSectionHeader {
            text: I18n.tr("WARNINGS")
            color: Theme.urgent
        }

        Repeater {
            model: root.warnings

            Text {
                required property var modelData

                width: parent.width
                textFormat: Text.PlainText
                // Set rather than implicit: a right-to-left panel then aligns
                // Latin text and numbers to the right too (plan 109).
                horizontalAlignment: Text.AlignLeft
                text: modelData.title + " · " + Model.statusLabel(modelData.body, I18n)
                color: Theme.urgent
                font.family: Theme.fontFamily
                font.pixelSize: Math.max(1, Theme.fontSize - 1)
                wrapMode: Text.WordWrap
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.nowFeed.showQueue === true && root.downloads.length > 0

        OmarrSectionHeader {
            text: I18n.tr("DOWNLOADING")
        }

        Repeater {
            model: root.nowFeed.showQueue ? root.downloads : []

            OmarrMediaRow {
                required property var modelData

                title: modelData.title || ""
                subtitle: {
                    const line = Model.queueLine(modelData, I18n);
                    return (modelData.serviceName || "") + " · " + Model.formatProgress(modelData.progress) + (line ? " · " + line : "");
                }
                subtitleColor: modelData.status === "warning" || modelData.status === "error" ? Theme.urgent : root.dim
                progress: modelData.progress || 0
            }
        }
    }

    Text {
        visible: root.nowFeed.showQueue === true && root.downloads.length === 0 && root.sessions.length === 0
        width: parent.width
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignLeft
        text: I18n.tr("Queue is quiet.")
        color: root.dim
        font.family: Theme.fontFamily
        font.pixelSize: Math.max(1, Theme.fontSize - 1)
        font.italic: true
    }

    Column {
        width: parent.width
        spacing: Theme.gap
        visible: root.sessions.length > 0

        OmarrSectionHeader {
            text: I18n.tr("NOW PLAYING")
        }

        Repeater {
            model: root.sessions

            OmarrMediaRow {
                required property var modelData

                title: modelData.title || ""
                subtitle: Model.sessionSubtitle(modelData.subtitle, I18n)
                progress: modelData.progress || 0
                // A playback position: time runs left to right.
                playback: true
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.gap

        OmarrTabs {
            width: parent.width
            model: root.panel.homeTabModel
            current: root.tab
            onPicked: id => root.panel.homeTab = id
        }

        Repeater {
            model: root.tab === "ondeck" ? root.onDeck : root.tab === "recent" ? root.recent : []

            CalendarCard {
                required property var modelData

                item: modelData
                posterUrl: root.panel.mediaSource(modelData.serviceId, modelData.posterId)
                fanartUrl: posterUrl
                onClicked: root.panel.openCard(modelData, "")
            }
        }

        Repeater {
            model: root.tab === "calendar" ? root.panel.calendarGroups : []

            Column {
                id: day

                required property var modelData

                width: parent.width
                spacing: Theme.gap

                Text {
                    visible: day.modelData.heading !== ""
                    width: parent.width
                    textFormat: Text.PlainText
                    horizontalAlignment: Text.AlignLeft
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
                        posterUrl: root.panel.posterSource(modelData.serviceId, modelData.posterId)
                        fanartUrl: root.panel.fanartSource(modelData.serviceId, modelData.posterId)
                        onClicked: root.panel.openCard(modelData, "")
                    }
                }
            }
        }

        Text {
            visible: (root.tab === "ondeck" && root.onDeck.length === 0) || (root.tab === "recent" && root.recent.length === 0) || (root.tab === "calendar" && root.calendar.length === 0)
            width: parent.width
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignLeft
            text: root.tab === "recent" ? I18n.tr("Nothing recently added.") : root.tab === "calendar" ? I18n.tr("Calendar is empty.") : I18n.tr("Nothing on deck.")
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: Math.max(1, Theme.fontSize - 1)
            font.italic: true
        }
    }
}
