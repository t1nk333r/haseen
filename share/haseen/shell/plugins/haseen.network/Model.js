// Adapted from Omarchy shell/plugins/panels/network/Model.js.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: row list shaping, row status, hero text and DNS choices added;
// the bar-status parser and frequency label dropped (the bar reads
// Quickshell.Networking, the band section names the band itself).
// Captive-portal state (connectivityState, the restricted hero line and row
// status, ping read as "--" while restricted) from Omarchy 41a40ccc7 (#8859)
// and 3357f9059 (#16186), plan 106.

// Pure helpers for the haseen.network bar widget and panel. Nothing here
// touches QML types, so tests/test-network-panel.sh runs it headless.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

function wifiIconFor(strength) {
    const icons = ["\u{F092F}", "\u{F091F}", "\u{F0922}", "\u{F0925}", "\u{F0928}"];
    const index = Math.max(0, Math.min(4, Math.ceil(strength / 20) - 1));
    return icons[index];
}

// Wired wins when both are up, matching the default-route device.
function connectionKind(wiredConnected, wifiConnected) {
    if (wiredConnected)
        return "ethernet";
    if (wifiConnected)
        return "wifi";
    return "disconnected";
}

// NetworkManager's connectivity as one word: "portal" (a sign-in page answers
// its check), "limited" (the network answers, the internet does not), "full",
// "none" or "unknown". Disconnected is "none". With connectivity checking off
// NetworkManager keeps a stale answer, so it reads "unknown" (Omarchy's rule).
// `states` maps the NetworkConnectivity names so this stays pure.
function connectivityState(kind, connectivity, states, checksEnabled) {
    const s = states || {};
    if (kind === "disconnected")
        return "none";
    if (!checksEnabled)
        return "unknown";
    if (connectivity === s.Portal)
        return "portal";
    if (connectivity === s.Limited)
        return "limited";
    if (connectivity === s.Full)
        return "full";
    if (connectivity === s.None)
        return "none";
    return "unknown";
}

// Signing in can lift a portal, and a portal that withholds DNS reads as
// limited to NetworkManager, so both offer the sign-in row.
function restricted(connectivity) {
    return connectivity === "portal" || connectivity === "limited";
}

// Ping and loss only mean something once the internet answers: behind a
// portal, on a limited link or offline every probe is lost by design, so the
// rows read "--" rather than restate it (Omarchy 3357f9059).
function internetPingReadable(samples, connectivity) {
    const values = Array.isArray(samples) ? samples : [];
    if (restricted(connectivity) || connectivity === "none")
        return false;
    return values.length > 0;
}

function connectionIcon(kind, signalStrength) {
    if (kind === "wifi")
        return wifiIconFor(signalStrength);
    if (kind === "ethernet")
        return "\u{F0200}";
    return "\u{F092E}";
}

function formatHeaderSpeed(mbps) {
    const v = parseInt(mbps, 10);
    if (!v || v < 0)
        return "";
    if (v >= 1000)
        return (v / 1000).toFixed(v % 1000 === 0 ? 0 : 1) + "gbit";
    return v + "mbit";
}

// Wi-Fi band state belongs in the band section, not beside the hero name.
// Ethernet has no band, so its negotiated link speed rides here.
function headerDetail(info) {
    const value = info || {};
    if (value.type === "ethernet")
        return formatHeaderSpeed(value.speed || "");
    return "";
}

function heroTitle(info, kind) {
    const value = info || {};
    if (value.type === "wifi")
        return value.ssid || N_("Wi-Fi");
    if (value.type === "ethernet")
        return N_("Ethernet");
    return value.iface || (kind === "disconnected" ? N_("Disconnected") : N_("No connection"));
}

// The line under the name: what a restricted link needs, else a rotating
// phrase while connected, NOT CONNECTED without a route, nothing in between.
function heroMeta(info, kind, wifiConnected, phrase, connectivity) {
    const type = (info || {}).type;
    if (kind !== "disconnected" && connectivity === "portal")
        return N_("SIGN-IN REQUIRED");
    if (kind !== "disconnected" && connectivity === "limited")
        return N_("LIMITED INTERNET ACCESS");
    if (type === "ethernet" || (type === "wifi" && wifiConnected))
        return String(phrase || "").toUpperCase();
    if (kind === "disconnected")
        return N_("NOT CONNECTED");
    return "";
}

