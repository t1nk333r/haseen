// Adapted from Omarchy shell/plugins/panels/network/Panel.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own layout on haseen widgets and theme tokens; haseen commands
// (network status/band, setup dns, test network, network portal); no keyboard
// cursor, Wi-Fi QR card or router ping; samplers at 2 s or slower. The
// captive-portal row and its re-check follow Omarchy 41a40ccc7 (#8859) and
// 3357f9059 (#16186), plan 106.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Network panel: the active connection (name, link speed, ping, traffic,
// addresses), a speed test and the Wi-Fi switch; the Wi-Fi band and DNS
// provider; then the Wi-Fi networks in range, saved ones first. Click a
// network to connect (a secured new one opens its passphrase field), the
// connected one to disconnect, the bin on a saved one to forget it. While
// NetworkManager reports a captive portal or limited connectivity, a Sign in
// row opens the browser on a fixed plain-HTTP page the portal can intercept
// (`haseen network portal`), and the panel asks NetworkManager to check again
// every 5 s while it is open; at other times nothing re-checks. Wi-Fi
// state and actions go through Quickshell.Networking (NetworkManager D-Bus);
// details, band and DNS through haseen commands sampled only while the panel
// is open, which is the only time it exists (the host loads panels lazily).
// Open with `haseen shell ipc panel toggle haseen.network` or a bar click.
Column {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    // Runs "$@" in the background and waits for it, output discarded. The
    // panel is destroyed when it closes, and that kills its processes: a
    // change in flight (band reconnect, DNS restart, 802.1X profile) must
    // outlive the bash it is waited from. Its exit code still comes back
    // while the panel stays open.
    readonly property string survive: "\"$@\" <&0 >/dev/null 2>&1 & wait \"$!\""
    readonly property int maxNetworks: typeof settings.maxNetworks === "number" && settings.maxNetworks >= 1 ? Math.round(settings.maxNetworks) : 8

    // Live details of the active route from haseen-network-status.
    property var info: ({})
    property real prevRxBytes: 0
    property real prevTxBytes: 0
    property real prevSampleTime: 0
    property string prevIface: ""
    property real downloadRate: 0
    property real uploadRate: 0
    property string pingIface: ""
    property var internetPingSamples: []
    property real internetPingLatency: -1
    property int internetPingPacketLoss: 0
    readonly property int pingHistoryWindow: 24
    readonly property int pingAverageWindow: 5
    readonly property bool hasInternetPing: Model.internetPingReadable(internetPingSamples, connectivity)
    readonly property bool hasTransferStats: info.rx_bytes !== undefined

    property int connectionPhraseIndex: 0
    readonly property var connectionPhrases: [I18n.mark("Wiring bits"), I18n.mark("Handling packets"), I18n.mark("Sorting frames"), I18n.mark("Hauling bytes"), I18n.mark("Routing crumbs"), I18n.mark("Counting collisions"), I18n.mark("Bending light")]
    readonly property string connectionPhrase: connectionPhrases[connectionPhraseIndex % connectionPhrases.length]
    // Hover text for the control under the pointer, shown in the hero;
    // translated when it is set (it lives only while the pointer stays).
    property string hint: ""

    readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
    readonly property var wifiDevice: findDevice(DeviceType.Wifi)
    readonly property var wiredDevice: findDevice(DeviceType.Wired)
    readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
    readonly property var connectedWifiNetwork: wifiNetworkObjects.find(n => n && n.connected) || null
    readonly property bool wifiOn: Networking.wifiEnabled && Networking.wifiHardwareEnabled
    readonly property string kind: Model.connectionKind(wiredDevice !== null && wiredDevice.connected, connectedWifiNetwork !== null)
    readonly property int signalStrength: connectedWifiNetwork ? Math.round((connectedWifiNetwork.signalStrength || 0) * 100) : -1
    // NetworkManager runs the HTTP check itself (a redirect or an unexpected
    // page means a portal); the panel reads its answer and never probes.
    readonly property bool connectivityChecksEnabled: networkManagerAvailable && Networking.canCheckConnectivity && Networking.connectivityCheckEnabled
    readonly property string connectivity: Model.connectivityState(kind, Networking.connectivity, {
        Portal: NetworkConnectivity.Portal,
        Limited: NetworkConnectivity.Limited,
        Full: NetworkConnectivity.Full,
        None: NetworkConnectivity.None
    }, connectivityChecksEnabled)
    readonly property bool restricted: Model.restricted(connectivity)
    // The portal is the active link's: with wired up too, not the Wi-Fi row's.
    readonly property string wifiConnectivity: kind === "wifi" ? connectivity : ""
    property bool portalOpening: false
    // The hero reads NetworkManager until the first details sample lands.
    readonly property var heroInfo: info.iface ? info : {
        type: kind === "disconnected" ? "" : kind,
        ssid: connectedWifiNetwork ? connectedWifiNetwork.name : ""
    }
    property var wifiNetworks: []
    property bool scanning: false
    readonly property bool wifiStationAvailable: wifiDevice !== null

    property string dnsProvider: ""
    property string pendingDns: ""
    // The provider a `haseen setup dns` run failed for ("" when none); the
    // note under the pills names it.
    property string dnsFailure: ""

    // Wi-Fi band from haseen-network-band: `bandCurrent` is the band in use,
    // `bandSelected` the pinned one ("auto" when nothing is pinned).
    property string bandCurrent: ""
    property string bandSelected: "auto"
    property var bandAvailable: []
    property string pendingBand: ""
    // The band a pin failed for ("" when none); the note names it.
    property string bandFailure: ""
    readonly property bool bandBusy: pendingBand !== ""
    // While a change is in flight, show what was asked for.
    readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
    readonly property bool bandPinned: bandEffective !== "auto"
    // Worth showing with a real choice, or with a pin in force (else the pin
    // could not be cleared here). bandBusy keeps it through the reconnect.
    readonly property bool canSelectBand: (heroInfo.type === "wifi" || bandBusy) && (bandAvailable.length > 1 || bandPinned)
    readonly property bool bandPillsVisible: canSelectBand && bandPinned

    // Per-row action state. actionSsid/actionKind: the row whose action runs
    // ("connect" | "disconnect" | "forget"); passwordSsid: the row whose
    // passphrase field is open, kept across scans so typing is not lost.
    property string actionSsid: ""
    property string actionKind: ""
    property string failureSsid: ""
    property string failureReason: ""
    property string passwordSsid: ""
    property string passwordText: ""
    property string identityText: ""
    readonly property bool busy: actionKind !== ""

    // failureReason stays English (Model.js and the marks below) and is
    // translated where a row shows it.
    // ConnectionFailReason as a plain object so Model.js stays pure.
    readonly property var connectionFailReasons: ({
            NoSecrets: ConnectionFailReason.NoSecrets,
            WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
            WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
            WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
            WifiClientFailed: ConnectionFailReason.WifiClientFailed
        })

    width: Theme.fontSize * 26
    spacing: Theme.gap * 1.5

    // Prefer a connected device: a machine can have an idle onboard port
    // beside the adapter in use.
    function findDevice(type: int): var {
        let fallback = null;
        for (const device of networkDevices) {
            if (!device || device.type !== type)
                continue;
            if (device.connected)
                return device;
            if (!fallback)
                fallback = device;
        }
        return fallback;
    }

    function networkForSsid(ssid: string): var {
        return wifiNetworkObjects.find(n => n && n.name === ssid) || null;
    }

    function requiresCredentials(security: var): bool {
        return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe);
    }

    function isEnterprise(security: var): bool {
        return security === WifiSecurityType.Wpa2Eap || security === WifiSecurityType.WpaEap;
    }

    // 802.1X kinds the identity/password (PEAP) prompt cannot set up: Suite-B
    // needs EAP-TLS certificates, LEAP and dynamic WEP their own key setup.
    // A passphrase prompt would only end in NetworkManager refusing it.
    function needsFullSetup(security: var): bool {
        return security === WifiSecurityType.Wpa3SuiteB192 || security === WifiSecurityType.Leap || security === WifiSecurityType.DynamicWep;
    }

    // Rows are rebuilt only when something in them changed, so an
    // unrelated NetworkManager signal does not reset an open prompt.
    function syncWifiNetworks(): void {
        for (const network of wifiNetworkObjects)
            checkActionCompletion(network);
        const rows = Model.wifiRows(wifiNetworkObjects, maxNetworks);
        if (JSON.stringify(rows) !== JSON.stringify(wifiNetworks))
            wifiNetworks = rows;
        scanning = false;
    }

    // Toggling the scanner off and on forces a fresh scan; deferred past the
    // first frame so opening the panel does not stall on the AP flood.
    function refresh(scanWifi: bool): void {
        if (!detailsProc.running)
            detailsProc.running = true;
        if (!dnsProc.running)
            dnsProc.running = true;
        if (!bandProc.running)
            bandProc.running = true;
        if (wifiDevice && wifiOn) {
            if (scanWifi) {
                scanning = true;
                wifiDevice.scannerEnabled = false;
                scanRestart.restart();
            } else {
                wifiDevice.scannerEnabled = true;
            }
        }
        syncWifiNetworks();
    }

    function toggleWifi(): void {
        if (!networkManagerAvailable || !Networking.wifiHardwareEnabled)
            return;
        Networking.wifiEnabled = !Networking.wifiEnabled;
        Qt.callLater(() => root.refresh(true));
    }

    function updateDetails(raw: string): void {
        const next = Model.parseKeyValue(raw);
        // A band change drops the route for a moment; keep the last good
        // sample instead of blanking every row mid-reconnect.
        if (bandBusy && !next.iface)
            return;
        info = next;
        const t = Model.throughputState({
            prevIface: prevIface,
            prevRxBytes: prevRxBytes,
            prevTxBytes: prevTxBytes,
            prevSampleTime: prevSampleTime,
            downloadRate: downloadRate,
            uploadRate: uploadRate
        }, next, Date.now() / 1000);
        prevIface = t.prevIface;
        prevRxBytes = t.prevRxBytes;
        prevTxBytes = t.prevTxBytes;
        prevSampleTime = t.prevSampleTime;
        downloadRate = t.downloadRate;
        uploadRate = t.uploadRate;
        const p = Model.pingLatencyState({
            pingIface: pingIface,
            internetPingSamples: internetPingSamples
        }, next, pingHistoryWindow, pingAverageWindow);
        pingIface = p.pingIface;
        internetPingSamples = p.internetPingSamples;
        internetPingLatency = p.internetPingLatency;
        internetPingPacketLoss = p.internetPingPacketLoss;
    }

    function updateBand(raw: string): void {
        const status = Model.parseBandStatus(raw);
        // Mid-reconnect there is no station and the command prints nothing.
        if (bandBusy && status.available.length === 0)
            return;
        bandCurrent = status.band;
        bandSelected = status.selected;
        bandAvailable = status.available;
    }

    // The hover text for a band switch or pill.
    function bandHint(band: string): string {
        if (band === "auto")
            return I18n.tr("Let Wi-Fi pick the band");
        return band ? I18n.tr("Stay on %1", I18n.tr(Model.bandLabel(band))) : "";
    }

    // Pinning reassociates; the panel stays open so the rows above show it.
    function setBand(band: string): void {
        if (!band || bandSet.running)
            return;
        bandFailure = "";
        pendingBand = band;
        bandSet.command = ["bash", "-c", survive, "bash", binDir + "/haseen-network-band", band];
        bandSet.running = true;
    }

    // Switching Automatic off pins the band the radio is already on.
    function toggleBandAuto(): void {
        if (bandSelected !== "auto")
            setBand("auto");
        else if (bandCurrent !== "")
            setBand(bandCurrent);
    }

    // `haseen setup dns`, as the menu runs it; custom asks for servers in a
    // floating terminal of its own.
    function setDns(provider: string): void {
        if (!provider || dnsSet.running)
            return;
        dnsFailure = "";
        pendingDns = provider;
        dnsSet.command = ["bash", "-c", survive, "bash", binDir + "/haseen-setup-dns", provider];
        dnsSet.running = true;
    }

    // One check now; NetworkManager's answer arrives as a property change.
    function checkConnectivity(): void {
        if (connectivityChecksEnabled && kind !== "disconnected")
            Networking.checkConnectivity();
    }

    // Explicit click only. The command opens the fixed sign-in page in the
    // browser (never a URL the network supplied) and asks NetworkManager to
    // check again every few seconds until the sign-in goes through, for at
    // most 5 minutes; it runs in its own scope, so closing the panel keeps it.
    function signIn(): void {
        if (!restricted || portalOpening)
            return;
        portalOpening = true;
        Apps.launch([binDir + "/haseen-network-portal"]);
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    function runSpeedTest(): void {
        Apps.launch([binDir + "/haseen-test-network"]);
        Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "close"]);
    }

    function copy(value: string): void {
        if (value)
            Quickshell.execDetached(["wl-copy", "--", value]);
    }

    function openPasswordPrompt(ssid: string): void {
        if (passwordSsid !== ssid) {
            passwordText = "";
            identityText = "";
        }
        passwordSsid = ssid;
    }

    function cancelPasswordPrompt(): void {
        passwordSsid = "";
        passwordText = "";
        identityText = "";
    }

    function runNetworkAction(kind: string, network: var, callback: var): void {
        if (actionKind !== "" || !network)
            return;
        actionSsid = network.name || "";
        actionKind = kind;
        failureSsid = "";
        failureReason = "";
        callback(network);
        // Safety net when NetworkManager never reports back.
        actionTimeout.restart();
    }

    function clearNetworkAction(): void {
        actionTimeout.stop();
        if (actionKind === "connect")
            cancelPasswordPrompt();
        failureSsid = "";
        failureReason = "";
        actionSsid = "";
        actionKind = "";
        refresh(false);
    }

    function failNetworkAction(network: var, reason: int): void {
        if (!network || actionKind === "" || actionSsid !== (network.name || ""))
            return;
        actionTimeout.stop();
        failureSsid = actionSsid;
        failureReason = Model.networkFailureReason(reason, requiresCredentials(network.security), connectionFailReasons);
        actionSsid = "";
        actionKind = "";
        refresh(false);
    }

    function checkActionCompletion(network: var): void {
        if (!network || actionKind === "" || actionSsid !== (network.name || ""))
            return;
        if (actionKind === "connect" && network.connected)
            clearNetworkAction();
        else if (actionKind === "disconnect" && !network.connected && !network.stateChanging)
            clearNetworkAction();
        else if (actionKind === "forget" && !network.known && !network.stateChanging)
            clearNetworkAction();
    }

    function activateRow(row: var): void {
        if (busy || !row)
            return;
        const network = networkForSsid(row.ssid);
        // A row left stale by scan churn does nothing.
        if (!network)
            return;
        switch (Model.rowAction(row, requiresCredentials(row.security))) {
        case "disconnect":
            runNetworkAction("disconnect", network, n => n.disconnect());
            break;
        case "prompt":
            if (needsFullSetup(row.security)) {
                failureSsid = row.ssid;
                failureReason = I18n.mark("Set this network up in nm-connection-editor");
                break;
            }
            openPasswordPrompt(row.ssid);
            break;
        case "connect":
            runNetworkAction("connect", network, n => n.connect());
            break;
        }
    }

    function forgetRow(row: var): void {
        runNetworkAction("forget", row ? networkForSsid(row.ssid) : null, n => n.forget());
    }

    function submitCredentials(row: var): void {
        if (busy || !row || passwordText.length === 0)
            return;
        const passphrase = passwordText;
        if (!isEnterprise(row.security)) {
            runNetworkAction("connect", networkForSsid(row.ssid), n => n.connectWithPsk(passphrase));
            return;
        }
        if (identityText.length === 0)
            return;
        const identity = identityText;
        runNetworkAction("connect", networkForSsid(row.ssid), () => {
            enterpriseConnect.secret = passphrase;
            enterpriseConnect.command = ["bash", "-c", root.survive, "bash", "bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", row.ssid, identity];
            enterpriseConnect.running = true;
        });
    }

    onWifiDeviceChanged: refresh(false)
    onWifiNetworkObjectsChanged: syncWifiNetworks()
    onMaxNetworksChanged: syncWifiNetworks()
    onWifiOnChanged: refresh(true)
    // A restricted answer may be minutes old (NetworkManager backs off to its
    // 300 s interval): ask again once on open.
    Component.onCompleted: {
        refresh(true);
        if (restricted)
            Qt.callLater(checkConnectivity);
    }
    // scannerEnabled lives on the shared device without reference counting;
    // the panel only exists while open, so it releases it here.
    Component.onDestruction: {
        if (wifiDevice)
            wifiDevice.scannerEnabled = false;
    }

    // NetworkManager signals for every network in range: completes or fails
    // the panel's own action and keeps the rows' connected/saved flags live.
    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks : null

        delegate: Connections {
            required property var modelData

            target: modelData

            function onConnectionFailed(reason: int): void {
                // Background auto-connect retries fire this too; only the
                // connect started here reopens the passphrase field.
                const ours = root.actionKind === "connect" && root.actionSsid === (modelData.name || "");
                root.failNetworkAction(modelData, reason);
                if (ours && Model.shouldRepromptPassphrase(reason, root.requiresCredentials(modelData.security), root.connectionFailReasons))
                    root.openPasswordPrompt(modelData.name);
            }
            function onConnectedChanged(): void {
                root.syncWifiNetworks();
            }
            function onKnownChanged(): void {
                root.syncWifiNetworks();
            }
            function onStateChangingChanged(): void {
                root.checkActionCompletion(modelData);
            }
        }
    }

    Process {
        id: detailsProc

        command: [root.binDir + "/haseen-network-status"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updateDetails(text)
        }
    }

    Process {
        id: bandProc

        command: [root.binDir + "/haseen-network-band"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.updateBand(text)
        }
    }

    Process {
        id: dnsProc

        command: [root.binDir + "/haseen-setup-dns"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.dnsProvider = Model.dnsChoice(text)
        }
    }

    Process {
        id: bandSet

        onExited: exitCode => {
            // A refused or reverted pin leaves bandSelected alone.
            if (exitCode === 0)
                root.bandSelected = root.pendingBand;
            else
                root.bandFailure = root.pendingBand;
            root.pendingBand = "";
            root.refresh(false);
        }
    }

    Process {
        id: dnsSet

        onExited: exitCode => {
            if (exitCode !== 0)
                root.dnsFailure = root.pendingDns;
            root.pendingDns = "";
            if (!dnsProc.running)
                dnsProc.running = true;
        }
    }

    // Creates and brings up the 802.1X profile (Model.enterpriseConnectScript).
    // The password goes over stdin, never argv, and is dropped once written.
    Process {
        id: enterpriseConnect

        property string secret: ""

        stdinEnabled: true
        onStarted: {
            write(secret + "\n");
            secret = "";
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.actionKind === "connect") {
                root.failureSsid = root.actionSsid;
                root.failureReason = I18n.mark("Connection failed");
                root.actionSsid = "";
                root.actionKind = "";
                actionTimeout.stop();
            }
        }
    }

    // haseen:ui-timeout
    Timer {
        id: scanRestart

        interval: 100
        repeat: false
        onTriggered: {
            if (root.wifiDevice && root.wifiOn) {
                root.wifiDevice.scannerEnabled = true;
                scanDone.restart();
            } else {
                root.scanning = false;
            }
        }
    }

    // haseen:ui-timeout
    Timer {
        id: scanDone

        interval: 1500
        repeat: false
        onTriggered: root.syncWifiNetworks()
    }

    // haseen:sample
    Timer {
        interval: 2000
        repeat: true
        running: root.visible
        onTriggered: {
            if (!detailsProc.running)
                detailsProc.running = true;
        }
    }

    // Slower: several nmcli calls, and the bands only move when a scan
    // turns up a new access point.
    // haseen:sample
    Timer {
        interval: 4000
        repeat: true
        running: root.visible && (root.heroInfo.type === "wifi" || root.bandBusy)
        onTriggered: {
            if (!bandProc.running)
                bandProc.running = true;
        }
    }

    // haseen:sample
    Timer {
        interval: 2800
        repeat: true
        running: root.visible && root.hint === "" && !root.restricted && (root.heroInfo.type === "ethernet" || (root.heroInfo.type === "wifi" && root.connectedWifiNetwork !== null))
        onTriggered: phraseSwap.restart()
    }

    // Only while the panel is open on a portal or limited link: a sign-in
    // made elsewhere shows here without waiting for NetworkManager's backoff.
    // haseen:sample
    Timer {
        interval: 5000
        repeat: true
        running: root.visible && root.restricted && root.connectivityChecksEnabled
        onTriggered: root.checkConnectivity()
    }

    SequentialAnimation {
        id: phraseSwap

        NumberAnimation {
            target: heroMeta
            property: "opacity"
            to: 0
            duration: 180
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: root.connectionPhraseIndex = (root.connectionPhraseIndex + 1) % root.connectionPhrases.length
        }
        NumberAnimation {
            target: heroMeta
            property: "opacity"
            to: 1
            duration: 260
            easing.type: Easing.InQuad
        }
    }

    // NetworkManager's supplicant gives up after 25 s; a wrong saved PSK
    // must still land as "Wrong password" while the action is tracked.
    // haseen:ui-timeout
    Timer {
        id: actionTimeout

        interval: 30000
        repeat: false
        onTriggered: {
            if (!root.actionKind)
                return;
            root.failureSsid = root.actionSsid;
            root.failureReason = root.actionKind === "connect" ? I18n.mark("Timed out connecting") : root.actionKind === "disconnect" ? I18n.mark("Timed out disconnecting") : I18n.mark("Timed out forgetting");
            root.actionSsid = "";
            root.actionKind = "";
            root.refresh(false);
        }
    }

    // A failure under an open passphrase field shows for 2 s, then the
    // field comes back.
    // haseen:ui-timeout
    Timer {
        interval: 2000
        repeat: false
        running: root.failureReason !== "" && root.passwordSsid !== "" && root.failureSsid === root.passwordSsid
        onTriggered: {
            root.failureSsid = "";
            root.failureReason = "";
        }
    }

    // Test hook (settings.debugIpc): read state and open a passphrase field
    // without a keyboard. Nothing here connects, disconnects, forgets,
    // switches a band or DNS, or toggles a radio: smoke runs must never
    // change the machine's network. The typed passphrase is never reported.
    IpcHandler {
        target: "haseen.network"
        enabled: root.settings.debugIpc === true

        function prompt(name: string): void {
            root.openPasswordPrompt(name);
        }

        function state(): string {
            return JSON.stringify({
                backend: root.networkManagerAvailable ? "NetworkManager" : "none",
                kind: root.kind,
                connectivity: root.connectivity,
                signIn: root.restricted,
                type: root.heroInfo.type || "",
                hasDetails: !!root.info.iface,
                wifiEnabled: Networking.wifiEnabled,
                wifiHardwareEnabled: Networking.wifiHardwareEnabled,
                scanning: root.wifiDevice ? root.wifiDevice.scannerEnabled : false,
                dns: root.dnsProvider,
                band: {
                    current: root.bandCurrent,
                    selected: root.bandSelected,
                    available: root.bandAvailable,
                    shown: root.canSelectBand
                },
                prompting: root.passwordSsid,
                sections: root.wifiNetworks.map((n, i) => Model.wifiSectionTitle(root.wifiNetworks, i)).filter(t => t !== ""),
                networks: root.wifiNetworks.map(n => ({
                            name: n.ssid,
                            connected: n.connected,
                            known: n.known,
                            secured: root.requiresCredentials(n.security),
                            signal: n.signal
                        }))
            });
        }
    }

    component SectionHeader: Text {
        width: root.width
        textFormat: Text.PlainText
        color: Theme.muted
        elide: Text.ElideRight
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 2
        font.bold: true
        font.letterSpacing: 1.1
    }

    component Separator: Rectangle {
        width: root.width
        height: Theme.borderWidth
        color: Theme.border
    }

    component Note: Text {
        width: root.width
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    component IconAction: Item {
        id: action

        property string glyph
        property string hintText

        signal clicked

        implicitWidth: Math.round(Theme.fontSize * 2.2)
        implicitHeight: implicitWidth

        Rectangle {
            anchors.fill: parent
            radius: Theme.radius
            color: Theme.surfaceAlt
            border.color: Theme.accent
            border.width: Theme.borderWidth
            visible: actionMouse.containsMouse
        }

        Glyph {
            anchors.centerIn: parent
            glyph: action.glyph
            color: Theme.foreground
        }

        MouseArea {
            id: actionMouse

            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: root.hint = containsMouse ? action.hintText : ""
            onClicked: action.clicked()
        }
    }

    component Detail: Item {
        id: detail

        property string label
        property string value
        property color valueColor: Theme.foreground
        property string copyHint: ""

        width: (root.width - Theme.gap * 3) / 2
        height: Math.round(Theme.fontSize * 1.5)

        Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: detail.label
            color: Theme.muted
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
        }

        Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: detail.value
            color: detail.valueColor
            font.family: Theme.fontFamily
            font.pixelSize: Theme.fontSize - 1
            font.underline: copyMouse.containsMouse

            MouseArea {
                id: copyMouse

                anchors.fill: parent
                enabled: detail.copyHint !== "" && detail.value !== "--"
                hoverEnabled: enabled
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onContainsMouseChanged: root.hint = containsMouse ? detail.copyHint : ""
                onClicked: root.copy(detail.value)
            }
        }
    }

    // ---------- Hero: icon · name and state · speed test, Wi-Fi switch ----------
    Item {
        width: parent.width
        height: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

        Glyph {
            id: heroIcon

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            glyph: Model.connectionIcon(root.kind, root.signalStrength)
            color: root.kind === "disconnected" ? Theme.muted : root.restricted ? Theme.warning : Theme.accent
            opacity: root.networkManagerAvailable ? 1 : 0.5
            font.pixelSize: Math.round(Theme.fontSize * 2.4)
        }

        Row {
            id: heroActions

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            IconAction {
                anchors.verticalCenter: parent.verticalCenter
                visible: !!root.info.iface
                glyph: "\u{F04C5}"
                hintText: I18n.tr("Run a speed test")
                onClicked: root.runSpeedTest()
            }

            ToggleSwitch {
                id: wifiSwitch

                anchors.verticalCenter: parent.verticalCenter
                visible: root.networkManagerAvailable && root.wifiStationAvailable
                checked: Networking.wifiEnabled
                onHovered: on => root.hint = on ? (!Networking.wifiHardwareEnabled ? I18n.tr("Wi-Fi is blocked (rfkill)") : Networking.wifiEnabled ? I18n.tr("Turn Wi-Fi off") : I18n.tr("Turn Wi-Fi on")) : ""
                onToggled: root.toggleWifi()
            }
        }

        Column {
            id: heroLabels

            anchors.left: heroIcon.right
            anchors.leftMargin: Theme.gap * 1.5
            anchors.right: heroActions.left
            anchors.rightMargin: Theme.gap
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            // Link detail rides after the name: "Ethernet (2.5gbit)".
            Text {
                readonly property string title: I18n.tr(Model.heroTitle(root.heroInfo, root.kind))
                readonly property string detail: Model.headerDetail(root.info)

                width: parent.width
                textFormat: Text.PlainText
                text: detail !== "" ? title + " (" + detail + ")" : title
                color: Theme.foreground
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize + 3
                font.bold: true
            }

            Text {
                id: heroMeta

                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                // The phrase goes in translated; the fixed lines come out
                // English and are translated here.
                text: root.hint !== "" ? root.hint : I18n.tr(Model.heroMeta(root.heroInfo, root.kind, root.connectedWifiNetwork !== null, I18n.tr(root.connectionPhrase), root.connectivity))
                color: root.hint === "" && root.restricted ? Theme.warning : Theme.muted
                elide: Text.ElideRight
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
                font.bold: true
                font.letterSpacing: 1.2
                onTextChanged: {
                    if (root.hint !== "") {
                        phraseSwap.stop();
                        opacity = 1;
                    }
                }
            }
        }
    }

    Note {
        visible: !root.networkManagerAvailable
        text: I18n.tr("NetworkManager is not running.")
    }

    // ---------- Captive portal: only while the link is restricted ----------
    Pill {
        width: parent.width
        visible: root.restricted
        text: I18n.tr("Sign in to network")
        pending: true
        busy: root.portalOpening
        onHovered: on => root.hint = on ? I18n.tr("Open the network's sign-in page in your browser") : ""
        onClicked: root.signIn()
    }

    // ---------- Connection details: traffic first, then addresses ----------
    Grid {
        visible: !!root.info.iface
        columns: 2
        columnSpacing: Theme.gap * 3
        rowSpacing: 2

        Detail {
            label: I18n.tr("Ping")
            value: I18n.tr(Model.formatPingLatency(root.internetPingLatency, root.hasInternetPing))
            valueColor: root.hasInternetPing && root.internetPingPacketLoss > 0 ? Theme.urgent : Theme.foreground
        }
        Detail {
            label: I18n.tr("Packet Loss")
            value: Model.formatPacketLoss(root.internetPingPacketLoss, root.hasInternetPing)
            valueColor: root.hasInternetPing && root.internetPingPacketLoss > 0 ? Theme.urgent : Theme.foreground
        }
        Detail {
            label: I18n.tr("Receiving")
            value: root.hasTransferStats ? Model.formatRate(root.downloadRate) : "--"
        }
        Detail {
            label: I18n.tr("Sending")
            value: root.hasTransferStats ? Model.formatRate(root.uploadRate) : "--"
        }
        Detail {
            label: I18n.tr("Downloaded")
            value: root.hasTransferStats ? Model.formatBytes(parseFloat(root.info.rx_bytes || "0")) : "--"
        }
        Detail {
            label: I18n.tr("Uploaded")
            value: root.hasTransferStats ? Model.formatBytes(parseFloat(root.info.tx_bytes || "0")) : "--"
        }
        Detail {
            label: I18n.tr("IP Address")
            value: root.info.ip || "--"
            copyHint: I18n.tr("Copy IP")
        }
        Detail {
            label: I18n.tr("Gateway")
            value: root.info.gateway || "--"
            copyHint: I18n.tr("Copy gateway")
        }
    }

    // ---------- Wi-Fi band: only when the network answers on more than one ----------
    Separator {
        visible: root.canSelectBand
    }

    Item {
        width: parent.width
        height: Math.max(bandHeader.implicitHeight, bandAuto.implicitHeight)
        visible: root.canSelectBand

        SectionHeader {
            id: bandHeader

            readonly property string band: Model.bandSectionBand(root.bandEffective, root.bandCurrent)

            // Anchored, not left at x 0, so a right-to-left panel puts it
            // opposite the switch.
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: implicitWidth
            text: band === "" ? I18n.tr("WI-FI BAND") : I18n.tr("WI-FI BAND: %1", band)
        }

        Row {
            id: bandAuto

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Math.round(Theme.gap / 2)

            SectionHeader {
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                text: I18n.tr("AUTOMATIC")
            }

            ToggleSwitch {
                anchors.verticalCenter: parent.verticalCenter
                trackHeight: Math.round(Theme.fontSize * 1.1)
                checked: !root.bandPinned
                busy: root.bandBusy
                onHovered: on => root.hint = on ? root.bandHint(root.bandPinned ? "auto" : root.bandCurrent) : ""
                onToggled: root.toggleBandAuto()
            }
        }
    }

    Row {
        id: bandRow

        readonly property int count: Math.max(1, root.bandAvailable.length)

        width: parent.width
        visible: root.bandPillsVisible
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: root.bandAvailable

            delegate: Pill {
                required property string modelData

                width: (bandRow.width - bandRow.spacing * (bandRow.count - 1)) / bandRow.count
                text: I18n.tr(Model.bandLabel(modelData))
                active: root.bandCurrent === modelData
                selected: root.bandEffective === modelData
                busy: root.bandBusy
                onHovered: on => root.hint = on ? root.bandHint(modelData) : ""
                onClicked: root.setBand(modelData)
            }
        }
    }

    Note {
        visible: root.bandFailure !== ""
        text: I18n.tr("Could not switch to %1", I18n.tr(Model.bandLabel(root.bandFailure)))
        color: Theme.urgent
    }

    // ---------- DNS provider ----------
    Separator {}

    SectionHeader {
        text: I18n.tr("DNS PROVIDER")
    }

    Row {
        id: dnsRow

        width: parent.width
        spacing: Math.round(Theme.gap / 2)

        Repeater {
            model: Model.dnsProviders

            delegate: Pill {
                required property var modelData

                width: (dnsRow.width - dnsRow.spacing * (Model.dnsProviders.length - 1)) / Model.dnsProviders.length
                text: I18n.tr(modelData.label)
                active: root.dnsProvider === modelData.id
                selected: (root.pendingDns || root.dnsProvider) === modelData.id
                busy: root.pendingDns !== ""
                onHovered: on => root.hint = on ? I18n.tr(modelData.hint) : ""
                onClicked: root.setDns(modelData.id)
            }
        }
    }

    Note {
        visible: root.dnsFailure !== ""
        text: I18n.tr("DNS unchanged: run haseen setup dns %1 in a terminal", root.dnsFailure)
        color: Theme.urgent
    }

    // ---------- Wi-Fi networks ----------
    Separator {
        visible: root.wifiStationAvailable
    }

    SectionHeader {
        visible: root.wifiStationAvailable && root.wifiOn && root.scanning
        text: I18n.tr("SCANNING WI-FI…")
    }

    Note {
        visible: root.wifiStationAvailable && (!root.wifiOn || (!root.scanning && root.wifiNetworks.length === 0))
        text: !Networking.wifiHardwareEnabled ? I18n.tr("Wi-Fi is blocked by a hardware switch or rfkill.") : !Networking.wifiEnabled ? I18n.tr("Wi-Fi is off.") : I18n.tr("No Wi-Fi networks in range.")
    }

    // Capped so a busy neighbourhood does not push the panel off-screen.
    ListView {
        id: networkList

        width: parent.width
        visible: root.wifiStationAvailable && root.wifiOn
        height: Math.min(contentHeight, Theme.fontSize * 22)
        spacing: Math.round(Theme.gap / 2)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        model: visible ? root.wifiNetworks : []

        delegate: Column {
            id: entry

            required property var modelData
            required property int index
            readonly property string sectionTitle: Model.wifiSectionTitle(root.wifiNetworks, index)

            width: ListView.view.width
            spacing: Math.round(Theme.gap / 2)

            SectionHeader {
                visible: entry.sectionTitle !== ""
                topPadding: entry.index > 0 ? Theme.gap : 0
                text: I18n.tr(entry.sectionTitle)
            }

            NetworkRow {
                width: parent.width
                net: entry.modelData
                passwordOpen: root.passwordSsid !== "" && root.passwordSsid === entry.modelData.ssid
                busy: root.actionKind !== "" && root.actionSsid === entry.modelData.ssid
                failed: root.failureReason !== "" && root.failureSsid === entry.modelData.ssid
                statusText: I18n.tr(passwordOpen && failed ? root.failureReason : Model.rowStatus(entry.modelData, {
                    kind: root.actionKind,
                    ssid: root.actionSsid
                }, {
                    reason: root.failureReason,
                    ssid: root.failureSsid
                }, passwordOpen, root.wifiConnectivity))
                warning: entry.modelData.connected && root.wifiConnectivity === "portal"
                panelBusy: root.busy
                requiresCredentials: root.requiresCredentials(entry.modelData.security)
                enterprise: root.isEnterprise(entry.modelData.security)
                canForget: Model.canForgetNetwork(entry.modelData)
                identityText: root.identityText
                passwordText: root.passwordText
                onActivated: root.activateRow(entry.modelData)
                onForgetRequested: root.forgetRow(entry.modelData)
                onIdentityEdited: t => root.identityText = t
                onPasswordEdited: t => root.passwordText = t
                onSubmitted: root.submitCredentials(entry.modelData)
                onHint: t => root.hint = t
            }
        }
    }
}
