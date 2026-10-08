import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Haseen
import "Osd.js" as Osd

// haseen.osd: a small card near the bottom of the focused screen when the
// default sink's or source's volume/mute, the backlight, the keyboard layout
// or a lock key changes. Every source is an event: PipeWire signals, an
// inotify watch on sysfs, Hyprland's `activelayout` (through the Keyboard
// singleton), and for Caps/Num Lock a non-consuming Hyprland bind that calls
// `haseen shell ipc osd lockkeys`, which reads `hyprctl -j devices` once
// (plan 079). The only timer is the single-shot 1.5 s hide. The window exists
// only while the card is shown and takes no input, so clicks pass through.
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

    readonly property var kinds: Osd.kinds(settings)
    readonly property bool volumeEnabled: kinds.volume
    readonly property bool brightnessEnabled: kinds.brightness
    readonly property bool micEnabled: kinds.mic
    readonly property bool layoutEnabled: kinds.layout
    readonly property bool lockKeysEnabled: kinds.lockKeys

    property bool shown: false
    // The card on screen (Osd.js): a level bar, or one line of text.
    property var card: Osd.levelCard("", 0, false)

    function showCard(c: var): void {
        card = c;
        shown = true;
        hideTimer.restart();
    }

    function show(g: string, v: real, muted: bool): void {
        showCard(Osd.levelCard(g, v, muted));
    }

    function focusedScreen(): var {
        const mon = Hyprland.focusedMonitor;
        const screens = Quickshell.screens;
        for (let i = 0; i < screens.length; i++)
            if (mon && screens[i].name === mon.name)
                return screens[i];
        return screens.length > 0 ? screens[0] : null;
    }

    // --- volume and microphone ------------------------------------------------
    // One tracker per default node. The first reading of a node only seeds
    // the baseline: startup and a default-device switch must not flash the OSD.
    component AudioWatch: QtObject {
        id: watch

        property PwNode node
        property bool enabled
        property var seen: null
        property real lastVolume: 0
        property bool lastMuted: false

        signal moved(real volume, bool muted)

        function read(): void {
            const n = node;
            if (!n || !n.ready || !n.audio)
                return;
            const v = n.audio.volume, m = n.audio.muted;
            if (seen !== n) {
                seen = n;
                lastVolume = v;
                lastMuted = m;
                return;
            }
            if (Math.abs(v - lastVolume) < 0.0005 && m === lastMuted)
                return;
            lastVolume = v;
            lastMuted = m;
            if (enabled)
                moved(v, m);
        }

        property PwObjectTracker tracker: PwObjectTracker {
            objects: [watch.node]
        }

        property Connections nodeConnections: Connections {
            target: watch.node
            function onReadyChanged() {
                watch.read();
            }
        }

        property Connections audioConnections: Connections {
            target: watch.node && watch.node.audio ? watch.node.audio : null
            function onVolumeChanged() {
                watch.read();
            }
            function onMutedChanged() {
                watch.read();
            }
        }
    }

    AudioWatch {
        node: Pipewire.defaultAudioSink
        enabled: root.volumeEnabled
        onMoved: (v, m) => root.show(Osd.volumeGlyph(v, m), v, m)
    }

    AudioWatch {
        node: root.micEnabled ? Pipewire.defaultAudioSource : null
        enabled: root.micEnabled
        onMoved: (v, m) => root.show(Osd.micGlyph(m), v, m)
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

    // --- keyboard layout --------------------------------------------------------
    // Keyboard.switched fires for a keyboard that moved to another layout,
    // never for the `activelayout` burst of a config reload. Keyboard is
    // touched only while the kind is on, so with it off nothing reads devices.
    Connections {
        target: root.layoutEnabled ? Keyboard : null

        function onSwitched(layout: string): void {
            root.showCard(Osd.layoutCard(layout, Keyboard.code));
        }
    }

    // --- Caps and Num Lock --------------------------------------------------------
    // Hyprland sends no event for a lock key, and the kernel's LED class does
    // not notify its `brightness` file. The default binds.lua has a
    // non-consuming release bind on the Caps Lock and Num Lock keys that calls
    // `lockkeys()`; each call reads the main keyboard once. The first read
    // when the kind turns on is the baseline, so only a change shows.
    property var _locks: null
    property bool _lockAgain: false
    property bool _lockSeed: false
    // A seed asked for while a read runs: that read and its re-run are seeds
    // too, so turning the kind on during a read never shows a card.
    property bool _lockAgainSeed: false

    // `haseen shell ipc osd lockkeys`. With the kind off the call returns at
    // once and starts nothing.
    function lockKeys(): void {
        if (lockKeysEnabled)
            readLocks(false);
    }

    function readLocks(seed: bool): void {
        if (lockProc.running) {
            _lockAgain = true;
            if (seed) {
                _lockSeed = true;
                _lockAgainSeed = true;
            }
            return;
        }
        _lockSeed = seed;
        lockProc.running = true;
    }

    function locksRead(text: string): void {
        const now = Keyboard.lockState(text);
        if (!now)
            return;
        const changes = _lockSeed ? [] : Osd.lockChanges(_locks, now);
        _locks = now;
        if (changes.length > 0)
            showCard(Osd.lockCard(changes[0]));
    }

    // The binds call `lockkeys` only while this flag exists (binds.lua), so
    // with the kind off a Caps or Num Lock press starts no IPC client. One
    // process per setting change and at start and exit; never per key.
    readonly property string lockFlag: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/haseen/osd-lockkeys"

    function flagLockKeys(on: bool): void {
        Quickshell.execDetached(on ? ["sh", "-c", "mkdir -p -- \"${1%/*}\" && : >\"$1\"", "sh", lockFlag] : ["rm", "-f", "--", lockFlag]);
    }

    onLockKeysEnabledChanged: {
        _locks = null;
        flagLockKeys(lockKeysEnabled);
        if (lockKeysEnabled)
            readLocks(true);
    }
    Component.onCompleted: {
        flagLockKeys(lockKeysEnabled);
        if (lockKeysEnabled)
            readLocks(true);
    }
    Component.onDestruction: {
        if (lockKeysEnabled)
            flagLockKeys(false);
    }

    Process {
        id: lockProc

        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: root.locksRead(text)
        }
        onExited: {
            if (root._lockAgain) {
                root._lockAgain = false;
                root._lockSeed = root._lockAgainSeed;
                root._lockAgainSeed = false;
                running = true;
            }
        }
    }

    // Architecture 5.5.
    IpcHandler {
        target: "osd"

        function lockkeys(): void {
            root.lockKeys();
        }

        function state(): string {
            return JSON.stringify({
                shown: root.shown,
                card: root.card,
                kinds: root.kinds,
                locks: root._locks
            });
        }
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
        source: Qt.resolvedUrl("CardWindow.qml")
        onItemChanged: if (item)
            item.service = root
    }
}
