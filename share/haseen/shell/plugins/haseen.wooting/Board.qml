import QtQuick
import QtQuick.Layouts
import qs.Haseen
import "Model.js" as Model

// The connected board, drawn from the firmware's own row/column matrix, with
// keys lit live from the analog stream (plan 099). Adapted from the owner's
// t1nk33r.wooting LayoutPanel.qml (MIT, Copyright (c) 2026 t1nk33r) onto
// haseen's Theme tokens and into haseen.wooting's panel: the original was a
// full-screen overlay of its own. Created when the panel's Keyboard layout
// pill is pressed and destroyed with the panel, so the analog subscription,
// up to 60 events a second while typing, exists only while it is seen.
//
// No HID here, ever: one socket to wootingd carries `subscribe` (model,
// layout, profile), `analog subscribe` (key travel) and `fn get` (the Fn
// layer the daemon learned).
ColumnLayout {
    id: root

    property var keyboard: Model.emptyState()
    property var device: ({ model: null, columns: 0, functionRow: false, layout: "unknown" })
    property bool analogPresent: false
    property var pressed: ({})
    // What this board reports under Fn, learned by wootingd from real presses
    // and kept across restarts; it outranks Wooting's documented defaults.
    property var learnedFn: ({})
    // Pinned by clicking the Fn key; while Fn is held the view follows it.
    property bool fnPinned: false

    readonly property bool fnHeld: Model.fnHeld(pressed)
    readonly property bool fnView: fnHeld || fnPinned
    readonly property var keys: Model.keysFor(device)
    readonly property var grid: Model.gridSize(keys)
    readonly property var stray: Model.unmapped(pressed, keys)
    readonly property int pressedCount: Object.keys(pressed).length
    readonly property real unit: Math.round(Theme.fontSize * 3.1)
    readonly property real keyGap: Math.max(2, Math.round(Theme.gap / 2))

    spacing: Theme.gap

    function ingest(line: string): void {
        const message = Model.parseLine(line);
        if (!message)
            return;
        const fnKeys = Model.fnMap(message);
        if (fnKeys) {
            root.learnedFn = fnKeys;
            return;
        }
        if (message.event === "analog") {
            root.analogPresent = message.present === true;
            root.pressed = Model.analogMap(message);
            return;
        }
        root.keyboard = Model.applyMessage(root.keyboard, message);
        if (typeof message.columns === "number")
            root.device = {
                model: typeof message.model === "string" ? message.model : null,
                columns: message.columns,
                functionRow: message.functionRow === true,
                layout: typeof message.layout === "string" ? message.layout : "unknown"
            };
    }

    WootingLink {
        id: link

        hello: "subscribe\nanalog subscribe\nfn get\n"
        onUp: root.keyboard = Model.withConnected(root.keyboard, true)
        onDown: {
            root.keyboard = Model.disconnected(root.keyboard);
            root.pressed = ({});
            root.analogPresent = false;
            root.device = ({ model: null, columns: 0, functionRow: false, layout: "unknown" });
        }
        onReceived: line => root.ingest(line)
    }

    Text {
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: {
            if (!root.keyboard.connected)
                return I18n.tr(link.hint);
            if (!root.keyboard.present)
                return I18n.tr("plug in a Wooting keyboard");
            const parts = [I18n.tr("%1 layout", String(root.device.layout || "unknown").toUpperCase()), I18n.tn("%1 column", "%1 columns", root.device.columns)];
            parts.push(root.analogPresent ? I18n.tr("analog live") : I18n.tr("no analog stream"));
            return (root.device.model || "Wooting") + " · " + parts.join(" · ");
        }
        color: Theme.subtle(Theme.surface)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    // One unit is `root.unit` px; every key is placed from Model.keysFor, so
    // a row's shape is data, not QML.
    // A key map: the keys keep their physical places in a mirrored panel
    // (plan 109), down to each key's travel bar.
    Item {
        id: board

        LayoutMirroring.enabled: false
        LayoutMirroring.childrenInherit: true
        Layout.preferredWidth: root.grid.w * root.unit
        Layout.preferredHeight: root.grid.h * root.unit
        visible: root.keyboard.present && root.keys.length > 0

        Repeater {
            model: root.keys

            delegate: Rectangle {
                id: key

                required property var modelData
                readonly property var hit: root.pressed[modelData.row + "," + modelData.col]
                readonly property real travel: hit ? hit.value : 0
                readonly property bool actuated: hit ? hit.actuated : false
                readonly property bool isFn: modelData.label === "Fn"
                // In the Fn view every key shows its Fn function: what this
                // board reported while Fn was held, else Wooting's documented
                // default, else nothing mapped there.
                readonly property var fn: Model.fnLabel(modelData, root.learnedFn)
                // The firmware names a pressed key by usage, so a disagreement
                // with the transcribed label is worth showing.
                readonly property string liveLabel: hit && hit.code ? Model.hidName(hit.code) : ""
                readonly property bool relabelled: !root.fnView && liveLabel !== "" && liveLabel !== modelData.label
                readonly property string shown: root.fnView ? fn.label : (relabelled ? liveLabel : modelData.label)
                readonly property bool lit: actuated || (isFn && root.fnView)

                x: modelData.x * root.unit + root.keyGap / 2
                y: modelData.y * root.unit + root.keyGap / 2
                width: modelData.w * root.unit - root.keyGap
                height: root.unit - root.keyGap
                radius: Theme.radius
                border.width: lit ? Math.max(2, Theme.borderWidth) : Theme.borderWidth
                border.color: lit ? Theme.accent : Theme.border
                // A cell the firmware calls unassigned recedes with the
                // undocumented ones: on this board Fn+that key does nothing.
                color: travel > 0 ? Qt.alpha(Theme.accent, 0.15 + 0.85 * travel) : (root.fnView && (fn.source === "none" || fn.source === "unassigned") ? Theme.surface : Theme.surfaceAlt)

                Text {
                    anchors.centerIn: parent
                    // Bounded and elided: a consumer-page name ("Search") is
                    // wider than a 1u key.
                    width: parent.width - 6
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: key.shown
                    // Learned labels are the keyboard's own truth; documented
                    // ones are Wooting's defaults and are dimmed, as is the ▪
                    // standing for an action the firmware will not name.
                    color: key.relabelled ? Theme.urgent : (root.fnView && (key.fn.source === "documented" || key.fn.source === "internal") ? Theme.subtle(Theme.surfaceAlt) : (root.fnView && key.fn.source === "learned" ? Theme.accent : Theme.foreground))
                    font.family: Theme.fontFamily
                    font.pixelSize: key.shown.length > 3 ? Theme.fontSize - 3 : Theme.fontSize
                    font.bold: key.actuated
                }

                // The travel bar along the bottom edge: the analog part of an
                // analog keyboard, visible even at shallow presses.
                Rectangle {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    anchors.margins: 2
                    height: 3
                    radius: 1
                    color: Theme.accent
                    visible: key.travel > 0
                    width: (parent.width - 4) * key.travel
                }

                // Clicking Fn pins the layer view: holding the real Fn while
                // reading the board is not always practical.
                MouseArea {
                    anchors.fill: parent
                    enabled: key.isFn
                    cursorShape: key.isFn ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.fnPinned = !root.fnPinned
                }
            }
        }
    }

    // Anything pressed at a matrix position the grid does not draw: this is
    // how a wrong layout assumption announces itself.
    Text {
        Layout.fillWidth: true
        visible: root.stray.length > 0
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: I18n.tr("Unmapped: %1", root.stray.map(k => "r" + k.row + "c" + k.col + " " + Model.hidName(k.code) + " " + Math.round(k.value * 100) + "%").join("   "))
        color: Theme.urgent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    Text {
        Layout.fillWidth: true
        visible: root.keyboard.present
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: {
            if (root.fnView) {
                // Only names count: an action the firmware will not name
                // teaches nothing, so it is not advertised.
                const learned = Model.namedCount(root.learnedFn);
                const how = root.fnHeld ? I18n.tr("Fn held") : I18n.tr("Fn pinned, click Fn again to leave");
                return how + " · " + (learned > 0 ? I18n.tn("%1 key read off your board (accent) · dim = Wooting default · ▪ = unnamed Wooting action · blank = nothing mapped", "%1 keys read off your board (accent) · dim = Wooting default · ▪ = unnamed Wooting action · blank = nothing mapped", learned) : I18n.tr("labels are Wooting's documented defaults; hold Fn and press keys to read yours off the firmware"));
            }
            if (root.pressedCount > 0)
                return I18n.tn("%1 key under travel", "%1 keys under travel", root.pressedCount);
            return I18n.tr("Press keys to see travel · click Fn for the Fn layer");
        }
        color: Theme.subtle(Theme.surface)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
    }
}
