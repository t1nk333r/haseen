import QtQuick
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// Bluetooth panel: adapter power, paired devices (connect / disconnect,
// battery when the device reports it) and nearby devices to pair. Discovery
// runs only while this panel is open and the adapter is on.
// Pairing uses BlueZ's default agent, so devices that need a PIN typed on
// the host are not covered here. Open with
// `haseen shell ipc panel toggle haseen.bluetooth` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var all: adapter ? adapter.devices.values : []
    readonly property var paired: all.filter(d => d.paired || d.bonded).sort((a, b) => (b.connected - a.connected) || label(a).localeCompare(label(b)))
    // Unpaired devices with a human name; BLE beacons announcing only an
    // address are noise in a pairing list.
    readonly property var nearby: all.filter(d => !d.paired && !d.bonded && hasName(d)).sort((a, b) => label(a).localeCompare(label(b))).slice(0, 12)

    function label(d: var): string {
        return String(d.name || d.deviceName || d.address || "").trim();
    }

    function hasName(d: var): bool {
        const l = String(d.name || d.deviceName || "").trim();
        return l !== "" && !/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(l);
    }

    function deviceGlyph(d: var): string {
        const icon = String(d.icon || "");
        if (/headset|headphone/.test(icon))
            return "\u{F02CB}";
        if (/audio|speaker/.test(icon))
            return "\u{F04C3}";
        if (/mouse/.test(icon))
            return "\u{F037D}";
        if (/keyboard/.test(icon))
            return "\u{F030C}";
        if (/gaming|joystick/.test(icon))
            return "\u{F0297}";
        if (/phone/.test(icon))
            return "\u{F011C}";
        if (/computer/.test(icon))
            return "\u{F0322}";
        return "\u{F00AF}";
    }

    function status(d: var): string {
        if (d.pairing)
            return "Pairing…";
        switch (d.state) {
        case BluetoothDeviceState.Connecting:
            return "Connecting…";
        case BluetoothDeviceState.Disconnecting:
            return "Disconnecting…";
        case BluetoothDeviceState.Connected:
            return d.batteryAvailable ? "Connected · " + Math.round(d.battery * 100) + "%" : "Connected";
        }
        return d.paired ? "Paired" : "";
    }

    width: Theme.fontSize * 24
    spacing: Theme.gap

    // Discovery only while open: started when the panel opens or the adapter
    // turns on, stopped when the panel closes. Explicit because a Binding
    // does not restore the old value when it is destroyed.
    onOnChanged: {
        if (on)
            adapter.discovering = true;
    }
    Component.onCompleted: {
        if (on)
            adapter.discovering = true;
    }
    Component.onDestruction: {
        if (adapter && adapter.discovering)
            adapter.discovering = false;
    }

    // Test hook (settings.debugIpc): read state without a keyboard. It has
    // no mutating functions: smoke runs must never touch real radios.
    IpcHandler {
        target: "haseen.bluetooth"
        enabled: root.settings.debugIpc === true

        function state(): string {
            return JSON.stringify({
                adapter: root.adapter ? root.adapter.name : null,
                enabled: root.on,
                discovering: root.adapter ? root.adapter.discovering : false,
                paired: root.paired.map(d => ({
                            name: root.label(d),
                            connected: d.connected,
                            battery: d.batteryAvailable ? d.battery : null
                        })),
                nearby: root.nearby.length
            });
        }
    }

    Item {
        width: parent.width
        height: Theme.fontSize * 2.2

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Bluetooth"
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize + 2
        }

        BarButton {
            anchors.right: parent.right
            height: parent.height
            visible: root.adapter !== null
            glyph: "\uf011"
            text: root.on ? "On" : "Off"
            color: root.on ? Theme.foreground : Theme.muted
            highlighted: root.on
            onClicked: root.adapter.enabled = !root.adapter.enabled
        }
    }

    Text {
        width: parent.width
        visible: !root.on
        wrapMode: Text.WordWrap
        text: root.adapter === null ? "No Bluetooth adapter." : root.adapter.state === BluetoothAdapterState.Blocked ? "Bluetooth is blocked (rfkill)." : "Bluetooth is off."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    component SectionLabel: Text {
        width: root.width
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    component DeviceRow: Item {
        id: row

        required property var device
        property string action: ""

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
            onClicked: row.activated()
        }

        Glyph {
            id: icon

            anchors.left: parent.left
            anchors.leftMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.fontSize * 2
            glyph: root.deviceGlyph(row.device)
            color: row.device.connected ? Theme.accent : Theme.foreground
        }

        Column {
            anchors.left: icon.right
            anchors.leftMargin: Theme.gap
            anchors.right: act.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter

            Text {
                width: parent.width
                text: root.label(row.device)
                color: Theme.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
            }

            Text {
                width: parent.width
                visible: text !== ""
                text: root.status(row.device)
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
            text: row.action
            color: Theme.accent
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }
    }

    SectionLabel {
        visible: root.on && root.paired.length > 0
        text: "Paired devices"
    }

    Repeater {
        model: root.on ? root.paired : []

        delegate: DeviceRow {
            required property var modelData

            device: modelData
            action: modelData.connected ? "Disconnect" : "Connect"
            onActivated: modelData.connected ? modelData.disconnect() : modelData.connect()
        }
    }

    SectionLabel {
        visible: root.on
        text: root.adapter && root.adapter.discovering ? "Nearby devices (scanning…)" : "Nearby devices"
    }

    Text {
        width: parent.width
        visible: root.on && root.nearby.length === 0
        text: "Nothing found yet."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    Repeater {
        model: root.on ? root.nearby : []

        delegate: DeviceRow {
            required property var modelData

            device: modelData
            action: modelData.pairing ? "Cancel" : "Pair"
            onActivated: {
                if (modelData.pairing) {
                    modelData.cancelPair();
                    return;
                }
                // Trusted first, so the device reconnects on its own later.
                modelData.trusted = true;
                modelData.pair();
            }
        }
    }
}
