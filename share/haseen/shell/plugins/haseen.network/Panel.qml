import QtQuick
import Quickshell.Io
import Quickshell.Networking
import qs.Haseen
import qs.Haseen.Widgets

// Network panel (Quickshell.Networking over NetworkManager D-Bus): wired
// status, a Wi-Fi on/off switch, and the Wi-Fi networks in range. Click a
// network to connect (saved and open networks connect directly; a secured
// new one asks for its password below the list), click the connected one
// to disconnect. The Wi-Fi scanner runs only while this panel is open.
// Open with `haseen shell ipc panel toggle haseen.network` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var devices: Networking.devices ? Networking.devices.values : []
    readonly property var wiredDevices: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) || null
    readonly property bool wifiOn: Networking.wifiEnabled && Networking.wifiHardwareEnabled
    readonly property var networks: wifiDevice && wifiOn ? wifiDevice.networks.values.filter(n => n.name !== "").sort((a, b) => (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength)).slice(0, maxNetworks) : []
    readonly property int maxNetworks: typeof settings.maxNetworks === "number" && settings.maxNetworks >= 1 ? Math.round(settings.maxNetworks) : 8
    // Name of the network whose password field is open, "" = none.
    property string prompting: ""
    readonly property var promptNetwork: wifiDevice && wifiOn && prompting !== "" ? wifiDevice.networks.values.find(n => n.name === prompting) || null : null
    // Last connection failure, shown under the list until the next attempt.
    property string failure: ""

    function signalGlyph(strength: real): string {
        return ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"][Math.min(4, Math.ceil(strength * 4))];
    }

    function secured(n: var): bool {
        return n.security !== WifiSecurityType.Open && n.security !== WifiSecurityType.Owe;
    }

    function activate(n: var): void {
        failure = "";
        if (n.connected) {
            prompting = "";
            n.disconnect();
        } else if (n.known || !secured(n)) {
            prompting = "";
            n.connect();
        } else {
            prompting = prompting === n.name ? "" : n.name;
        }
    }

    function status(n: var): string {
        switch (n.state) {
        case ConnectionState.Connecting:
            return "Connecting…";
        case ConnectionState.Disconnecting:
            return "Disconnecting…";
        case ConnectionState.Connected:
            return "Connected";
        }
        return n.known ? "Saved" : secured(n) ? WifiSecurityType.toString(n.security) : "Open";
    }

    function wiredStatus(d: var): string {
        if (d.connected)
            return "Connected" + (d.linkSpeed > 0 ? " · " + d.linkSpeed + " Mb/s" : "");
        if (!d.hasLink)
            return "Cable unplugged";
        return d.state === ConnectionState.Connecting ? "Connecting…" : "Disconnected";
    }

    width: Theme.fontSize * 24
    spacing: Theme.gap

    // Scanner only while open: started when the panel opens or Wi-Fi turns
    // on, stopped when the panel closes. Explicit because a Binding does not
    // restore the old value when it is destroyed.
    readonly property bool scan: wifiDevice !== null && wifiOn

    onScanChanged: {
        if (scan)
            wifiDevice.scannerEnabled = true;
    }
    Component.onCompleted: {
        if (scan)
            wifiDevice.scannerEnabled = true;
    }
    Component.onDestruction: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = false;
    }

    // Test hook (settings.debugIpc): read state and open a password row
    // without a keyboard. Nothing here connects, disconnects or toggles a
    // radio: smoke runs must never change the machine's network.
    IpcHandler {
        target: "haseen.network"
        enabled: root.settings.debugIpc === true

        function prompt(name: string): void {
            root.prompting = name;
        }

        function state(): string {
            return JSON.stringify({
                wifiEnabled: Networking.wifiEnabled,
                wifiHardwareEnabled: Networking.wifiHardwareEnabled,
                scanning: root.wifiDevice ? root.wifiDevice.scannerEnabled : false,
                prompting: root.prompting,
                wired: root.wiredDevices.map(d => ({
                            name: d.name,
                            connected: d.connected,
                            hasLink: d.hasLink
                        })),
                networks: root.networks.map(n => ({
                            name: n.name,
                            connected: n.connected,
                            known: n.known,
                            secured: root.secured(n),
                            signal: n.signalStrength
                        }))
            });
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Network"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        BarButton {
            anchors.right: parent.right
            height: parent.height
            visible: root.wifiDevice !== null
            glyph: root.wifiOn ? "\u{F0928}" : "\u{F092E}"
            text: !Networking.wifiHardwareEnabled ? "Blocked" : Networking.wifiEnabled ? "Wi-Fi on" : "Wi-Fi off"
            color: root.wifiOn ? Theme.foreground : Theme.muted
            highlighted: root.wifiOn
            onClicked: {
                if (Networking.wifiHardwareEnabled)
                    Networking.wifiEnabled = !Networking.wifiEnabled;
            }
        }
    }

    component SectionLabel: Text {
        width: root.width
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    component InfoRow: Item {
        id: info

        property string glyph
        property string title
        property string detail
        property string action
        property bool active: false
        property bool locked: false

        signal activated

        width: root.width
        height: Math.round(Theme.fontSize * 2.6)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surfaceAlt
            visible: mouse.containsMouse
        }

        MouseArea {
            id: mouse

            anchors.fill: parent
            hoverEnabled: true
            enabled: info.action !== ""
            onClicked: info.activated()
        }

        Glyph {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: info.glyph
            color: info.active ? Theme.accent : Theme.foreground
        }

        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.gap
            anchors.right: act.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: info.title + (info.locked ? "  \uf023" : "")
                color: Theme.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: info.detail
                color: Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Text {
            id: act

            anchors.right: parent.right
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            text: info.action
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    SectionLabel {
        visible: root.wiredDevices.length > 0
        text: "Wired"
    }

    Repeater {
        model: root.wiredDevices

        delegate: InfoRow {
            required property var modelData

            glyph: "\u{F0200}"
            title: modelData.network && modelData.network.name !== "" ? modelData.network.name : modelData.name
            detail: root.wiredStatus(modelData)
            active: modelData.connected
        }
    }

    SectionLabel {
        visible: root.wifiDevice !== null
        text: root.wifiOn ? "Wi-Fi networks" : "Wi-Fi"
    }

    Text {
        width: parent.width
        visible: root.wifiDevice !== null && (!root.wifiOn || root.networks.length === 0)
        text: !Networking.wifiHardwareEnabled ? "Wi-Fi is blocked by a hardware switch or rfkill." : !Networking.wifiEnabled ? "Wi-Fi is off." : "Scanning…"
        color: Theme.muted
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Text {
        width: parent.width
        visible: root.wifiDevice === null && root.wiredDevices.length === 0
        text: Networking.backend === NetworkBackendType.None ? "NetworkManager is not running." : "No network devices."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: root.networks

        delegate: InfoRow {
            id: net

            required property var modelData

            glyph: root.signalGlyph(modelData.signalStrength)
            title: modelData.name
            detail: root.status(modelData)
            active: modelData.connected
            locked: root.secured(modelData)
            action: modelData.stateChanging ? "" : modelData.connected ? "Disconnect" : "Connect"
            onActivated: root.activate(modelData)

            Connections {
                target: net.modelData

                function onConnectionFailed(reason: int): void {
                    root.failure = net.modelData.name + ": " + ConnectionFailReason.toString(reason);
                    // Wrong or missing password: ask again.
                    if (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)
                        root.prompting = net.modelData.name;
                }
            }
        }
    }

    // One password field below the list rather than inside a row: the rows
    // are rebuilt whenever a scan re-sorts them, which would drop typed text.
    Rectangle {
        width: parent.width
        height: Theme.fontSize * 2.4
        visible: root.promptNetwork !== null
        radius: Theme.radius
        color: Theme.surfaceAlt
        border.color: psk.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        onVisibleChanged: {
            psk.text = "";
            if (visible)
                psk.forceActiveFocus();
        }

        TextInput {
            id: psk

            anchors.fill: parent
            anchors.leftMargin: Theme.gap * 1.5
            anchors.rightMargin: Theme.gap * 1.5
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            color: Theme.foreground
            selectionColor: Theme.selection
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 1
            clip: true

            function submit(): void {
                const network = root.promptNetwork;
                if (text === "" || !network)
                    return;
                const key = text;
                root.failure = "";
                root.prompting = "";
                network.connectWithPsk(key);
            }

            Keys.onReturnPressed: submit()
            Keys.onEnterPressed: submit()

            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: psk.text === ""
                text: "Password for " + root.prompting + ", Enter to connect"
                color: Theme.muted
                font: psk.font
            }
        }
    }

    Text {
        width: parent.width
        visible: root.failure !== ""
        text: root.failure
        color: Theme.urgent
        wrapMode: Text.WordWrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }
}
