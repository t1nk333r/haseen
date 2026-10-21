import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// The Wooting keyboard's active profile in the bar (plan 099), adapted from
// the owner's t1nk33r.wooting Panel.qml (MIT, Copyright (c) 2026 t1nk33r):
// a keyboard glyph and the profile's short name (`1 Typing Profile` reads
// `Typing`, Model.shortName). A click opens the panel, which lists the stored
// profiles and switches them. The label never predicts: it moves when
// wootingd reports the change, which also covers a switch made with the
// keyboard's own Fn shortcuts. With no keyboard there is no daemon and, by
// default, no widget: it takes no room and waits for the socket through
// inotify (WootingLink), never a poll. Off by default.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // Coerced, not compared: a string writer stores "false" and "8".
    readonly property bool showName: Model.boolSetting(settings.showName, true)
    readonly property bool hideWhenAbsent: Model.boolSetting(settings.hideWhenAbsent, true)
    readonly property int nameMaxChars: Model.numSetting(settings.nameMaxChars, Model.NAME_MAX_CHARS)
    // The daemon's view (Model.emptyState); not `state`, which is Item's.
    property var keyboard: Model.emptyState()
    readonly property bool shown: Model.shouldShow(keyboard, hideWhenAbsent)

    visible: shown
    implicitWidth: shown ? contentWidth : 0
    glyph: "\u{F030C}"
    text: showName ? Model.barLabel(keyboard, true, nameMaxChars) : ""

    onClicked: button => {
        if (button === Qt.LeftButton || button === Qt.RightButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }

    WootingLink {
        id: link

        hello: "subscribe\n"
        onUp: root.keyboard = Model.withConnected(root.keyboard, true)
        onDown: root.keyboard = Model.disconnected(root.keyboard)
        onReceived: line => {
            const message = Model.parseLine(line);
            if (message)
                root.keyboard = Model.applyMessage(root.keyboard, message);
        }
    }
}
