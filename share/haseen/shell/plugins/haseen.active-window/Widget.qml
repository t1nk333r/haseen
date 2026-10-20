import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Haseen
import qs.Haseen.Widgets
import "Title.js" as Title

// The focused window's title in the bar (plan 095), adopted from the owner's
// t1nk33r.active-window, a fork of Omarchy's active-window widget
// (ActiveWindow.qml, MIT, Copyright (c) David Heinemeier Hansson). The
// toplevel comes from the compositor's foreign-toplevel protocol
// (Quickshell's ToplevelManager), an event, never a poll. A long title keeps
// its head and tail around a middle ellipsis within `maxChars` characters;
// `maxWidth` (pixels, 0 = none) is an optional clamp for a narrow bar, with
// an end ellipsis as its backstop. No window, or a vertical bar (a title does
// not read sideways), takes no room.
//
// A left click focuses the window; a middle or right click closes it, as in
// the owner's fork. Off by default.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // Writable so a test can hand in a stand-in toplevel.
    property var toplevel: ToplevelManager.activeToplevel
    readonly property string title: Title.titleOf(toplevel)
    readonly property bool active: title !== "" && !vertical

    visible: active
    implicitWidth: active ? contentWidth : 0
    text: Title.label(title, settings.maxChars)
    maxTextWidth: Math.max(0, Number(settings.maxWidth) || 0)

    onClicked: button => {
        if (!root.toplevel)
            return;
        if (button === Qt.LeftButton)
            root.toplevel.activate();
        else
            root.toplevel.close();
    }
}
