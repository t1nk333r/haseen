import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Usage.js" as Usage

// System usage details: CPU, memory, swap and GPU with meters, and the top
// processes by CPU from a `top -b -n 2` snapshot. Samples every 3 s only
// while open (the panel is a LazyLoader, so nothing runs when closed).
// Open with `haseen shell ipc panel toggle haseen.sysusage` or a click on the
// bar widget.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property int panelWidth: Theme.fontSize * 28

    spacing: Theme.gap
    width: panelWidth

    Sampler {
        id: sampler
        active: root.visible
        wantTop: true
        wantGpu: root.settings.showGpu !== false
        gpuChoice: typeof root.settings.gpu === "string" ? root.settings.gpu : "auto"
    }

    component Meter: Column {
        id: meter

        property string label
        property string detail
        property real value: -1

        width: root.panelWidth
        spacing: 3

        Item {
            width: parent.width
            height: labelText.implicitHeight

            Text {
                id: labelText
                text: meter.label
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.right: parent.right
                text: (meter.detail !== "" ? meter.detail + "  " : "") + (meter.value < 0 ? "--" : Math.round(meter.value) + "%")
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize
            }
        }

        Rectangle {
            width: parent.width
            height: Math.max(4, Math.round(Theme.gap * 0.75))
            radius: height / 2
            color: Theme.surfaceAlt

            Rectangle {
                width: parent.width * Math.max(0, meter.value) / 100
                height: parent.height
                radius: parent.radius
                color: meter.value >= 95 ? Theme.urgent : meter.value >= 80 ? Theme.warning : Theme.accent
            }
        }
    }

    Meter {
        label: "CPU"
        value: sampler.cpu
    }

    Meter {
        label: "Memory"
        value: sampler.mem ? sampler.mem.percent : -1
        detail: sampler.mem ? Usage.formatKiB(sampler.mem.usedKiB) + " / " + Usage.formatKiB(sampler.mem.totalKiB) : ""
    }

    Meter {
        visible: sampler.mem !== null && sampler.mem.swapTotalKiB > 0
        label: "Swap"
        value: sampler.mem && sampler.mem.swapTotalKiB > 0 ? 100 * sampler.mem.swapUsedKiB / sampler.mem.swapTotalKiB : -1
        detail: sampler.mem ? Usage.formatKiB(sampler.mem.swapUsedKiB) + " / " + Usage.formatKiB(sampler.mem.swapTotalKiB) : ""
    }

    Meter {
        visible: sampler.gpuInfo !== null
        label: sampler.gpuLabel
        value: sampler.gpu
        detail: sampler.gpuInfo ? sampler.gpuInfo.card + " " + sampler.gpuInfo.driver : ""
    }

    Text {
        topPadding: Theme.gap
        text: "Top processes"
        color: Theme.foreground
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
        font.bold: true
    }

    Text {
        visible: sampler.processes.length === 0
        text: "Sampling…"
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: sampler.processes

        delegate: Item {
            required property var modelData

            width: root.panelWidth
            height: name.implicitHeight

            Text {
                id: name
                width: parent.width - stats.implicitWidth - Theme.gap
                text: modelData.command
                elide: Text.ElideRight
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                id: stats
                anchors.right: parent.right
                text: modelData.cpu.toFixed(1).padStart(5) + "% cpu " + modelData.mem.toFixed(1).padStart(4) + "% mem"
                color: Theme.muted
                font.family: Theme.fontMono
                font.pixelSize: Theme.fontSize - 1
            }
        }
    }
}
