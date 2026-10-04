import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets

// haseen.osd: a small card near the bottom of the focused screen when the
// default sink's volume/mute or the backlight changes. Both sources are
// events (PipeWire signals, an inotify watch on sysfs); the only timer is the
// single-shot 1.5 s hide. The window exists only while the card is shown and
// takes no input, so clicks pass through.
//
// Brightness watches actual_brightness, not brightness: the backlight class
// calls sysfs_notify() on actual_brightness for every change, including
// firmware hotkeys, while brightness only reports writes from userspace.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property bool volumeEnabled: settings.volume !== false
    readonly property bool brightnessEnabled: settings.brightness !== false

    property bool shown: false
    property string glyph: ""
    property real value: 0
    property bool dim: false

    function show(g: string, v: real, muted: bool): void {
        glyph = g;
        value = Math.max(0, Math.min(1, v));
        dim = muted;
        shown = true;
        hideTimer.restart();
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // --- volume -------------------------------------------------------------
    readonly property PwNode sink: Pipewire.defaultAudioSink
    // The first reading of a sink only seeds the baseline: startup and a
    // default-sink switch must not flash the OSD.
    property var _seenSink: null
    property real _lastVolume: 0
    property bool _lastMuted: false

    function volumeGlyph(v: real, muted: bool): string {
        return muted || v <= 0 ? "\ueee8" : v >= 0.67 ? "\uf028" : v >= 0.34 ? "\uf027" : "\uf026";
    }

    function _audioChanged(): void {
        const s = sink;
        if (!s || !s.ready || !s.audio)
            return;
        const v = s.audio.volume, m = s.audio.muted;
        if (_seenSink !== s) {
            _seenSink = s;
            _lastVolume = v;
            _lastMuted = m;
            return;
        }
        if (Math.abs(v - _lastVolume) < 0.0005 && m === _lastMuted)
            return;
        _lastVolume = v;
        _lastMuted = m;
        if (volumeEnabled)
            show(volumeGlyph(v, m), v, m);
    }

    PwObjectTracker {
        objects: [root.sink]
    }

    Connections {
        target: root.sink
        function onReadyChanged() {
            root._audioChanged();
        }
    }

    Connections {
        target: root.sink && root.sink.audio ? root.sink.audio : null
        function onVolumeChanged() {
            root._audioChanged();
        }
        function onMutedChanged() {
            root._audioChanged();
        }
    }

    // --- brightness ---------------------------------------------------------
    readonly property string backlight: {
        if (typeof settings.backlight === "string" && settings.backlight !== "")
            return settings.backlight;
        return backlights.count > 0 ? backlights.get(0, "fileName") : "";
    }
    readonly property string backlightDir: backlight !== "" ? "/sys/class/backlight/" + backlight : ""
    property int _maxBrightness: 0
    property int _lastBrightness: -1

    function _brightnessRead(raw: string): void {
        const v = parseInt(raw);
        if (isNaN(v) || _maxBrightness <= 0)
            return;
        if (_lastBrightness < 0 || v === _lastBrightness) {
            _lastBrightness = v;
            return;
        }
        _lastBrightness = v;
        if (brightnessEnabled)
            show("\uf185", v / _maxBrightness, false);
    }

    onBacklightDirChanged: _lastBrightness = -1

    // Lists the backlight devices once (and on hotplug). A missing
    // directory makes FolderListModel fall back to the working directory;
    // the max_brightness read below then fails and brightness stays off.
    FolderListModel {
        id: backlights

        folder: root.brightnessEnabled ? "file:///sys/class/backlight" : ""
        showDirs: true
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    FileView {
        path: root.brightnessEnabled && root.backlightDir !== "" ? root.backlightDir + "/max_brightness" : ""
        printErrors: false
        onLoaded: root._maxBrightness = parseInt(text()) || 0
        onLoadFailed: root._maxBrightness = 0
    }

    FileView {
        path: root._maxBrightness > 0 ? root.backlightDir + "/actual_brightness" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root._brightnessRead(text())
    }

    // --- surface ------------------------------------------------------------
    // haseen:ui-timeout
    Timer {
        id: hideTimer

        interval: 1500
        repeat: false
        onTriggered: root.shown = false
    }

    LazyLoader {
        active: root.shown

        PanelWindow {
            screen: root.focusedScreen()
            anchors.bottom: true
            margins.bottom: Theme.gap * 12
            exclusionMode: ExclusionMode.Ignore
            implicitWidth: card.implicitWidth
            implicitHeight: card.implicitHeight
            color: "transparent"
            mask: Region {}
            WlrLayershell.namespace: "haseen-osd"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Rectangle {
                id: card

                implicitWidth: row.implicitWidth + Theme.gap * 4
                implicitHeight: row.implicitHeight + Theme.gap * 3
                color: Theme.surface
                radius: Theme.radius
                border.color: Theme.border
                border.width: Theme.borderWidth

                Row {
                    id: row

                    anchors.centerIn: parent
                    spacing: Theme.gap * 2

                    Glyph {
                        width: Theme.fontSize * 2
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: root.glyph
                        color: root.dim ? Theme.muted : Theme.foreground
                        font.pixelSize: Theme.fontSize * 1.6
                    }

                    Rectangle {
                        width: Theme.fontSize * 12
                        height: Math.max(Theme.gap, 4)
                        anchors.verticalCenter: parent.verticalCenter
                        radius: height / 2
                        color: Theme.surfaceAlt

                        Rectangle {
                            width: parent.width * root.value
                            height: parent.height
                            radius: parent.radius
                            color: root.dim ? Theme.muted : Theme.accent
                        }
                    }

                    Text {
                        width: Theme.fontSize * 3
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(root.value * 100) + "%"
                        color: root.dim ? Theme.muted : Theme.foreground
                        horizontalAlignment: Text.AlignRight
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                    }
                }
            }
        }
    }
}
