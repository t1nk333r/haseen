import QtQuick
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// The notification centre: quiet state and its switches, a screen-sharing
// snooze offer, Recent (this session), Held Back / Snoozed Sources, and the
// disk History. Open with `haseen shell ipc panel toggle haseen.pager` or the
// bar indicator.
//
// Adapted from omapager's Widget.qml panel (https://github.com/njpatel/omapager,
// MIT, Copyright (c) 2026 Neil Jagdish Patel). haseen hosts it as a `panel`
// plugin (lazy, one popup at a time); preferences live in shell.json like
// every haseen plugin, so upstream's in-panel settings view is not ported.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var service: {
        const entry = Plugins.roles.notifications;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }

    readonly property bool silenced: Flags.dnd
    readonly property int snoozeRevision: service ? service.snoozeRevision : 0
    readonly property int heldRevision: service ? service.heldRevision : 0
    readonly property int historyRevision: service ? service.historyRevision : 0
    readonly property var snoozed: {
        snoozeRevision;
        return service ? service.liveSnoozes() : [];
    }
    readonly property double globalUntil: {
        snoozeRevision;
        return service ? service.globalSnoozeUntil : 0;
    }
    readonly property bool globalSnoozed: globalUntil > 0
    readonly property bool codesLetThrough: service ? service.codesBypassQuiet : true
    readonly property bool quiet: silenced || globalSnoozed
    readonly property bool hasState: quiet || snoozed.length > 0
    readonly property bool sharingOfferPending: service ? service.sharingOfferPending : false
    readonly property var recent: {
        snoozeRevision;
        if (!service)
            return [];
        service.recentRevision;
        return service.recentForPanel(service.recentCount);
    }
    readonly property var history: {
        historyRevision;
        return service ? service.historyRows : [];
    }
    readonly property var sources: {
        snoozeRevision;
        heldRevision;
        return service ? service.quietSources(service.sourceLimit) : [];
    }
    readonly property int heldCount: sources.reduce((n, s) => n + s.held.length, 0)

    property string expandedKey: ""
    // Expanded by default: the messages are what you came for. While quiet,
    // Held Back is the subject instead.
    property bool recentExpanded: !quiet
    property bool historyExpanded: false
    property bool globalChoosing: false
    onQuietChanged: recentExpanded = !quiet

    readonly property color dim: Theme.muted
    readonly property int small: Math.max(8, Theme.fontSize - 2)
    readonly property string timeFormat: String(settings.timeFormat || "system")

    readonly property string bellOff: "\u{f009b}"
    readonly property string bellSleep: "\u{f00a0}"
    readonly property string bell: "\u{f009a}"
    readonly property string hourglass: "\u{f051f}"

    function clockTime(when) {
        if (timeFormat === "24h")
            return Qt.formatTime(when, "HH:mm");
        if (timeFormat === "12h")
            return Qt.formatTime(when, "h:mm ap");
        return when.toLocaleTimeString(Qt.locale(), Locale.ShortFormat);
    }

    // A wake time on another day carries the offset the way a flight arrival does.
    function dayOffset(when) {
        const today = new Date();
        today.setHours(0, 0, 0, 0);
        const then = new Date(when.getTime());
        then.setHours(0, 0, 0, 0);
        const days = Math.round((then.getTime() - today.getTime()) / 86400000);
        return days <= 0 ? "" : " +" + days;
    }

    function waitingFor(until) {
        const when = new Date(until * 1000);
        const left = Math.max(0, until - Date.now() / 1000);
        const minutes = Math.max(1, Math.round(left / 60));
        if (minutes < 60)
            return minutes + "m";
        if (left < 8 * 3600)
            return Math.max(1, Math.round(left / 3600)) + "h";
        return clockTime(when) + dayOffset(when);
    }

    readonly property string stateLine: {
        if (globalSnoozed) {
            const when = new Date(globalUntil * 1000);
            return "Snoozed until " + clockTime(when) + dayOffset(when);
        }
        if (silenced)
            return "Do Not Disturb on";
        if (snoozed.length === 1)
            return "1 source snoozed";
        if (snoozed.length > 1)
            return snoozed.length + " sources snoozed";
        return "Notifications enabled";
    }

    // The switch reads as "notifications are on": turning it back on undoes
    // every reason they were off.
    function letEverythingThrough() {
        Flags.set("dnd", false);
        if (service)
            service.unsnooze(service.globalKey);
    }

    width: Math.max(300, Number(settings.width) || 380)
    spacing: Theme.gap

    Component.onCompleted: {
        if (service)
            service._trimDiskHistory();
    }

    // Test hooks (settings.debugIpc): drive the panel over IPC, never by
    // injected input. Exists only while the panel is open.
    IpcHandler {
        target: "haseen.pager"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                line: root.stateLine,
                silenced: root.silenced,
                globalSnoozed: root.globalSnoozed,
                sharingOfferPending: root.sharingOfferPending,
                sources: root.sources.map(s => s.label + "=" + s.held.length),
                expanded: root.expandedKey,
                recent: root.recent.length,
                recentExpanded: root.recentExpanded,
                history: root.history.length,
                historyExpanded: root.historyExpanded,
                heldCount: root.heldCount
            });
        }

        // Open a source's held list, as clicking it would ("" closes).
        function expand(key: string): string {
            const wanted = String(key || "");
            if (!wanted) {
                root.expandedKey = "";
                return "closed";
            }
            for (const s of root.sources)
                if (s.key.indexOf(wanted) >= 0 || s.label.indexOf(wanted) >= 0) {
                    root.expandedKey = s.key;
                    return s.label;
                }
            return "no such source";
        }

        function fold(section: string, open: string): string {
            const on = open === "show";
            if (section === "recent")
                root.recentExpanded = on;
            else if (section === "history")
                root.historyExpanded = on;
            else
                return "usage: fold recent|history show|hide";
            return on ? "shown" : "hidden";
        }
    }

    // ------------------------------------------------------------- header
    Item {
        width: parent.width
        height: Math.max(heroText.implicitHeight, heroButtons.implicitHeight)

        Glyph {
            id: heroIcon

            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: root.silenced ? root.bellOff : (root.globalSnoozed || root.snoozed.length > 0) ? root.bellSleep : root.bell
            color: root.silenced ? Theme.urgent : (root.globalSnoozed || root.snoozed.length > 0) ? Theme.accent : Theme.foreground
            opacity: root.hasState ? 1 : 0.6
            font.pixelSize: Theme.fontSize + 6
        }

        Column {
            id: heroText

            anchors.left: heroIcon.right
            anchors.leftMargin: Theme.gap
            anchors.right: heroButtons.left
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: "Notifications"
                color: Theme.accent
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 2
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.service ? root.stateLine : "The notification service is not running"
                color: root.dim
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: root.small
            }
        }

        Row {
            id: heroButtons

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.service !== null

            // Whether quiet has a hole in it for verification codes: a
            // qualifier on the quiet, shown only while there is quiet.
            BarButton {
                visible: root.hasState || root.globalChoosing
                height: Theme.fontSize * 2
                glyph: root.codesLetThrough ? "\u{f0306}" : "\u{f0308}"
                color: root.codesLetThrough ? Theme.foreground : Theme.muted
                onClicked: root.service.setCodesBypassQuiet(!root.codesLetThrough)
            }

            // Snooze everything (the lengths appear below), or end it.
            BarButton {
                height: Theme.fontSize * 2
                glyph: root.globalSnoozed ? root.bell : root.bellSleep
                color: root.globalSnoozed ? Theme.accent : Theme.foreground
                highlighted: root.globalChoosing
                onClicked: {
                    if (root.globalSnoozed)
                        root.service.unsnooze(root.service.globalKey);
                    else
                        root.globalChoosing = !root.globalChoosing;
                }
            }

            // On means notifications are coming through.
            BarButton {
                height: Theme.fontSize * 2
                glyph: root.quiet ? "\u{f0522}" : "\u{f0521}"
                color: root.quiet ? Theme.muted : Theme.accent
                onClicked: root.quiet ? root.letEverythingThrough() : Flags.set("dnd", true)
            }
        }
    }

    // ------------------------------------------------------- sharing offer
    Rectangle {
        visible: root.sharingOfferPending
        width: parent.width
        height: offer.implicitHeight + Theme.gap * 2
        color: "transparent"
        radius: Theme.radius
        border.color: Theme.accent
        border.width: 1

        Column {
            id: offer

            x: Theme.gap
            y: Theme.gap
            width: parent.width - Theme.gap * 2
            spacing: 5

            Text {
                text: "Sharing detected"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                text: "Snooze notifications?"
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: root.small
            }

            Row {
                spacing: 5

                Repeater {
                    model: [
                        {
                            label: "30 min",
                            seconds: 1800
                        },
                        {
                            label: "1 hour",
                            seconds: 3600
                        },
                        {
                            label: "4 hours",
                            seconds: 14400
                        }
                    ]

                    PagerButton {
                        required property var modelData

                        text: modelData.label
                        trackHover: true
                        fontSize: root.small
                        onClicked: root.service.snoozeSharingOffer(modelData.seconds)
                    }
                }

                PagerButton {
                    text: "Not now"
                    trackHover: true
                    fontSize: root.small
                    onClicked: root.service.dismissSharingOffer()
                }
            }
        }
    }

    // ------------------------------------------------ snooze everything for
    Column {
        width: parent.width
        spacing: 5
        visible: root.globalChoosing && !root.globalSnoozed

        Text {
            visible: root.codesLetThrough
            width: parent.width
            text: "Verification-code exception enabled."
            color: root.dim
            font.family: Theme.fontFamily
            font.pixelSize: root.small
            wrapMode: Text.WordWrap
        }

        Row {
            spacing: 5

            Repeater {
                model: root.globalChoosing && root.service ? root.service.snoozeOptions : []

                PagerButton {
                    required property var modelData

                    text: String(modelData.short)
                    trackHover: true
                    fontSize: root.small
                    onClicked: {
                        root.service.snoozeSource(root.service.globalKey, "Everything", Number(modelData.seconds), true);
                        root.globalChoosing = false;
                    }
                }
            }
        }
    }

    Flickable {
        width: parent.width
        height: Math.min(sections.implicitHeight, Theme.fontSize * 44)
        contentHeight: sections.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
            id: sections

            width: parent.width
            spacing: Theme.gap

            // ------------------------------------------------------ recent
            SectionHeader {
                visible: !root.quiet
                title: "RECENT · " + root.recent.length
                folded: !root.recentExpanded
                canClear: root.recent.length > 0
                onToggled: root.recentExpanded = !root.recentExpanded
                onCleared: root.service.clearRecent()
            }

            Text {
                visible: !root.quiet && root.recentExpanded && root.recent.length === 0
                width: parent.width
                text: "No recent notifications."
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: root.small
            }

            Repeater {
                model: !root.quiet && root.recentExpanded ? root.recent : []

                // Right or middle click takes it off the stack; left opens a
                // clipped body - the card is the only place it can be read.
                TextCard {
                    required property var modelData

                    width: sections.width
                    meta: modelData.source + " · " + root.clockTime(new Date(modelData.ts * 1000))
                    summary: modelData.summary
                    bodyLine: modelData.bodyLine
                    closedLines: 2
                    openLines: 12
                    onForget: root.service.forgetRecent(modelData.key)
                }
            }

            // ------------------------------------------- held / snoozed sources
            SectionHeader {
                title: root.quiet ? "HELD BACK" : "SNOOZED SOURCES"
                foldable: false
                canClear: root.heldCount > 0
                onCleared: root.service.clearHeld()
            }

            Text {
                visible: root.sources.length === 0
                width: parent.width
                text: root.quiet ? "No held notifications." : "No snoozed sources. Middle-click a notification to snooze its source."
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: root.small
                wrapMode: Text.WordWrap
            }

            Repeater {
                model: root.sources

                Column {
                    id: line

                    required property var modelData
                    readonly property bool expanded: root.expandedKey === modelData.key
                    readonly property bool snoozedByName: modelData.until > 0
                    property bool choosing: false

                    width: sections.width
                    spacing: 2

                    Item {
                        width: parent.width
                        height: Math.max(label.implicitHeight, controls.implicitHeight)

                        Column {
                            id: label

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - controls.width - Theme.gap

                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: line.modelData.label
                                color: Theme.foreground
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: Theme.fontSize
                            }

                            // When it comes back, and what it has cost so far.
                            Text {
                                width: parent.width
                                readonly property int count: line.modelData.held.length
                                visible: line.snoozedByName || count > 0
                                textFormat: Text.PlainText
                                text: (line.snoozedByName ? root.hourglass + " " + root.waitingFor(line.modelData.until) : "") + (line.snoozedByName && count > 0 ? " · " : "") + (count > 0 ? count + " held" : "")
                                color: line.snoozedByName ? Theme.accent : root.dim
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: root.small
                            }
                        }

                        MouseArea {
                            anchors.fill: label
                            enabled: line.modelData.held.length > 0
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.expandedKey = line.expanded ? "" : line.modelData.key
                        }

                        Row {
                            id: controls

                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter

                            Repeater {
                                model: line.choosing && root.service ? root.service.snoozeOptions : []

                                PagerButton {
                                    required property var modelData

                                    anchors.verticalCenter: parent.verticalCenter
                                    text: String(modelData.short)
                                    trackHover: true
                                    fontSize: root.small
                                    // From now: four hours means four hours.
                                    onClicked: {
                                        root.service.snoozeSource(line.modelData.key, line.modelData.label, Number(modelData.seconds), true);
                                        line.choosing = false;
                                    }
                                }
                            }

                            BarButton {
                                visible: line.modelData.held.length > 0
                                height: Theme.fontSize * 2
                                glyph: line.expanded ? "\u{f0143}" : "\u{f0140}"
                                color: Theme.foreground
                                onClicked: root.expandedKey = line.expanded ? "" : line.modelData.key
                            }

                            BarButton {
                                height: Theme.fontSize * 2
                                glyph: line.choosing ? "\u2715" : "\u{f0150}"
                                color: Theme.foreground
                                onClicked: line.choosing = !line.choosing
                            }

                            BarButton {
                                visible: line.snoozedByName
                                height: Theme.fontSize * 2
                                glyph: root.bell
                                color: Theme.foreground
                                onClicked: root.service.unsnooze(line.modelData.key)
                            }
                        }
                    }

                    // What it caught: one line each, for recognising what you
                    // missed, not reading it.
                    Column {
                        visible: line.expanded
                        x: Theme.gap * 2
                        width: parent.width - Theme.gap * 2
                        spacing: 1

                        Repeater {
                            model: line.expanded ? line.modelData.held : []

                            Text {
                                required property var modelData

                                width: parent.width
                                textFormat: Text.PlainText
                                text: {
                                    const when = Qt.formatDateTime(new Date(Number(modelData.ts) * 1000), "HH:mm");
                                    const head = String(modelData.summary || "");
                                    const rest = String(modelData.bodyLine || "");
                                    return when + "  " + (head && rest ? head + " · " + rest : (head || rest));
                                }
                                color: root.dim
                                elide: Text.ElideRight
                                font.family: Theme.fontFamily
                                font.pixelSize: root.small
                            }
                        }
                    }
                }
            }

            // ----------------------------------------------------- history
            //
            // The disk log (historyHours, at most 100), newest first.
            // Verification codes are stored redacted.
            SectionHeader {
                title: "HISTORY · " + root.history.length
                folded: !root.historyExpanded
                canClear: root.history.length > 0
                onToggled: root.historyExpanded = !root.historyExpanded
                onCleared: root.service.forgetHistory()
            }

            Text {
                visible: root.historyExpanded && root.history.length === 0
                width: parent.width
                text: Number(root.settings.historyHours) === 0 ? "History is off (historyHours is 0)." : "No notification history."
                color: root.dim
                font.family: Theme.fontFamily
                font.pixelSize: root.small
            }

            // Folded instantiates nothing: up to 100 cards only while open.
            Repeater {
                model: root.historyExpanded ? root.history : []

                TextCard {
                    required property var modelData

                    width: sections.width
                    meta: String(modelData.source || modelData.app || "") + " · " + root.clockTime(new Date(Number(modelData.ts) * 1000))
                    summary: String(modelData.summary || "")
                    bodyLine: String(modelData.bodyLine || "")
                    closedLines: 2
                    openLines: 1000
                    forgettable: false
                }
            }
        }
    }

    PagerButton {
        visible: root.service !== null && (root.quiet || root.snoozed.length > 1)
        width: parent.width
        text: "Resume all notifications"
        trackHover: true
        fontSize: root.small
        onClicked: {
            root.letEverythingThrough();
            root.service.unsnoozeAll();
        }
    }
}
