import QtQuick
import qs.Haseen

import "Markup.js" as Markup
import "Security.js" as Security

// One notification card, in every state it has.
//
// Adapted from omapager (https://github.com/njpatel/omapager), MIT,
// Copyright (c) 2026 Neil Jagdish Patel. haseen changes: Theme tokens instead
// of Omarchy's Style/Color/Border kit, no MultiEffect masks (no shaders), and
// a single-shot expiry timer instead of a 100 ms ticker.
//
// The card never decides where it goes - Layout.js does that and the scene
// hands it a placement. What the card owns is how long it lives and what is
// inside its own edges.
Item {
    id: card

    property real fontScale: 1
    property bool showCountdown: false
    property var row: ({})
    // Image URLs to try for the source icon, best first (Service.iconsFor).
    property var icons: []
    property int iconRevision: 0
    property var place: ({
            y: 0,
            scale: 1,
            opacity: 1,
            z: 1,
            front: true,
            hidden: false
        })
    property var scene: null
    property bool expanded: false
    property bool sole: false                  // the only card on screen
    property int bulkCount: 0
    property bool paused: false
    property bool hovered: false
    property double now: Date.now()
    property real cardWidth: 380

    signal expired
    signal activated
    signal dismissed
    signal dismissAllRequested
    signal snoozeRequested(int seconds)
    signal silenceRequested
    signal offerTaken(string kind, string value)
    signal actionInvoked(string identifier)
    signal replyRequested
    signal replySent(string text)
    signal replyCancelled

    // "now" for the first minute, then minutes, then the clock time, then
    // the day.
    function ago() {
        const ts = Number(row.ts || 0) * 1000;
        if (!ts)
            return "";
        const s = Math.max(0, (now - ts) / 1000);
        if (s < 50)
            return "now";
        if (s < 3600)
            return Math.round(s / 60) + "m";
        const then = new Date(ts);
        if (new Date(now).toDateString() === then.toDateString())
            return Qt.formatDateTime(then, "HH:mm");
        if (new Date(now - 86400000).toDateString() === then.toDateString())
            return "yesterday";
        return Qt.formatDateTime(then, "ddd");
    }

    readonly property int fade: 150
    readonly property bool critical: row.urgency === 2
    readonly property color dimColor: Theme.muted
    readonly property color bodyColor: Theme.foreground
    readonly property color accentColor: critical ? Theme.urgent : (row.urgency === 0 ? Theme.muted : Theme.accent)
    readonly property int titleSize: Math.round((Theme.fontSize + 1) * fontScale)
    readonly property int bodySize: Math.round(Theme.fontSize * fontScale)
    readonly property int captionSize: Math.round(Math.max(8, Theme.fontSize - 2) * fontScale)
    readonly property bool hasBody: String(row.body || "").length > 0
    readonly property real contentPaddingY: hasBody ? 10 : 7
    // A card behind the front one in a collapsed deck is a shape, not a message.
    readonly property bool showsContent: expanded || place.front === true
    // Two lines while scanning; the body opens when the deck is open, or on
    // hover when this is the only card.
    readonly property bool bodyOpen: expanded || (hovered && sole)
    readonly property int bodyLines: bodyOpen ? 8 : 2
    readonly property int stands: place.count || 1

    readonly property var foundCodes: String(row.codes || row.code || "").split(" ").filter(c => !!c)

    // Everything this card can do, spelled out: what it found in its own text
    // first, then what the sender said it supports.
    readonly property var allDeeds: {
        const out = [];
        for (const c of foundCodes)
            out.push({
                kind: "code",
                value: c,
                label: foundCodes.length > 1 ? ("Copy " + c) : "Copy code"
            });
        if (String(row.link || ""))
            out.push({
                kind: row.meeting ? "meeting" : "link",
                label: row.meeting ? "Join" : "Open link",
                value: String(row.link)
            });
        if (String(row.phone || ""))
            out.push({
                kind: "phone",
                label: "Copy number",
                value: String(row.phone)
            });
        if (String(row.replyPath || ""))
            out.push({
                kind: "reply",
                label: "Reply",
                value: ""
            });
        for (const a of actions) {
            // The phone's own "Reply" opens a window elsewhere; ours types here.
            if (String(row.replyPath || "") && /^reply$/i.test(String(a.text || "")))
                continue;
            out.push({
                kind: "action",
                label: String(a.text || ""),
                value: String(a.id)
            });
        }
        return out;
    }

    // Marks on the headline say "there is something here" without costing
    // height: a key, a link, a phone, a cursor for sender actions.
    readonly property var marks: {
        const out = [];
        if (String(row.code || ""))
            out.push("\u{f0306}");
        if (String(row.link || ""))
            out.push(row.meeting ? "\u{f0567}" : "\u{f0339}");
        if (String(row.phone || ""))
            out.push("\u{f03f2}");
        if (actions.length > 0)
            out.push("\u{f0cfd}");
        return out;
    }

    // Measure the real buttons: reserve More before admitting each action.
    readonly property var actionWidths: {
        const widths = [];
        for (let i = 0; i < deedMeasures.count; i++) {
            const button = deedMeasures.itemAt(i);
            if (button)
                widths.push(button.implicitWidth);
        }
        return widths;
    }
    readonly property int fits: {
        const widths = actionWidths;
        const gap = deedRow.spacing;
        const available = deedArea.width;
        if (widths.length !== allDeeds.length)
            return 0;
        let total = 0;
        for (let i = 0; i < widths.length; i++)
            total += widths[i] + (i ? gap : 0);
        if (total <= available)
            return widths.length;
        let used = moreMeasure.implicitWidth;
        let count = 0;
        for (const w of widths) {
            if (used + gap + w > available)
                break;
            used += gap + w;
            count++;
        }
        return count;
    }
    readonly property var deeds: allDeeds.slice(0, fits)
    readonly property var spare: allDeeds.slice(fits)

    property bool deedsOpen: false
    property bool menuOpen: false
    property string actionsAlign: "right"
    property var snoozeOptions: []

    // Middle-click asks about the source rather than the message.
    readonly property var menuDeeds: {
        const out = snoozeOptions.map(o => ({
                    kind: "snooze",
                    label: String(o.menuLabel),
                    value: Number(o.seconds)
                }));
        out.push({
            kind: "silence",
            label: "Enable Do Not Disturb",
            value: 0
        });
        return out;
    }

    // The pointer, in the deck's coordinates, converted to the card's.
    property real hoverX: -1
    property real hoverY: -1
    readonly property real localHoverX: hoverX - x
    readonly property real localHoverY: hoverY - y

    property var actions: []
    property string replyError: ""
    property bool replying: false

    function doDeed(deed) {
        const kind = String(deed.kind || "");
        if (kind === "more") {
            deedsOpen = !deedsOpen;
            return;
        }
        if (kind === "snooze") {
            menuOpen = false;
            snoozeRequested(Number(deed.value));
            return;
        }
        if (kind === "silence") {
            menuOpen = false;
            silenceRequested();
            return;
        }
        if (kind === "reply") {
            menuOpen = false;
            replyRequested();
            return;
        }
        if (kind === "action") {
            actionInvoked(String(deed.value));
            return;
        }
        offerTaken(kind, String(deed.value));
        takenKind = kind + ":" + String(deed.value);
        tick.restart();
    }

    function hoverOn(item) {
        if (!hovered)
            return false;
        const origin = item.mapToItem(card, 0, 0);
        return localHoverX >= origin.x && localHoverX <= origin.x + item.width && localHoverY >= origin.y && localHoverY <= origin.y + item.height;
    }

    // Which one was just pressed, so its label can say so for a moment.
    property string takenKind: ""

    // haseen:ui-timeout
    Timer {
        id: tick

        interval: 1400
        repeat: false
        onTriggered: card.takenKind = ""
    }

    // ------------------------------------------------------------- expiry
    //
    // One single-shot timer for the time left. Pausing banks what has run, so
    // a card you stopped to read keeps the seconds you spent reading it.
    readonly property int duration: Number(row.duration || 0)
    property real remaining: duration
    property double _since: 0
    readonly property bool ticking: duration > 0 && !paused && !replying

    function _bank() {
        if (_since > 0)
            remaining = Math.max(0, remaining - (Date.now() - _since));
        _since = ticking ? Date.now() : 0;
    }

    onTickingChanged: _bank()
    onDurationChanged: {
        remaining = duration;
        _since = ticking ? Date.now() : 0;
        if (expiry.running)
            expiry.restart();
    }
    Component.onCompleted: _since = ticking ? Date.now() : 0

    // haseen:ui-timeout
    Timer {
        id: expiry

        interval: Math.max(1, card.remaining)
        repeat: false
        running: card.ticking && card.remaining > 0
        onTriggered: card.expired()
    }

    // The optional countdown line, animated only while it is shown.
    property real countdown: 1

    NumberAnimation {
        target: card
        property: "countdown"
        running: card.showCountdown && card.ticking && card.remaining > 0
        from: card.remaining / Math.max(1, card.duration)
        to: 0
        duration: Math.max(1, card.remaining)
    }

    width: cardWidth
    height: body.height

    // ---------------------------------------------------- what the scene reads
    readonly property real textBlock: headline.height + (hasBody ? column.spacing + bodyBox.height : 0)
    readonly property real restingBlock: headline.height + (hasBody ? column.spacing + bodyBox.restHeight : 0)
    readonly property real fixedHeight: plate.border.width * 2 + contentPaddingY * 2 + Math.max(thumb.height, textBlock)
    // The height this card's *state* implies; the deck lays out from this.
    readonly property real targetHeight: fixedHeight + deedArea.wanted
    // And the height the scene says it is right now, on the way there.
    property real drawnHeight: targetHeight

    onHoveredChanged: {
        if (!hovered)
            menuOpen = false;
    }
    onExpandedChanged: {
        if (!expanded)
            menuOpen = false;
    }

    // Position, size and opacity all come from the scene clock.
    y: scene ? scene.at(row.key, "y") : 0
    z: place.z
    scale: scene ? scene.at(row.key, "scale") : 1
    opacity: place.hidden ? 0 : (scene ? scene.at(row.key, "opacity") : 1)
    transformOrigin: Item.Top
    // `visible` is deliberately not bound: anything the layout produces is the
    // wrong side of that fence (binding loops). `enabled` refuses the pointer.
    enabled: !place.hidden

    Rectangle {
        id: plate

        width: body.width
        height: body.height
        radius: Theme.radius
        color: Theme.surface
        border.color: card.critical ? Theme.urgent : Theme.border
        border.width: Math.max(1, Theme.borderWidth)
    }

    Item {
        id: body

        width: parent.width
        height: card.drawnHeight

        Row {
            id: layoutRow

            // Anchored to the top: a card grows downwards when its buttons or
            // reply field appear, and the words must not move.
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: plate.border.width + 12
            anchors.rightMargin: plate.border.width + 12
            anchors.topMargin: plate.border.width + card.contentPaddingY
            spacing: 12

            // Every notification gets a mark: the sender's image, else the
            // resolved icon, else the first letter of its source.
            Item {
                id: thumb

                // The sender's picture wins while it works (a contact photo
                // beats any app icon); then the resolved candidates in order.
                readonly property var candidates: {
                    const out = [];
                    const sent = String(card.row.image || "");
                    if (/^image:\/\/qsimage\/[0-9]+\/[0-9]+$/.test(sent) || sent.indexOf("image://icon//") === 0)
                        out.push(sent);
                    return out.concat(card.icons || []);
                }
                property int pick: 0

                width: 40
                height: width
                y: Math.max(0, (card.restingBlock - height) / 2)
                opacity: card.showsContent ? 1 : 0
                onCandidatesChanged: pick = 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: card.fade
                    }
                }

                Connections {
                    target: card
                    function onIconRevisionChanged() {
                        thumb.pick = 0;
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    radius: Theme.radius
                    visible: picture.status !== Image.Ready
                    color: Theme.surfaceAlt
                    border.color: card.accentColor
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        textFormat: Text.PlainText
                        text: String(card.row.source || card.row.app || "?").substring(0, 1).toUpperCase()
                        color: card.dimColor
                        font.family: Theme.fontFamily
                        font.pixelSize: card.bodySize
                        font.weight: Font.DemiBold
                    }
                }

                Image {
                    id: picture

                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: thumb.pick < thumb.candidates.length ? thumb.candidates[thumb.pick] : ""
                    // A file or handle that will not draw: try the next one.
                    onStatusChanged: {
                        if (status === Image.Error && thumb.pick < thumb.candidates.length)
                            thumb.pick += 1;
                    }
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    cache: true
                    sourceSize.width: 80
                    sourceSize.height: 80
                }
            }

            Column {
                id: column

                width: layoutRow.width - thumb.width - layoutRow.spacing
                spacing: 3

                // Title, how many this one stands for, when it arrived.
                Item {
                    id: headline

                    width: parent.width
                    height: Math.max(title.implicitHeight, rightSide.height, badge.visible ? badge.height : 0)
                    opacity: card.showsContent ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: card.fade
                        }
                    }

                    Text {
                        id: title

                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(1, parent.width - rightSide.width - (badge.visible ? badge.width + 6 : 0) - (titleMarks.visible ? titleMarks.width + 7 : 0) - 8)
                        textFormat: Text.PlainText
                        text: String(card.row.summary || "")
                        color: card.critical ? Theme.urgent : Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: card.titleSize
                        font.bold: true
                        wrapMode: Text.Wrap
                        maximumLineCount: card.bodyOpen ? 8 : 3
                        elide: Text.ElideRight
                    }

                    Row {
                        id: titleMarks

                        visible: card.marks.length > 0
                        anchors.verticalCenter: title.verticalCenter
                        x: title.x + Math.min(title.implicitWidth, title.width) + 7
                        spacing: 5

                        Repeater {
                            model: card.marks

                            Text {
                                required property var modelData

                                textFormat: Text.PlainText
                                text: modelData
                                color: Theme.foreground
                                font.family: Theme.fontMono
                                font.pixelSize: card.bodySize
                            }
                        }
                    }

                    Rectangle {
                        id: badge

                        anchors.right: rightSide.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: title.verticalCenter
                        visible: card.stands > 1
                        width: badgeText.implicitWidth + 10
                        height: badgeText.implicitHeight + 2
                        radius: Theme.radius
                        color: Theme.surfaceAlt
                        border.color: card.accentColor
                        border.width: 1

                        Text {
                            id: badgeText

                            anchors.centerIn: parent
                            textFormat: Text.PlainText
                            text: String(card.stands)
                            color: card.dimColor
                            font.family: Theme.fontFamily
                            font.pixelSize: card.captionSize
                        }
                    }

                    // Timestamp and the close control share one slot, so hover
                    // crossfades between them without moving the headline.
                    Row {
                        id: rightSide

                        anchors.right: parent.right
                        anchors.verticalCenter: title.verticalCenter
                        spacing: 5

                        PagerButton {
                            id: clearAll

                            visible: card.bulkCount > 1
                            enabled: visible
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Clear all " + card.bulkCount
                            horizontalPadding: 4
                            verticalPadding: 2
                            fontSize: card.captionSize
                            hot: card.hoverOn(clearAll)
                            onClicked: card.dismissAllRequested()
                            onRightClicked: card.dismissed()
                        }

                        Item {
                            width: Math.max(stamp.implicitWidth, shut.implicitWidth)
                            height: Math.max(stamp.implicitHeight, shut.implicitHeight)
                            anchors.verticalCenter: parent.verticalCenter

                            Text {
                                id: stamp

                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: card.ago()
                                color: card.dimColor
                                opacity: card.hovered ? 0 : 1
                                visible: opacity > 0.01
                                font.family: Theme.fontFamily
                                font.pixelSize: card.captionSize

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: card.fade
                                    }
                                }
                            }

                            PagerButton {
                                id: shut

                                anchors.centerIn: parent
                                text: "\u2715"
                                horizontalPadding: 4
                                verticalPadding: 2
                                implicitWidth: implicitHeight
                                fontSize: card.captionSize
                                hot: card.hoverOn(shut)
                                enabled: card.hovered
                                opacity: card.hovered ? 1 : 0
                                visible: opacity > 0.01
                                onClicked: card.dismissed()
                                onRightClicked: card.menuOpen = !card.menuOpen

                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: card.fade
                                    }
                                }
                            }
                        }
                    }
                }

                FontMetrics {
                    id: metrics

                    font.family: Theme.fontFamily
                    font.pixelSize: card.bodySize
                }

                // Rich text cannot elide, so a body beyond the current line cap
                // is flattened into the plain rendering that can.
                Item {
                    id: bodyBox

                    readonly property real lineH: Math.max(1, metrics.height)
                    readonly property real cap: lineH * card.bodyLines
                    readonly property bool overflow: rich.contentHeight > cap + lineH * 0.4
                    readonly property real shown: overflow ? plain.contentHeight : rich.contentHeight
                    readonly property real restHeight: Math.min(Math.ceil(lineH * 2), Math.ceil(rich.contentHeight))

                    clip: true
                    width: parent.width
                    height: Math.ceil(shown)
                    visible: card.hasBody
                    opacity: card.showsContent ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: card.fade
                        }
                    }

                    Text {
                        id: rich

                        width: parent.width
                        visible: !bodyBox.overflow
                        textFormat: Text.RichText
                        text: Markup.colourLinks(String(card.row.bodyRich || ""), String(Theme.accent))
                        color: card.bodyColor
                        font.family: Theme.fontFamily
                        font.pixelSize: card.bodySize
                        wrapMode: Text.Wrap
                        // Second gate on the same rule as Markup.js.
                        onLinkActivated: url => Security.openExternalUrl(url)
                    }

                    Text {
                        id: plain

                        width: parent.width
                        visible: bodyBox.overflow
                        textFormat: Text.PlainText
                        text: String(card.row.bodyLine || "")
                        color: card.bodyColor
                        font.family: Theme.fontFamily
                        font.pixelSize: card.bodySize
                        wrapMode: Text.Wrap
                        maximumLineCount: card.bodyLines
                        elide: Text.ElideRight
                    }
                }

                // The space under the body does one job at a time: the action
                // row (under the pointer in an open deck), the More list, the
                // middle-click menu, or the reply field.
                Item {
                    id: deedArea

                    readonly property string mode: card.replying ? "reply" : card.menuOpen ? "menu" : card.deedsOpen ? "list" : (card.hovered && card.expanded && card.allDeeds.length > 0) ? "row" : ""
                    readonly property real contentHeight: mode === "reply" ? replyBox.height : mode === "menu" ? menuColumn.implicitHeight : mode === "list" ? deedColumn.implicitHeight : mode === "row" ? deedRow.implicitHeight : 0
                    readonly property real wanted: mode === "" ? 0 : contentHeight + 7

                    width: parent.width
                    height: Math.max(0, card.drawnHeight - card.fixedHeight)
                    visible: height > 0
                    clip: true

                    // Measured offscreen so `fits` knows the real widths.
                    Item {
                        visible: false

                        Repeater {
                            id: deedMeasures

                            model: card.allDeeds

                            DeedButton {
                                required property var modelData

                                deed: modelData
                                toast: card
                            }
                        }

                        DeedButton {
                            id: moreMeasure

                            deed: ({
                                    kind: "more",
                                    label: "More",
                                    value: ""
                                })
                            toast: card
                        }
                    }

                    Row {
                        id: deedRow

                        anchors.bottom: parent.bottom
                        anchors.right: card.actionsAlign === "right" ? parent.right : undefined
                        anchors.left: card.actionsAlign === "right" ? undefined : parent.left
                        spacing: 6
                        opacity: deedArea.mode === "row" ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: card.fade
                            }
                        }

                        Repeater {
                            model: card.deeds

                            DeedButton {
                                required property var modelData

                                deed: modelData
                                toast: card
                            }
                        }

                        DeedButton {
                            visible: card.spare.length > 0
                            deed: ({
                                    kind: "more",
                                    label: "More",
                                    value: ""
                                })
                            toast: card
                        }
                    }

                    // Typing an answer, in the card the message arrived in.
                    Item {
                        id: replyBox

                        width: parent.width
                        height: card.replying ? replyField.implicitHeight + 3 : 0
                        visible: height > 0
                        anchors.bottom: parent.bottom
                        clip: true
                        onVisibleChanged: {
                            if (visible)
                                replyInput.forceActiveFocus();
                        }

                        Rectangle {
                            id: replyField

                            anchors.fill: parent
                            anchors.topMargin: 3
                            implicitHeight: replyInput.implicitHeight + 10
                            radius: Theme.radius
                            color: Theme.background
                            border.color: replyInput.activeFocus ? Theme.accent : Theme.border
                            border.width: 1

                            Text {
                                anchors.fill: replyInput
                                visible: replyInput.text.length === 0
                                textFormat: Text.PlainText
                                text: card.replyError || ("Reply to " + String(card.row.replyTo || card.row.summary || ""))
                                color: card.replyError ? Theme.urgent : Theme.muted
                                font: replyInput.font
                                elide: Text.ElideRight
                            }

                            TextInput {
                                id: replyInput

                                // Trailing edge is left for right-to-left text.
                                readonly property bool isRtl: {
                                    const t = text;
                                    for (let i = 0; i < t.length;) {
                                        const c = t.codePointAt(i);
                                        i += c > 0xFFFF ? 2 : 1;
                                        if (c <= 0x7F && !(c >= 0x41 && c <= 0x5A) && !(c >= 0x61 && c <= 0x7A))
                                            continue;
                                        if (c <= 0x024F)
                                            return false;
                                        if ((c >= 0x0590 && c <= 0x08FF) || (c >= 0xFB50 && c <= 0xFDFF) || (c >= 0xFE70 && c <= 0xFEFF))
                                            return true;
                                        return false;
                                    }
                                    return false;
                                }

                                anchors.verticalCenter: parent.verticalCenter
                                x: 8 + (sendButton.visible && isRtl ? sendButton.width + 6 : 0)
                                width: parent.width - 16 - (sendButton.visible ? sendButton.width + 6 : 0)
                                color: Theme.foreground
                                selectionColor: Theme.selection
                                font.family: Theme.fontFamily
                                font.pixelSize: card.bodySize
                                clip: true
                                onAccepted: {
                                    card.replySent(text);
                                    text = "";
                                }
                                Keys.onEscapePressed: {
                                    text = "";
                                    card.replyCancelled();
                                }
                            }

                            PagerButton {
                                id: sendButton

                                x: replyInput.isRtl ? 4 : parent.width - width - 4
                                anchors.verticalCenter: parent.verticalCenter
                                visible: replyInput.text.length > 0
                                text: "Send"
                                bordered: false
                                trackHover: true
                                fontSize: card.bodySize
                                onClicked: {
                                    card.replySent(replyInput.text);
                                    replyInput.text = "";
                                }
                            }
                        }
                    }

                    Column {
                        id: deedColumn

                        anchors.bottom: parent.bottom
                        width: parent.width
                        spacing: 4
                        opacity: deedArea.mode === "list" ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: card.fade
                            }
                        }

                        Repeater {
                            model: card.deedsOpen ? card.allDeeds : []

                            DeedButton {
                                required property var modelData

                                deed: modelData
                                toast: card
                                wide: true
                            }
                        }
                    }

                    // Middle-click: what to do about this sender. Drawn in the
                    // card, not as a popup: the surface is clipped.
                    Column {
                        id: menuColumn

                        anchors.bottom: parent.bottom
                        width: parent.width
                        spacing: 4
                        opacity: deedArea.mode === "menu" ? 1 : 0
                        visible: opacity > 0.01

                        Behavior on opacity {
                            NumberAnimation {
                                duration: card.fade
                            }
                        }

                        Repeater {
                            model: card.menuOpen ? card.menuDeeds : []

                            DeedButton {
                                required property var modelData

                                deed: modelData
                                toast: card
                                wide: true
                            }
                        }
                    }
                }
            }
        }

        // Optional countdown line. Expiry runs whether or not it is shown.
        Rectangle {
            visible: card.showCountdown && card.duration > 0 && card.place.front === true && card.remaining > 0 && !card.expanded
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            anchors.leftMargin: plate.border.width + 7
            anchors.bottomMargin: plate.border.width
            height: 2
            radius: 1
            color: card.accentColor
            width: visible ? Math.max(0, (body.width - plate.border.width * 2 - 14) * card.countdown) : 0
        }

        // Clicks on the card, underneath its own controls. Right dismisses,
        // middle opens the snooze menu (the owner's luna patch, kept), left
        // activates. Not hoverEnabled: the deck's own region needs hover.
        MouseArea {
            anchors.fill: parent
            z: -1
            hoverEnabled: false
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: mouse => {
                if (mouse.button === Qt.MiddleButton) {
                    card.menuOpen = !card.menuOpen;
                    return;
                }
                if (card.menuOpen) {
                    card.menuOpen = false;
                    return;
                }
                if (mouse.button === Qt.RightButton)
                    card.dismissed();
                else
                    card.activated();
            }
        }
    }
}