function bandLabel(band) {
    if (band === "auto")
        return N_("Auto");
    if (!band)
        return "";
    return band + "ghz";
}

// Under Automatic the pills are hidden, so the header carries the live band
// instead: "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills say it.
// The panel fills the template itself, so the band rides as %1.
function bandSectionBand(selected, current) {
    if (selected !== "auto")
        return "";
    return bandLabel(current).toUpperCase();
}

function bandSectionTitle(selected, current) {
    const band = bandSectionBand(selected, current);
    if (band === "")
        return N_("WI-FI BAND");
    return N_("WI-FI BAND: %1").replace("%1", band);
}

function bandTooltip(band) {
    if (band === "auto")
        return N_("Let Wi-Fi pick the band");
    if (!band)
        return "";
    return N_("Stay on %1").replace("%1", bandLabel(band));
}

function parseBandStatus(raw) {
    const next = parseKeyValue(raw);
    const available = String(next.available || "").split(" ").filter(t => t !== "");
    return {
        band: next.band || "",
        selected: next.selected || "auto",
        available: available
    };
}

// iw prints non-ASCII SSID bytes as \xNN; turn them back into UTF-8, but
// keep control bytes escaped so they never reach the label.
function decodeIwSsid(value) {
    const raw = String(value || "");
    try {
        let encoded = "";
        for (let i = 0; i < raw.length; i++) {
            if (raw[i] === "\\" && raw[i + 1] === "x" && /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))) {
                const hex = raw.substring(i + 2, i + 4);
                const byte = parseInt(hex, 16);
                encoded += byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex;
                i += 3;
            } else {
                encoded += encodeURIComponent(raw[i]);
            }
        }
        return decodeURIComponent(encoded);
    } catch (error) {
        return raw;
    }
}

// "key<TAB>value" lines from haseen-network-status / haseen-network-band.
function parseKeyValue(raw) {
    const next = {};
    const lines = String(raw || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        const idx = line.indexOf("\t");
        if (idx <= 0)
            continue;
        const key = line.substring(0, idx);
        const value = line.substring(idx + 1);
        next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim();
    }
    return next;
}

// Rates are deltas between successive samples. The first sample after open
// or after an interface switch only primes the counters, so no fake spike.
function throughputState(previous, next, now) {
    const prev = previous || {};
    const sample = next || {};
    const iface = sample.iface || "";
    const rx = parseFloat(sample.rx_bytes || "0");
    const tx = parseFloat(sample.tx_bytes || "0");
    const previousTime = Number(prev.prevSampleTime || 0);

    if (iface !== (prev.prevIface || "") || previousTime === 0)
        return {
            prevIface: iface,
            prevRxBytes: rx,
            prevTxBytes: tx,
            prevSampleTime: now,
            downloadRate: 0,
            uploadRate: 0
        };

    let downloadRate = Number(prev.downloadRate || 0);
    let uploadRate = Number(prev.uploadRate || 0);
    const dt = now - previousTime;
    if (dt > 0) {
        downloadRate = Math.max(0, (rx - Number(prev.prevRxBytes || 0)) / dt);
        uploadRate = Math.max(0, (tx - Number(prev.prevTxBytes || 0)) / dt);
    }
    return {
        prevIface: iface,
        prevRxBytes: rx,
        prevTxBytes: tx,
        prevSampleTime: now,
        downloadRate: downloadRate,
        uploadRate: uploadRate
    };
}

function pingSampleValue(raw) {
    const value = parseFloat(raw);
    if (!isFinite(value) || value < 0)
        return null;
    return value;
}

function appendPingSample(samples, raw, limit) {
    const values = Array.isArray(samples) ? samples.slice() : [];
    values.push(pingSampleValue(raw));
    while (values.length > limit)
        values.shift();
    return values;
}

