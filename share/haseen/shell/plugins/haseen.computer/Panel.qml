import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Haseen
import qs.Haseen.Widgets
import "Computer.js" as Computer

// Your computer (plan 162): the processor and memory over the last 90 s, the
// processor's temperature, and how full the root disk is, under the uptime
// and the battery. Behaviour taken from pocket-dots' "Your computer" panel
// (GPL-3.0, reference only, nothing copied).
//
// haseen-sidecar does the sampling. The plugin's service (Service.qml, plan
// 165) keeps the histories while the panel is closed, so the panel opens on
// the last 90 s and only draws them. Without the service (a user's own
// `services` list without it) the panel subscribes to the `sysusage` stream
// itself while it is shown and keeps a history that starts when it opens, as
// plan 162 built it. The uptime and the load are re-read when a sample
// arrives, the thread count once.
//
// Open with SUPER + SHIFT + D, the menu's Trigger > Your Computer, or
// `haseen shell ipc panel toggle haseen.computer`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // System files under $HASEEN_SYSROOT, as the CLI's sysroot_path reads
    // them, so a test points the panel at a fixture tree.
    readonly property string sysroot: Quickshell.env("HASEEN_SYSROOT") || ""

    readonly property bool available: Sidecar.has("sysusage")
    readonly property var sample: Sidecar.streams["sysusage"] || null

    readonly property var service: {
        const entry = Plugins.roles.computer;
        return entry && entry.id === root.pluginId ? entry.instance : null;
    }

    // The histories, {t, v} per sample, newest last (Computer.push): the
    // service's, else the panel's own.
    readonly property var cpuHistory: service ? service.cpuHistory : _cpu
    readonly property var memHistory: service ? service.memHistory : _mem
    readonly property var tempHistory: service ? service.tempHistory : _temp
    property var _cpu: []
    property var _mem: []
    property var _temp: []
    property var _last: null

    readonly property real cpu: sample && typeof sample.cpu === "number" ? sample.cpu : -1
    readonly property var mem: sample && sample.mem ? sample.mem : null
    readonly property real tempC: sample && typeof sample.cpuTempC === "number" ? sample.cpuTempC : -1
    readonly property var disk: Computer.pickDisk(sample ? sample.disks : null, settings.mount)

    property string uptimeText: ""
    property string loadText: ""
    property int threads: 0
    readonly property var up: Computer.uptime(uptimeText)
    readonly property real load: Computer.loadAverage(loadText)

    readonly property var battery: UPower.displayDevice
    readonly property bool hasBattery: battery !== null && battery.ready && battery.isLaptopBattery && battery.isPresent

    readonly property int cardGap: Theme.spacing.xxl
    readonly property int pad: Theme.spacing.popupPadding
    readonly property color subtle: Theme.subtle(Theme.popups.background)

    width: Theme.fontSize * 54
    spacing: Theme.spacing.xxl

    // record(sample, t) — one sample into the histories. The stream handler
    // calls it with the arrival time; a test calls it with its own clock.
    function record(s: var, t: real): void {
        if (!s)
            return;
        if (service) {
            service.record(s, t);
            return;
        }
        _cpu = Computer.push(_cpu, t, s.cpu);
        _mem = Computer.push(_mem, t, s.mem ? s.mem.percent : -1);
        _temp = Computer.push(_temp, t, s.cpuTempC);
    }

    function percent(v: real): string {
        return I18n.tr("%1 %", I18n.formatNumber(Math.round(v)));
    }

    // GiB with one decimal ("6.5 of 15.4 GiB"), or none when the total it
    // is read against reaches 1000 GiB ("592 GiB free of 1861"), where a
    // tenth says nothing; both numbers of a pair look alike.
    function gib(kib: real, totalKib: real): string {
        return I18n.formatNumber(Computer.gib(kib), Computer.gib(totalKib) >= 1000 ? 0 : 1);
    }

    function uptimeLabel(): string {
        if (!up)
            return "";
        if (up.days > 0)
            return I18n.tr("%1 d %2 h", I18n.formatNumber(up.days), I18n.formatNumber(up.hours));
        if (up.hours > 0)
            return I18n.tr("%1 h %2 min", I18n.formatNumber(up.hours), I18n.formatNumber(up.minutes));
        return I18n.tr("%1 min", I18n.formatNumber(up.minutes));
    }

    function subtitle(): string {
        const parts = [];
        if (up)
            parts.push(I18n.tr("Uptime %1", uptimeLabel()));
        if (hasBattery)
            parts.push(I18n.tr("Battery %1", percent(battery.percentage * 100)));
        return parts.join(" · ");
    }

    // The panel's own subscription, only without the service and only while
    // the panel is shown: one key of its own, merged by Sidecar with the bar
    // widget's, so the daemon runs one sampler.
    readonly property string _key: "computer:" + String(root)

    function _apply(): void {
        if (!visible || service) {
            Sidecar.drop(_key);
            return;
        }
        Sidecar.want(_key, "sysusage", {
            intervalMs: Computer.INTERVAL_MS,
            gpu: "off",
            system: true
        });
    }

    onVisibleChanged: _apply()
    onServiceChanged: _apply()
    onSampleChanged: {
        // Sidecar.streams changes for every stream; only a new sysusage
        // frame is a sample. The service records it itself.
        if (!sample || sample === _last)
            return;
        _last = sample;
        if (!service)
            record(sample, Date.now());
        uptimeFile.reload();
        loadFile.reload();
    }
    Component.onCompleted: {
        Sidecar.ensure();
        _apply();
    }
    Component.onDestruction: Sidecar.drop(_key)

    FileView {
        id: uptimeFile

        path: root.sysroot + "/proc/uptime"
        printErrors: false
        onLoaded: root.uptimeText = text()
    }

    FileView {
        id: loadFile

        path: root.sysroot + "/proc/loadavg"
        printErrors: false
        onLoaded: root.loadText = text()
    }

    // The logical CPUs online; read once when the panel opens.
    FileView {
        path: root.sysroot + "/sys/devices/system/cpu/online"
        printErrors: false
        onLoaded: root.threads = Computer.cpuCount(text())
    }

    // A card on the panel: the foreground's faint fill and a hairline edge.
    component Card: Rectangle {
        default property alias content: inner.data

        color: Theme.normalFill
        border.color: Theme.separator
        border.width: 1
        radius: Theme.radius

        Item {
            id: inner

            anchors.fill: parent
            anchors.margins: root.pad
        }
    }

    // A reading's first line: a dot, its name, its value and a note.
    component Heading: Row {
        property string name
        property string value
        property string note

        spacing: Theme.spacing.lg

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(6, Theme.space(7))
            height: width
            radius: width / 2
            color: Theme.accent
        }

        Text {
            anchors.baseline: valueText.baseline
            text: parent.name
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.body
        }

        Text {
            id: valueText

            text: parent.value
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.heading
            font.bold: true
        }

        Text {
            anchors.baseline: valueText.baseline
            visible: text !== ""
            text: parent.note
            color: root.subtle
            font.family: Theme.fontFamily
            font.pixelSize: Theme.font.bodySmall
        }
    }

    // A graph's ceiling, announced at its top left in every language: the
    // graph under it is not mirrored either.
    component Ceiling: Text {
        color: root.subtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.caption
    }

    // --- header --------------------------------------------------------------
    Row {
        width: parent.width
        spacing: Theme.spacing.xl

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            glyph: String.fromCodePoint(0xf4bc)
            color: Theme.accent
            font.pixelSize: Theme.font.iconLarge
        }

        // As wide as its longer line, each line as wide as the column, so a
        // mirrored panel aligns both to the right.
        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(title.implicitWidth, subtitleText.implicitWidth)

            Text {
                id: title

                width: parent.width
                text: I18n.tr("Your computer")
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.title
                font.bold: true
            }

            Text {
                id: subtitleText

                width: parent.width
                visible: text !== ""
                text: root.subtitle()
                color: root.subtle
                font.family: Theme.fontFamily
                font.pixelSize: Theme.font.bodySmall
            }
        }
    }

    PanelSeparator {}

    // --- no daemon -------------------------------------------------------------
    Text {
        width: parent.width
        visible: !root.available
        wrapMode: Text.WordWrap
        text: I18n.tr("No readings: haseen-sidecar is not running. Start it with: haseen sidecar start")
        color: root.subtle
        font.family: Theme.fontFamily
        font.pixelSize: Theme.font.body
    }

    // --- the cards ---------------------------------------------------------------
    Row {
        id: cards

        visible: root.available
        width: parent.width
        height: usage.height
        spacing: root.cardGap

        // Processor and memory, one over the other, each with its own scale.
        Card {
            id: usage

            objectName: "usageCard"

            width: Math.round((cards.width - root.cardGap) * 0.62)
            height: usageColumn.implicitHeight + root.pad * 2

            Column {
                id: usageColumn

                width: parent.width
                spacing: Theme.spacing.md

                Item {
                    width: parent.width
                    height: cpuHeading.height

                    Heading {
                        id: cpuHeading

                        anchors.left: parent.left
                        name: I18n.tr("Processor")
                        value: root.cpu < 0 ? "--" : root.percent(root.cpu)
                        note: [root.load >= 0 ? I18n.tr("load %1", I18n.formatNumber(root.load, 2)) : "", root.threads > 0 ? I18n.tn("%1 thread", "%1 threads", root.threads) : ""].filter(s => s !== "").join(" · ")
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("last 90 s")
                        color: root.subtle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.caption
                    }
                }

                Ceiling {
                    text: root.percent(Computer.ceiling(root.cpuHistory))
                }

                Graph {
                    objectName: "cpuGraph"
                    width: parent.width
                    height: Theme.fontSize * 8
                    history: root.cpuHistory
                    hi: Computer.ceiling(root.cpuHistory)
                }

                Item {
                    width: 1
                    height: Theme.spacing.md
                }

                // In an item as wide as the card, so a mirrored panel puts
                // it on the right as it does the processor's.
                Item {
                    width: parent.width
                    height: memHeading.height

                    Heading {
                        id: memHeading

                        anchors.left: parent.left
                        name: I18n.tr("Memory")
                        value: root.mem ? root.percent(root.mem.percent) : "--"
                        note: root.mem ? I18n.tr("%1 of %2 GiB", root.gib(root.mem.usedKiB, root.mem.totalKiB), root.gib(root.mem.totalKiB, root.mem.totalKiB)) : ""
                    }
                }

                Ceiling {
                    text: root.percent(Computer.ceiling(root.memHistory))
                }

                Graph {
                    objectName: "memGraph"
                    width: parent.width
                    height: Theme.fontSize * 4
                    history: root.memHistory
                    hi: Computer.ceiling(root.memHistory)
                }
            }
        }

        Column {
            width: cards.width - usage.width - root.cardGap
            height: usage.height
            spacing: root.cardGap

            // The temperature fills what the storage card leaves.
            Card {
                id: tempCard

                objectName: "tempCard"

                width: parent.width
                height: parent.height - storage.height - root.cardGap

                readonly property var range: Computer.tempRange(root.tempHistory)

                Item {
                    id: tempTop

                    width: parent.width
                    height: tempName.height + tempWord.height

                    Glyph {
                        id: tempGlyph

                        anchors.left: parent.left
                        anchors.verticalCenter: tempName.verticalCenter
                        glyph: String.fromCodePoint(0xf2c9)
                        color: Theme.accent
                    }

                    Text {
                        id: tempName

                        anchors.left: tempGlyph.right
                        anchors.leftMargin: Theme.spacing.lg
                        text: I18n.tr("Temperature")
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.body
                    }

                    Text {
                        id: tempWord

                        anchors.left: tempName.left
                        anchors.top: tempName.bottom
                        text: root.tempC < 0 ? I18n.tr("Unknown") : I18n.tr(Computer.tempWord(root.tempC))
                        color: Computer.tempLevel(root.tempC) === 2 ? Theme.urgent : Computer.tempLevel(root.tempC) === 1 ? Theme.warning : root.subtle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.bodySmall
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        visible: root.tempC >= 0
                        text: I18n.tr("%1 °C", I18n.formatNumber(Math.round(root.tempC)))
                        color: Theme.foreground
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.heading
                        font.bold: true
                    }
                }

                Graph {
                    objectName: "tempGraph"
                    visible: root.tempC >= 0
                    anchors.top: tempTop.bottom
                    anchors.topMargin: Theme.spacing.md
                    anchors.bottom: parent.bottom
                    width: parent.width
                    history: root.tempHistory
                    lo: tempCard.range.lo
                    hi: tempCard.range.hi
                    stroke: Computer.tempLevel(root.tempC) === 2 ? Theme.urgent : Computer.tempLevel(root.tempC) === 1 ? Theme.warning : Theme.accent
                }
            }

            // How full the disk is; no history, it barely moves in 90 s.
            Card {
                id: storage

                width: parent.width
                height: storageColumn.implicitHeight + root.pad * 2

                Column {
                    id: storageColumn

                    width: parent.width
                    spacing: Theme.spacing.md

                    Item {
                        width: parent.width
                        height: storageName.height

                        Glyph {
                            id: storageGlyph

                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: String.fromCodePoint(0xf02ca)
                            color: Theme.accent
                        }

                        Text {
                            id: storageName

                            anchors.left: storageGlyph.right
                            anchors.leftMargin: Theme.spacing.lg
                            anchors.verticalCenter: parent.verticalCenter
                            text: I18n.tr("Storage")
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.body
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.disk ? root.percent(root.disk.percent) : "--"
                            color: Theme.foreground
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.font.heading
                            font.bold: true
                        }
                    }

                    // A level meter: it fills from the right in a mirrored
                    // panel, as TrackBar does under LayoutMirroring.
                    TrackBar {
                        width: parent.width
                        enabled: false
                        value: root.disk ? root.disk.percent / 100 : 0
                    }

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        text: root.disk ? I18n.tr("%1 GiB free of %2", root.gib(root.disk.availKiB, root.disk.totalKiB), root.gib(root.disk.totalKiB, root.disk.totalKiB)) : I18n.tr("No disk at %1", root.settings.mount || "/")
                        color: root.subtle
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.font.bodySmall
                    }
                }
            }
        }
    }
}
