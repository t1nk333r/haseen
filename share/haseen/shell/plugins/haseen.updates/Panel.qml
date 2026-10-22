import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.updates' list (plan 095), opened by a right click on the bar count.
// It stands in for the original widget's tooltip: the pending packages
// ("name old -> new", AUR ones marked), at most `listLines` of them, and why
// a check was incomplete. Opening it asks `haseen update check` once, which
// answers from its cache when a check ran in the last minute; Check now
// forces a new one; Update runs `haseen update` in its own floating terminal
// (Apps.launch) and closes the panel.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property string pid: String(Quickshell.processId)
    property var result: null
    readonly property int listLines: typeof settings.listLines === "number" ? settings.listLines : 20

    width: Theme.fontSize * 26
    spacing: Theme.gap

    function check(force: bool): void {
        if (checkProc.running)
            return;
        checkProc.command = [binDir + "/haseen-update-check"].concat(force ? ["--force"] : []);
        checkProc.running = true;
    }

    function update(): void {
        Apps.launch([binDir + "/haseen-update"]);
        Quickshell.execDetached(["qs", "ipc", "--pid", pid, "call", "panel", "close"]);
    }

    Component.onCompleted: check(false)

    Process {
        id: checkProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.result = Model.parse(text)
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("Package updates")
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: {
                const n = Model.total(root.result);
                return n > 0 ? I18n.tn("%1 update · repo %2 · AUR %3", "%1 updates · repo %2 · AUR %3", n, root.result.repo, root.result.aur) : I18n.tr(Model.summary(root.result, checkProc.running));
            }
            color: Theme.subtle(Theme.surface)
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Repeater {
        // The check's own messages; one haseen knows is shown translated.
        model: root.result !== null ? root.result.errors.map(e => I18n.tr(e)) : []

        delegate: Text {
            required property string modelData

            width: root.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: modelData
            color: Theme.urgent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Repeater {
        model: Model.listed(root.result, root.listLines, I18n.tr)

        delegate: Text {
            required property string modelData

            width: root.width
            elide: Text.ElideRight
            textFormat: Text.PlainText
            text: modelData
            color: Theme.foreground
            font.family: Theme.fontMono
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Row {
        // Full width, so a mirrored panel (plan 109) starts the row on the right.
        width: parent.width
        spacing: Theme.gap

        Pill {
            text: checkProc.running ? I18n.tr("Checking…") : I18n.tr("Check now")
            busy: checkProc.running
            onClicked: root.check(true)
        }

        Pill {
            text: I18n.tr("Update")
            active: Model.total(root.result) > 0
            onClicked: root.update()
        }
    }
}