function averagePingLatency(samples, limit) {
    const values = Array.isArray(samples) ? samples : [];
    const sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1);
    let total = 0;
    let count = 0;
    for (let i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
        const value = values[i];
        if (typeof value !== "number" || !isFinite(value) || value < 0)
            continue;
        total += value;
        count++;
    }
    return count > 0 ? total / count : -1;
}

function pingPacketLossPercent(samples) {
    const values = Array.isArray(samples) ? samples : [];
    if (values.length === 0)
        return 0;
    const lost = values.filter(v => v === null).length;
    return Math.round((lost / values.length) * 100);
}

// `hasSamples` false means no probe has come back yet, which is different
// from a probe that timed out: the row reads "--" instead of reflowing.
function formatPacketLoss(percent, hasSamples) {
    if (hasSamples === false)
        return "--";
    const value = parseInt(percent, 10);
    if (!value || value < 0)
        return "0%";
    return value + "%";
}

function pingLatencyState(previous, next, limit, averageLimit) {
    const prev = previous || {};
    const sample = next || {};
    const iface = sample.iface || "";
    const window = Math.max(1, parseInt(limit, 10) || 5);
    const averageWindow = Math.max(1, parseInt(averageLimit, 10) || window);
    const reset = iface === "" || iface !== (prev.pingIface || "");
    const internetSamples = sample.internet_ping_ms === undefined ? [] : appendPingSample(reset ? [] : prev.internetPingSamples, sample.internet_ping_ms, window);

    return {
        pingIface: iface,
        internetPingSamples: internetSamples,
        internetPingLatency: averagePingLatency(internetSamples, averageWindow),
        internetPingPacketLoss: pingPacketLossPercent(internetSamples)
    };
}

function formatBytes(bytes) {
    let n = Number(bytes);
    if (!isFinite(n) || n < 0)
        n = 0;
    if (n < 1024)
        return Math.round(n) + " B";
    if (n < 1024 * 1024)
        return (n / 1024).toFixed(1) + " KB";
    if (n < 1024 * 1024 * 1024)
        return (n / (1024 * 1024)).toFixed(1) + " MB";
    return (n / (1024 * 1024 * 1024)).toFixed(2) + " GB";
}

function formatRate(bytesPerSec) {
    return formatBytes(bytesPerSec) + "/s";
}

function formatPingLatency(ms, hasSamples) {
    if (hasSamples === false)
        return "--";
    const value = parseFloat(ms);
    if (!isFinite(value) || value < 0)
        return N_("Timeout");
    return value.toFixed(value > 0 && value < 10 ? 1 : 0) + " ms";
}

// Primitives only: rows become delegate data, and a live WifiNetwork in a
// delegate's var property can dangle when NetworkManager drops the access
// point mid-scan. Callers resolve the object by SSID when they act.
function wifiRow(network) {
    if (!network)
        return null;
    return {
        connected: !!network.connected,
        known: !!network.known,
        ssid: network.name || "",
        signal: Math.round((network.signalStrength || 0) * 100),
        security: network.security
    };
}

function sortWifiRows(rows) {
    const nets = Array.isArray(rows) ? rows.slice() : [];
    nets.sort((a, b) => {
        if (a.connected !== b.connected)
            return a.connected ? -1 : 1;
        if (a.known !== b.known)
            return a.known ? -1 : 1;
        return b.signal - a.signal;
    });
    return nets;
}

// The panel's list: named networks only (a hidden SSID cannot be told apart
// or joined from a row), connected first, then saved, then by signal, capped
// at `limit` rows.
// `networks` is usually a QML sequence (ObjectModel.values), which is
// array-like but fails Array.isArray.
function wifiRows(networks, limit) {
    const list = networks && typeof networks.length === "number" ? Array.prototype.slice.call(networks) : [];
    const rows = list.map(wifiRow).filter(r => r !== null && r.ssid !== "");
    const max = Math.max(1, parseInt(limit, 10) || 8);
    return sortWifiRows(rows).slice(0, max);
}

