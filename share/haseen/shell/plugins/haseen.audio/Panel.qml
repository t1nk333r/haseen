// Adapted from Omarchy shell/plugins/panels/audio/Panel.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own layout on haseen widgets and theme tokens; no MPRIS matching.
import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Audio panel: output volume and mute, output device, input volume and mute,
// input device, per-app playback volumes. Everything is PipeWire property
// bindings (Quickshell.Services.Pipewire), no polling. Open with
// `haseen shell ipc panel toggle haseen.audio` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var source: Pipewire.defaultAudioSource
    readonly property var sinks: Model.sinks(nodes)
    readonly property var sources: Model.sources(nodes)
    readonly property var streams: Model.streams(nodes)

    width: Theme.fontSize * 26
    spacing: Theme.gap

    // Binds every listed node so audio, nickname and properties are live.
    PwObjectTracker {
        objects: root.sinks.concat(root.sources, root.streams)
    }

    // Test hook (settings.debugIpc): read the panel's view of the graph.
    // Read-only: smoke runs must never change the owner's audio.
    IpcHandler {
        target: "haseen.audio"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                sink: root.sink ? root.sink.name : null,
                source: root.source ? root.source.name : null,
                sinks: root.sinks.map(n => Model.nodeLabel(n)),
                sources: root.sources.map(n => Model.nodeLabel(n)),
                streams: root.streams.map(n => Model.streamLabel(n))
            });
        }
    }

    component SectionLabel: Text {
        width: root.width
        topPadding: Theme.gap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    component DeviceRow: Item {
        id: row

        required property var node
        property string glyph
        property bool current: false

        signal activated

        width: root.width
        height: Math.round(Theme.fontSize * 2.2)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: row.current ? Theme.selection : Theme.surfaceAlt
            visible: row.current || mouse.containsMouse
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            onClicked: row.activated()
        }

        Glyph {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: row.glyph
            color: row.current ? Theme.accent : Theme.foreground
        }

        Text {
            anchors.left: icon.right
            anchors.leftMargin: Theme.gap
            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: Model.nodeLabel(row.node)
            color: Theme.foreground
            elide: Text.ElideRight
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Audio"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.sink !== null && root.sink.audio !== null
            text: visible ? Model.outputVolumeName(root.sink.audio.volume, root.sink.audio.muted) : ""
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: parent.width
        visible: root.sink === null
        wrapMode: Text.WordWrap
        text: "No audio output (is PipeWire running?)."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    SectionLabel {
        visible: root.sink !== null
        text: "Output"
    }

    VolumeRow {
        width: parent.width
        visible: root.sink !== null && root.sink.audio !== null
        audio: root.sink ? root.sink.audio : null
        glyph: Model.sinkGlyph(root.sink)
        label: Model.nodeLabel(root.sink)
    }

    Repeater {
        model: root.sinks.length > 1 ? root.sinks : []

        delegate: DeviceRow {
            required property var modelData

            node: modelData
            glyph: Model.sinkGlyph(modelData)
            current: modelData === root.sink
            onActivated: Pipewire.preferredDefaultAudioSink = modelData
        }
    }

    SectionLabel {
        visible: root.source !== null
        text: "Input"
    }

    VolumeRow {
        width: parent.width
        visible: root.source !== null && root.source.audio !== null
        audio: root.source ? root.source.audio : null
        glyph: root.source && root.source.audio && root.source.audio.muted ? "\u{F036D}" : Model.sourceGlyph(root.source)
        label: Model.nodeLabel(root.source)
    }

    Repeater {
        model: root.sources.length > 1 ? root.sources : []

        delegate: DeviceRow {
            required property var modelData

            node: modelData
            glyph: Model.sourceGlyph(modelData)
            current: modelData === root.source
            onActivated: Pipewire.preferredDefaultAudioSource = modelData
        }
    }

    SectionLabel {
        visible: root.streams.length > 0
        text: "Apps"
    }

    Repeater {
        model: root.streams

        delegate: VolumeRow {
            required property var modelData

            width: root.width
            audio: modelData.audio
            glyph: "\u{F075A}"
            label: Model.streamLabel(modelData)
            detail: Model.streamDetail(modelData)
        }
    }
}
