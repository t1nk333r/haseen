import QtQuick
import Quickshell
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.wooting's panel (plan 099), adapted from the owner's t1nk33r.wooting
// (MIT, Copyright (c) 2026 t1nk33r): the bar popup's profile list (Panel.qml
// PopupCard) and, one click further, its keyboard layout view (LayoutPanel.qml),
// in the one lazy panel haseen gives a plugin. Only profiles that hold stored
// data are listed (wootingd refuses the empty ones); a click switches and
// closes the panel, and the bar's label moves when the keyboard confirms.
// The drawing and its key-travel stream exist only while it is shown.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string pid: String(Quickshell.processId)
    // The daemon's view (Model.emptyState); not `state`, which is Item's.
    property var keyboard: Model.emptyState()
    property string modelName: ""
    property bool showLayout: false
    // The keyboard drawing while it is shown (Board.qml), else null.
    readonly property alias layoutView: board.item

    width: Math.max(Theme.fontSize * 24, board.item ? board.item.implicitWidth : 0)
    spacing: Theme.gap

    // No prediction: the bar and this panel move when wootingd reports the
    // switch on its subscription.
    function choose(slot: int): void {
        if (link.send("profile set " + slot))
            Quickshell.execDetached(["qs", "ipc", "--pid", pid, "call", "panel", "close"]);
        else
            root.keyboard = Model.applyMessage(root.keyboard, {
                ok: false,
                error: link.hint || I18n.mark("not connected")
            });
    }

    WootingLink {
        id: link

        hello: "subscribe\n"
        onUp: root.keyboard = Model.withConnected(root.keyboard, true)
        onDown: root.keyboard = Model.disconnected(root.keyboard)
        onReceived: line => {
            const message = Model.parseLine(line);
            if (!message)
                return;
            root.keyboard = Model.applyMessage(root.keyboard, message);
            if (typeof message.model === "string")
                root.modelName = message.model;
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Keyboard profile")
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: root.keyboard.present ? (root.modelName || "Wooting") + (root.keyboard.firmware ? " · v" + root.keyboard.firmware : "") : ""
            color: Theme.subtle(Theme.surface)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: root.width
        visible: !root.keyboard.present
        wrapMode: Text.WordWrap
        text: {
            if (link.connected)
                return I18n.tr("Plug in a Wooting keyboard.");
            const hint = I18n.tr(link.hint);
            return hint.charAt(0).toUpperCase() + hint.slice(1) + ".";
        }
        color: Theme.subtle(Theme.surface)
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: root.keyboard.present ? root.keyboard.profiles : []

        delegate: ProfileRow {
            required property var modelData

            width: root.width
            // A slot without stored metadata carries wootingd's positional label.
            text: modelData.name
            active: modelData.slot === root.keyboard.active
            onClicked: root.choose(modelData.slot)
        }
    }

    Text {
        width: root.width
        visible: root.keyboard.error !== ""
        wrapMode: Text.WordWrap
        // The daemon's own words (an empty slot, a refused switch); the
        // model's and the link's own fallbacks are shown translated.
        textFormat: Text.PlainText
        text: I18n.tr(root.keyboard.error)
        color: Theme.urgent
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    Row {
        // Full width, so a mirrored panel (plan 109) starts the row on the right.
        width: parent.width
        spacing: Theme.gap

        Pill {
            text: I18n.tr("Keyboard layout")
            active: root.showLayout
            onClicked: root.showLayout = !root.showLayout
        }
    }

    Loader {
        id: board

        active: root.showLayout
        visible: active
        sourceComponent: Board {}
    }
}
