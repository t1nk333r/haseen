import QtQuick
import Quickshell.Services.Pipewire
import qs.Haseen
import qs.Haseen.Widgets

// PipeWire default sink via Quickshell.Services.Pipewire (event-driven).
// Scroll changes the volume, click toggles mute.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.ready && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : true
    readonly property real step: typeof settings.step === "number" && settings.step > 0 ? settings.step : 0.05

    glyph: muted || volume <= 0 ? "\ueee8" : volume >= 0.67 ? "\uf028" : volume >= 0.34 ? "\uf027" : "\uf026"
    text: ready ? Math.round(volume * 100) + "%" : ""
    color: muted ? Theme.muted : Theme.barForeground

    onClicked: button => {
        if (ready && button === Qt.LeftButton)
            sink.audio.muted = !sink.audio.muted;
    }
    onScrolled: steps => {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(1, sink.audio.volume + steps * step));
    }

    // Binds the sink so its audio properties are live.
    PwObjectTracker {
        objects: [root.sink]
    }
}
