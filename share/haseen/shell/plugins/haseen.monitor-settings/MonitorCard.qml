import QtQuick
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// One monitor in the haseen.monitor-settings panel: its friendly name and
// mode, then refresh rate, scale and rotation for an enabled monitor, and an
// on/off pill. A change is a request(argv) for `haseen hardware monitor` (or
// `haseen hardware laptop-display` for the built-in panel); the panel runs
// it. Adapted from the Displays and Refresh rate sections of juliusmork-sys's
// Monitor Settings Extender (MIT, Copyright (c) 2026 Julius Getz Mørk).
Column {
    id: card

    required property var monitor
    // The panel's monitor list, for the rotation's push-out.
    property var monitors: []
    property bool busy: false
    // False for the last enabled monitor: it cannot be turned off.
    property bool canTurnOff: true
    property bool mirroring: false

    signal request(var argv)

    readonly property var rates: Model.ratesFor(monitor.modes, monitor.width, monitor.height)
    readonly property var scales: Model.scalesFor(monitor.width, monitor.height)
    readonly property color subtle: Theme.subtle(Theme.surface)

    spacing: Math.round(Theme.gap / 2)

    Item {
        width: card.width
        height: Math.round(Theme.fontSize * 2.2)

        Glyph {
            id: glyph

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: card.monitor.internal ? "\u{F0322}" : "\u{F0379}"
            color: card.monitor.focused ? Theme.accent : Theme.foreground
        }

        Column {
            anchors.left: glyph.right
            anchors.leftMargin: Theme.gap
            anchors.right: power.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: I18n.tr(card.monitor.label)
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                textFormat: Text.PlainText
                elide: Text.ElideRight
                text: card.monitor.disabled ? I18n.tr("%1 · off", card.monitor.name) : card.monitor.name + " · " + card.monitor.width + " × " + card.monitor.height + " @ " + Model.formatHz(card.monitor.refreshRate)
                color: card.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 1
            }
        }

        Pill {
            id: power

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: card.monitor.disabled ? I18n.tr("Turn on") : I18n.tr("Turn off")
            busy: card.busy
            enabled: card.monitor.disabled || (card.canTurnOff && !card.mirroring)
            onClicked: {
                if (card.monitor.internal)
                    card.request(["hardware", "laptop-display", card.monitor.disabled ? "on" : "off"]);
                else
                    card.request(["hardware", "monitor", "set", card.monitor.name, card.monitor.disabled ? "--on" : "--off"]);
            }
        }
    }

    Text {
        width: card.width
        visible: card.monitor.userRule
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: I18n.tr("Your ~/.config/hypr/monitors.lua (or hyprmod) also sets this monitor; that rule wins at the next reload.")
        color: Theme.warning
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    PillRow {
        width: card.width
        visible: !card.monitor.disabled && !card.mirroring && card.rates.length > 1
        title: I18n.tr("Refresh rate")
        options: card.rates.map(r => ({ value: r, label: Model.formatHz(r) }))
        current: Model.nearest(card.rates, card.monitor.refreshRate)
        busy: card.busy
        onPicked: value => card.request(["hardware", "monitor", "set", card.monitor.name, "--mode", Model.modeArg(card.monitor, value)])
    }

    PillRow {
        width: card.width
        visible: !card.monitor.disabled && !card.mirroring && card.scales.length > 0
        title: I18n.tr("Scale")
        options: card.scales.map(s => ({ value: s, label: s + "×" }))
        current: Model.nearest(card.scales, card.monitor.scale)
        busy: card.busy
        onPicked: value => card.request(["hardware", "monitor", "set", card.monitor.name, "--scale", String(value)])
    }

    PillRow {
        width: card.width
        visible: !card.monitor.disabled && !card.mirroring
        title: I18n.tr("Rotation")
        options: Model.ROTATIONS
        current: card.monitor.transform
        busy: card.busy
        onPicked: value => {
            const at = Model.rotated(card.monitors, card.monitor.name, value);
            const argv = ["hardware", "monitor", "set", card.monitor.name, "--transform", String(value)];
            card.request(at ? argv.concat(["--position", at.x + "x" + at.y]) : argv);
        }
    }
}
