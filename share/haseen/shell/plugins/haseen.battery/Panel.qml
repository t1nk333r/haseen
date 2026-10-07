import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// haseen.battery panel (plan 076): charge, state, time to empty or full,
// power draw, energy, health and cycles; the power profile
// (power-profiles-daemon, `haseen powerprofile set`, remembered per power
// source) and the charge limit (`haseen battery limit`, which asks for the
// password in a floating terminal); a link to the Setup menu. The device's
// values are UPower property bindings; `haseen battery status --shell`
// (cycles, the limit window, whether the limit holds the charge) and
// `haseen powerprofile list` run when the panel opens and again when the
// state or the profile changes. The host loads the panel only while it is
// open. Open with a click on the bar battery or
// `haseen shell ipc panel toggle haseen.battery`.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    readonly property string pid: String(Quickshell.processId)

    readonly property var device: UPower.displayDevice
    readonly property bool present: device !== null && device.ready && device.isLaptopBattery && device.isPresent
    readonly property int percent: present ? Math.round(device.percentage * 100) : 0
    readonly property int deviceState: present ? device.state : 0
    readonly property bool charging: present && Model.isCharging(deviceState)

    property var status: ({})
    property var profiles: []
    property string pendingProfile: ""
    readonly property string activeProfile: Model.profileName(PowerProfiles.profile)
    readonly property int limit: Model.limitEnd(status.threshold)
    readonly property var details: [
        { label: "Power draw", value: present ? Model.rate(device.changeRate) : "" },
        { label: "Energy", value: present ? Model.energy(device.energy, device.energyCapacity) : "" },
        { label: "Health", value: present ? Model.health(device.healthPercentage, device.healthSupported) : "" },
        { label: "Cycles", value: status.cycles && status.cycles !== "0" ? status.cycles : "" }
    ].filter(d => d.value !== "")

    width: Theme.fontSize * 24
    spacing: Theme.gap

    onDeviceStateChanged: {
        if (!statusProc.running)
            statusProc.running = true;
    }
    onActiveProfileChanged: pendingProfile = ""

    function setProfile(name: string): void {
        if (!name || name === activeProfile || profileSet.running)
            return;
        pendingProfile = name;
        profileSet.command = [binDir + "/haseen-powerprofile-set", "autodetect", name];
        profileSet.running = true;
    }

    // The limit needs root: the command opens its own floating terminal for
    // the password, so the panel gets out of its way.
    function setLimit(end: int): void {
        if (end === limit)
            return;
        Apps.launch([binDir + "/haseen-battery-limit"].concat(Model.limitArgs(end)));
        Quickshell.execDetached(["qs", "ipc", "--pid", pid, "call", "panel", "close"]);
    }

    function openSetup(): void {
        Quickshell.execDetached(["sh", "-c", "qs ipc --pid \"$1\" call panel close; exec qs ipc --pid \"$1\" call menu toggle setup", "sh", pid]);
    }

    Process {
        id: statusProc

        running: true
        command: [root.binDir + "/haseen-battery-status", "--shell"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.status = Model.parseStatus(text)
        }
    }

    Process {
        id: profilesProc

        running: true
        command: [root.binDir + "/haseen-powerprofile-list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.profiles = Model.profiles(text)
        }
    }

    Process {
        id: profileSet

        onExited: exitCode => {
            if (exitCode !== 0)
                root.pendingProfile = "";
        }
    }

    component SectionLabel: Text {
        width: root.width
        topPadding: Theme.gap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    // A bordered choice in a row: `active` is the value in force (filled),
    // `pending` the one asked for while the change is in flight.
    component Choice: Item {
        id: choice

        property string label
        property bool active: false
        property bool pending: false

        signal clicked

        implicitWidth: choiceText.implicitWidth + Theme.gap * 3
        implicitHeight: Math.round(Theme.fontSize * 2.1)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: choice.active ? Theme.accent : choiceMouse.containsMouse ? Theme.surfaceAlt : "transparent"
            border.color: choice.active || choice.pending || choiceMouse.containsMouse ? Theme.accent : Theme.border
            border.width: Theme.borderWidth
        }

        Text {
            id: choiceText

            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: choice.label
            color: choice.active ? Theme.accentFg : Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.bold: choice.active || choice.pending
        }

        MouseArea {
            id: choiceMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: choice.clicked()
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Battery"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.present
            text: Model.stateLabel(root.deviceState, root.status.state === "holding", root.status.threshold || "")
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    Text {
        width: parent.width
        visible: !root.present
        wrapMode: Text.WordWrap
        text: "No battery (UPower reports none)."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Row {
        visible: root.present
        spacing: Theme.gap * 2

        Glyph {
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.glyph(root.percent, root.charging)
            color: root.charging ? Theme.success : Theme.foreground
            font.pixelSize: Theme.fontSize * 3
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter

            Text {
                text: root.percent + "%"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize * 2
                font.bold: true
            }

            Text {
                visible: text !== ""
                text: root.present ? Model.timeLine(root.deviceState, root.device.timeToEmpty, root.device.timeToFull) : ""
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    Repeater {
        model: root.details

        delegate: Item {
            required property var modelData

            width: root.width
            height: Math.round(Theme.fontSize * 1.8)

            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: parent.modelData.label
                color: Theme.muted
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: parent.modelData.value
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }
        }
    }

    SectionLabel {
        visible: root.profiles.length > 0
        text: "Power profile"
    }

    Row {
        visible: root.profiles.length > 0
        spacing: Theme.gap

        Repeater {
            model: root.profiles

            delegate: Choice {
                required property string modelData

                label: Model.profileLabel(modelData)
                active: modelData === root.activeProfile
                pending: modelData === root.pendingProfile
                onClicked: root.setProfile(modelData)
            }
        }
    }

    SectionLabel {
        visible: root.limit >= 0
        text: "Charge limit"
    }

    Row {
        visible: root.limit >= 0
        spacing: Theme.gap

        Repeater {
            model: Model.limitChoices(root.limit)

            delegate: Choice {
                required property int modelData

                label: Model.limitLabel(modelData)
                active: modelData === root.limit
                onClicked: root.setLimit(modelData)
            }
        }
    }

    Item {
        width: parent.width
        height: Math.round(Theme.fontSize * 2.4)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surfaceAlt
            visible: setupMouse.containsMouse
        }

        Glyph {
            id: setupGlyph

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            glyph: "\ue615"
        }

        Text {
            anchors.left: setupGlyph.right
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: "System settings"
            color: Theme.foreground
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize
        }

        MouseArea {
            id: setupMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openSetup()
        }
    }
}
