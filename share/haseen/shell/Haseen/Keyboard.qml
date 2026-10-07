pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Keyboard.js" as Model

// The keyboard layout as Hyprland reports it (plans 079, 080), shared by the
// haseen.osd layout card and the haseen.kblayout bar widget. One
// `hyprctl -j devices` read when the first user appears and one after each
// config reload (the layout list may have changed); everything else is the
// socket2 `activelayout` event, plus one read after a switch the event alone
// cannot place in the list (a variant, or another keyboard). Nothing polls.
Singleton {
    id: root

    // The keyboard Hyprland marks main at the last read.
    property string mainKeyboard: ""
    // [{layout, variant, code}] of the main keyboard ("us,ara" -> two).
    property var layouts: []
    // active_layout_index at the last read, then the entry a switch went to;
    // -1 before the first read and while a switch waits for its read.
    property int index: -1
    // The description of the active layout ("Arabic"): the main keyboard at
    // the last read, then the last keyboard that switched.
    property string layout: ""
    // The list's code for the active entry, so the bar, the list and the OSD
    // agree ("TJ" for Tajik, not "TA" from its description); the
    // description's code only while the entry is not known.
    readonly property string code: index >= 0 && index < layouts.length ? layouts[index].code : Model.codeFromName(layout)
    readonly property bool ready: _read

    // Each keyboard's layout as last seen, so a reload or a new keyboard (both
    // send `activelayout`) is not taken for a switch.
    property var _known: ({})
    property bool _read: false
    property bool _again: false

    // A keyboard moved to another layout (not a reload, not a hotplug).
    signal switched(string layout)

    function refresh(): void {
        if (devices.running) {
            _again = true;
            return;
        }
        devices.running = true;
    }

    // Hyprland's `main` is the keyboard the devices list marks main
    // (HyprCtl.cpp switchXKBLayoutRequest), so this follows the keyboard
    // typed on last, not the one read at startup.
    function next(): void {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
    }

    function select(i: int): void {
        if (i >= 0 && i < layouts.length)
            Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", String(i)]);
    }

    // The lock-key reader over one `hyprctl -j devices` output: {caps, num}
    // of the main keyboard, or null.
    function lockState(text: string): var {
        return Model.lockState(text);
    }

    // "ara" -> "Arabic", for the layout list.
    function layoutName(name: string): string {
        return Model.layoutName(name);
    }

    function applyDevices(text: string): void {
        const d = Model.readDevices(text);
        // A failed or empty read (a compositor hiccup during a reload) keeps
        // what the last good one said, so the bar code does not vanish.
        if (d.main === "" && _read)
            return;
        mainKeyboard = d.main;
        layouts = d.layouts;
        index = d.index;
        _known = Object.assign({}, _known, d.known);
        if (d.layout !== "")
            layout = d.layout;
        _read = true;
    }

    function layoutEvent(data: string): void {
        const r = Model.layoutEvent(_known, data);
        _known = r.known;
        if (!r.switched)
            return;
        layout = r.layout;
        index = r.keyboard === mainKeyboard ? Model.indexOf(layouts, r.layout) : -1;
        if (index < 0)
            refresh();
        switched(r.layout);
    }

    Component.onCompleted: refresh()

    Process {
        id: devices

        command: ["hyprctl", "-j", "devices"]
        stdout: StdioCollector {
            onStreamFinished: root.applyDevices(text)
        }
        onExited: {
            if (root._again) {
                root._again = false;
                running = true;
            }
        }
    }

    Connections {
        target: Hyprland

        function onRawEvent(event: var): void {
            if (event.name === "activelayout")
                root.layoutEvent(event.data);
            else if (event.name === "configreloaded")
                root.refresh();
        }
    }
}