function wifiSectionTitle(wifiNetworks, index) {
    const networks = Array.isArray(wifiNetworks) ? wifiNetworks : [];
    if (index < 0 || index >= networks.length)
        return "";
    const net = networks[index];
    if (!net)
        return "";
    if (net.known && index === 0)
        return N_("KNOWN NETWORKS");
    if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known)))
        return N_("OTHER NETWORKS");
    return "";
}

// OWE (Enhanced Open) encrypts without authenticating, so it has no
// credentials to collect. Unknown security stays credentialed.
function requiresCredentials(security, openSecurity, oweSecurity) {
    return security !== openSecurity && security !== oweSecurity;
}

function canForgetNetwork(network) {
    return !!(network && network.known && !network.connected);
}

// What a click on a row does: disconnect the connected one, ask for the
// passphrase of a secured network without a saved profile, connect the rest.
function rowAction(row, needsCredentials) {
    if (!row)
        return "";
    if (row.connected)
        return "disconnect";
    if (needsCredentials && !row.known)
        return "prompt";
    return "connect";
}

// The second line of a row: the panel's own action in flight, then its
// failure, then Sign-in required (the connected network behind a portal),
// then Connected. Empty while the passphrase field is open.
function rowStatus(row, action, failure, passwordOpen, connectivity) {
    if (!row || passwordOpen)
        return "";
    const act = action || {};
    const fail = failure || {};
    if (act.kind && act.ssid === row.ssid) {
        if (act.kind === "connect")
            return N_("Connecting…");
        if (act.kind === "disconnect")
            return N_("Disconnecting…");
        return N_("Forgetting…");
    }
    if (fail.reason && fail.ssid === row.ssid)
        return fail.reason;
    if (row.connected && connectivity === "portal")
        return N_("Sign-in required");
    if (row.connected)
        return N_("Connected");
    return "";
}

// The passphrase reaches nmcli on stdin through the scriptable
// `connection edit` editor: argv is world-readable in /proc, so the secret
// is never an argument (printf is a bash builtin, so no process gets it in
// argv either). $1 is the SSID, $2 the identity.
var enterpriseConnectScript = "u=$(uuidgen); IFS= read -r pw;" + " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" + " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" + " 802-1x.identity \"$2\" 802-1x.auth-timeout 8 >/dev/null" + " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" + " && nmcli connection up uuid \"$u\"" + " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }";

function networkFailureReason(reason, needsCredentials, reasons) {
    const r = reasons || {};
    if (needsCredentials && reason === r.NoSecrets)
        return N_("Passphrase required");
    if (needsCredentials && reason === r.WifiAuthTimeout)
        return N_("Wrong password");
    if (reason === r.WifiNetworkLost)
        return N_("Network lost");
    if (reason === r.WifiClientDisconnected)
        return N_("Disconnected");
    if (reason === r.WifiClientFailed)
        return N_("Connection failed");
    return N_("Failed to connect");
}

// NoSecrets means credentials are missing; an auth timeout on a secured
// network means the saved passphrase is wrong (connectWithPsk overwrites it
// on the next submit). Either way the user gets the field back.
function shouldRepromptPassphrase(reason, needsCredentials, reasons) {
    const r = reasons || {};
    if (!needsCredentials)
        return false;
    return reason === r.NoSecrets || reason === r.WifiAuthTimeout;
}

// `haseen setup dns` names; the panel shows Omarchy's labels (translated
// where shown; DHCP and the companies keep their names).
var dnsProviders = [
    {
        id: "dhcp",
        label: "DHCP",
        hint: N_("Use DNS from DHCP")
    },
    {
        id: "cloudflare",
        label: "Cloudflare",
        hint: N_("Set DNS to Cloudflare")
    },
    {
        id: "google",
        label: "Google",
        hint: N_("Set DNS to Google")
    },
    {
        id: "custom",
        label: N_("Custom"),
        hint: N_("Set custom DNS servers")
    }
];

function dnsChoice(raw) {
    const value = String(raw || "").trim().toLowerCase();
    return dnsProviders.some(p => p.id === value) ? value : "dhcp";
}
