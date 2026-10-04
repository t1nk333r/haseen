import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets

// Compact CPU / RAM / GPU percentages. Samples only while the bar shows it
// (Sampler.active). Click opens the haseen.sysusage panel (details and top
// processes). Values >= warnAt turn warning, >= 95 % urgent.
Item {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null
    property bool vertical: false

    readonly property int warnAt: typeof settings.warnAt === "number" ? settings.warnAt : 80
    // The model holds only keys, so a new sample updates the texts in place
    // instead of rebuilding the delegates every tick.
    readonly property var keys: sampler.gpuInfo !== null ? ["cpu", "mem", "gpu"] : ["cpu", "mem"]
    readonly property var glyphs: ({
            cpu: "\uf4bc",
            mem: "\u{F035B}",
            gpu: "\u{F08AE}"
        })
    readonly property int cpu: Math.round(sampler.cpu)
    readonly property int mem: sampler.mem ? Math.round(sampler.mem.percent) : -1
    readonly property int gpu: Math.round(sampler.gpu)

    function tone(v: real): color {
        return v >= 95 ? Theme.urgent : v >= root.warnAt ? Theme.warning : Theme.barForeground;
    }

    // Vertical: the slot is the bar's width anyway; report content width
    // only (depending on the parent's width would loop through BarSection).
    implicitWidth: vertical ? grid.implicitWidth : grid.implicitWidth + Theme.gap * 2
    implicitHeight: vertical ? grid.implicitHeight + Theme.gap * 2 : Config.barHeight

    Sampler {
        id: sampler
        // Item.visible stays true inside a hidden window, so the window counts too.
        active: root.visible && (root.QsWindow.window ? root.QsWindow.window.visible : true)
        wantGpu: root.settings.showGpu !== false
        gpuChoice: typeof root.settings.gpu === "string" ? root.settings.gpu : "auto"
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Theme.radius
        color: Theme.surfaceAlt
        visible: mouse.containsMouse
    }

    Grid {
        id: grid
        anchors.centerIn: parent
        columns: root.vertical ? 1 : root.keys.length
        columnSpacing: Theme.gap
        rowSpacing: Math.round(Theme.gap / 2)

        Repeater {
            model: root.keys

            delegate: Grid {
                required property string modelData
                readonly property int value: root[modelData]
                readonly property color tint: value < 0 ? Theme.muted : root.tone(value)

                columns: root.vertical ? 1 : 2
                columnSpacing: Math.round(Theme.gap / 2)
                horizontalItemAlignment: Grid.AlignHCenter
                verticalItemAlignment: Grid.AlignVCenter

                Glyph {
                    glyph: root.glyphs[parent.modelData]
                    color: parent.tint
                }

                Text {
                    // Fixed width per value so the bar does not jitter.
                    text: parent.value < 0 ? "--" : parent.value + (root.vertical ? "" : "%")
                    color: parent.tint
                    font.family: Theme.fontMono
                    font.pixelSize: root.vertical ? Theme.fontSize - 2 : Theme.fontSize
                    horizontalAlignment: Text.AlignRight
                    width: Math.ceil(metrics.advanceWidth)
                }
            }
        }
    }

    TextMetrics {
        id: metrics
        font.family: Theme.fontMono
        font.pixelSize: root.vertical ? Theme.fontSize - 2 : Theme.fontSize
        text: root.vertical ? "100" : "100%"
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        onClicked: Quickshell.execDetached(["qs", "-p", Quickshell.shellDir, "ipc", "call", "panel", "toggle", root.pluginId])
    }
}
