// Model.js: pure logic for haseen.omaconnect (plan 098). No QML types here,
// so tests/test-omaconnect.sh runs it under the real Qt JS engine.
//
// Adapted from jitendradara12's OmaConnect, KdeConnectController.qml
// (MIT, Copyright (c) 2026 OmaConnect contributors): the scan-line format, device
// capabilities, battery and network text, the literal IPv4/IPv6 address
// check, Tailscale peers, remote-command parsing and the verification key.

// Interface strings stay English here and are translated where QML shows
// them (I18n.tr); N_ marks them for tools/i18n.py (plan 109).
function N_(text) { return text; }

const PLUGINS = {
    battery: ["kdeconnect_battery"],
    ping: ["kdeconnect_ping"],
    ring: ["kdeconnect_findmyphone"],
    text: ["kdeconnect_share"],
    file: ["kdeconnect_share"],
    clipboard: ["kdeconnect_clipboard"],
    commands: ["kdeconnect_runcommand"],
    network: ["kdeconnect_connectivity_report"],
    sms: ["kdeconnect_sms"],
    media: ["kdeconnect_mprisremote"]
};

// parseDevice(line): one DEVICE line of `haseen kdeconnect devices`, or null.
function parseDevice(line) {
    const p = String(line || "").replace(/\r$/, "").split("\t");
    if (p.length < 9 || p[0] !== "DEVICE" || !/^[A-Za-z0-9_-]+$/.test(p[1]))
        return null;
    const plugins = String(p[8] || "").split(",");
    const caps = {};
    for (const key in PLUGINS)
        caps[key] = PLUGINS[key].some(name => plugins.indexOf(name) >= 0);
    const strength = /^[0-9]+$/.test(p[10] || "") ? Number(p[10]) : -1;
    return {
        id: p[1],
        name: p[2] || p[1],
        type: (p[3] || "unknown").toLowerCase(),
        paired: p[4] === "true",
        reachable: p[5] === "true",
        battery: /^[0-9]+$/.test(p[6]) ? Math.min(100, Number(p[6])) : -1,
        charging: p[7] === "true",
        networkType: (p[9] || "").trim() === "null" ? "" : (p[9] || "").trim(),
        networkStrength: strength >= 0 && strength <= 4 ? strength : -1,
        pairRequested: p[11] === "true",
        pairRequestedByPeer: p[12] === "true",
        verificationKey: (p[13] || "").trim(),
        caps: caps
    };
}

// parseScan(text): { devices, addresses, addressesReady } from the whole
// output; a device id is kept once.
function parseScan(text) {
    const devices = [], addresses = [], seen = {};
    let ready = false;
    for (const raw of String(text || "").split("\n")) {
        const line = raw.replace(/\r$/, "");
        if (line === "CUSTOM_ADDRESSES_READY") {
            ready = true;
        } else if (line.indexOf("CUSTOM_ADDRESS\t") === 0) {
            const a = line.slice(15).trim();
            if (a && addresses.indexOf(a) < 0)
                addresses.push(a);
        } else {
            const d = parseDevice(line);
            if (d && !seen[d.id]) {
                seen[d.id] = true;
                devices.push(d);
            }
        }
    }
    return { devices: devices, addresses: addresses, addressesReady: ready };
}

// pickDevice(devices, current): the id to show: the current one while it
// is listed, else a paired reachable device, else the first.
function pickDevice(devices, current) {
    const list = devices || [];
    if (list.some(d => d.id === current))
        return current;
    const live = list.find(d => d.paired && d.reachable);
    return live ? live.id : list.length ? list[0].id : "";
}

const TYPE_GLYPHS = { phone: "\u{F011C}", tablet: "\u{F04F9}", laptop: "\u{F0322}", desktop: "\u{F0379}", tv: "\u{F0D54}" };

function deviceGlyph(type) {
    return TYPE_GLYPHS[String(type || "").toLowerCase()] || TYPE_GLYPHS.phone;
}

function batteryGlyph(d) {
    if (!d || !d.caps || !d.caps.battery || d.battery < 0)
        return "\u{F0091}";
    if (d.charging)
        return "\u{F0084}";
    if (d.battery <= 20)
        return "\u{F0083}";
    return d.battery <= 50 ? "\u{F007D}" : "\u{F0079}";
}

function status(d) {
    if (!d)
        return N_("No devices");
    if (d.pairRequestedByPeer)
        return N_("Wants to pair");
    if (!d.paired)
        return d.reachable ? N_("Not paired") : N_("Not paired, offline");
    return d.reachable ? N_("Connected") : N_("Paired, offline");
}

function networkText(d) {
    if (!d || !d.networkType)
        return "";
    return d.networkStrength >= 0 ? d.networkType + " (" + d.networkStrength + "/4)" : d.networkType;
}

// detailParts(d, showBattery, showNetwork): ["64%", "Charging", "LTE (3/4)"];
// the panel translates each part before it joins them.
function detailParts(d, showBattery, showNetwork) {
    if (!d || !d.reachable)
        return [];
    const out = [];
    if (showBattery !== false && d.caps.battery && d.battery >= 0)
        out.push(d.battery + "%", d.charging ? N_("Charging") : d.battery <= 20 ? N_("Low battery") : N_("Discharging"));
    if (showNetwork !== false && d.networkType)
        out.push(networkText(d));
    return out;
}

// details(d, showBattery, showNetwork): "64% · Charging · LTE (3/4)".
function details(d, showBattery, showNetwork) {
    return detailParts(d, showBattery, showNetwork).join(" · ");
}

function canAct(d) {
    return !!(d && d.paired && d.reachable);
}

// formatKey(key): an 8-character verification key as "ABCD EFGH".
function formatKey(key) {
    const v = String(key || "").trim();
    return v.length === 8 ? v.slice(0, 4) + " " + v.slice(4) : v;
}

// addressError(address): "" for a literal IPv4 or IPv6 address, else why not.
function addressError(address) {
    const v = String(address || "").trim();
    if (!v)
        return N_("Enter an IP address");
    if (v.charAt(0) === "-" || /[\s\/\[\]%]/.test(v))
        return N_("Enter a literal IPv4 or IPv6 address");
    const v4 = /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/.exec(v);
    if (v4)
        return v4.slice(1).every(n => Number(n) <= 255) ? "" : N_("Invalid IPv4 address");
    const group = g => /^[0-9a-fA-F]{1,4}$/.test(g);
    if (/^[0-9a-fA-F:]+$/.test(v) && v.indexOf(":::") < 0 && v.indexOf(":") >= 0) {
        const halves = v.split("::");
        if (halves.length === 1) {
            const g = v.split(":");
            if (g.length === 8 && g.every(group))
                return "";
        } else if (halves.length === 2) {
            const g = (halves[0] ? halves[0].split(":") : []).concat(halves[1] ? halves[1].split(":") : []);
            if (g.length < 8 && g.every(group))
                return "";
        }
    }
    return N_("Enter a literal IPv4 or IPv6 address");
}

function firstIPv4(list) {
    return (list || []).map(String).find(a => /^\d+\.\d+\.\d+\.\d+$/.test(a)) || "";
}

// parseTailscale(json): `tailscale status --json` as { running, backend,
// self, peers }, peers online first, then by name.
function parseTailscale(text) {
    let data;
    try {
        data = JSON.parse(String(text || ""));
    } catch (e) {
        return null;
    }
    if (!data || typeof data !== "object")
        return null;
    const peers = [];
    const raw = data.Peer && typeof data.Peer === "object" ? data.Peer : {};
    for (const key in raw) {
        const r = raw[key] || {};
        const address = firstIPv4(r.TailscaleIPs);
        if (!address)
            continue;
        const dns = String(r.DNSName || "").replace(/\.$/, "");
        const host = String(r.HostName || "");
        peers.push({ id: String(r.ID || key), name: host || (dns ? dns.split(".")[0] : address), dnsName: dns, os: String(r.OS || ""), address: address, online: r.Online === true });
    }
    peers.sort((a, b) => a.online !== b.online ? (a.online ? -1 : 1) : a.name.localeCompare(b.name));
    const backend = String(data.BackendState || "");
    return { running: backend === "Running", backend: backend, self: firstIPv4(data.Self && data.Self.TailscaleIPs), peers: peers };
}

function filterPeers(peers, query) {
    const q = String(query || "").trim().toLowerCase();
    if (!q)
        return peers || [];
    return (peers || []).filter(p => [p.name, p.dnsName, p.address, p.os].some(f => String(f || "").toLowerCase().indexOf(q) >= 0));
}

// parseCommands(text): `kdeconnect-cli --list-commands` (JSON or "key: name"
// lines) as [{key, name}].
function parseCommands(text) {
    const src = String(text || "").trim();
    const out = [];
    if (!src)
        return out;
    let json;
    try {
        json = JSON.parse(src);
    } catch (e) {
        json = undefined;
    }
    if (json !== undefined) {
        if (json === null || typeof json !== "object")
            return out;
        const items = Array.isArray(json) ? json : Object.keys(json).map(k => ({ key: k, name: typeof json[k] === "object" && json[k] ? json[k].name : json[k] }));
        for (const item of items) {
            if (typeof item === "string" && item.trim())
                out.push({ key: item.trim(), name: item.trim() });
            else if (item && typeof item === "object") {
                const k = String(item.key || item.id || item.command || "").trim();
                if (k)
                    out.push({ key: k, name: String(item.name || item.label || k).trim() || k });
            }
        }
        return out;
    }
    for (const raw of src.split("\n")) {
        const v = raw.trim().replace(/^[-*•]\s*|^\d+\.\s*/, "").trim();
        if (!v || /no.*commands/i.test(v))
            continue;
        const at = v.indexOf(":");
        if (at > 0)
            out.push({ key: v.slice(0, at).trim(), name: v.slice(at + 1).trim() || v.slice(0, at).trim() });
        else
            out.push({ key: v, name: v });
    }
    return out;
}

const NO_MEDIA = { isPlaying: false, title: "", artist: "", album: "", player: "", albumArt: "", playerList: [] };

// parseMedia(text): `haseen kdeconnect media status` as a media state.
function parseMedia(text) {
    let m;
    try {
        m = JSON.parse(String(text || ""));
    } catch (e) {
        return NO_MEDIA;
    }
    if (!m || typeof m !== "object")
        return NO_MEDIA;
    const s = v => typeof v === "string" ? v : "";
    // Only KDE Connect's downloaded art (a local file) is shown; a remote
    // URL would be a request from the shell (plan 010).
    const art = s(m.albumArt);
    return {
        isPlaying: m.isPlaying === true,
        title: s(m.title),
        artist: s(m.artist),
        album: s(m.album),
        player: s(m.player),
        albumArt: /^file:\/\//.test(art) || art.charAt(0) === "/" ? art : "",
        playerList: Array.isArray(m.playerList) ? m.playerList.filter(p => typeof p === "string" && p !== "") : []
    };
}

function hasMedia(m) {
    return !!(m && (m.title || m.player));
}

// mediaLine(m): "Title — Artist".
function mediaLine(m) {
    if (!m || !m.title)
        return m && m.player ? N_("%1: nothing playing").replace("%1", () => m.player) : "";
    return m.artist ? m.title + " — " + m.artist : m.title;
}

// What the service calls each action, with its two failure sentences
// (refused, failed): whole sentences, so each translates on its own.
const FAILURES = {
    ring: [N_("That ring was refused"), N_("The ring failed")],
    clipboard: [N_("That clipboard was refused"), N_("The clipboard failed")],
    ping: [N_("That ping was refused"), N_("The ping failed")],
    text: [N_("That text was refused"), N_("The text failed")],
    "file transfer": [N_("That file transfer was refused"), N_("The file transfer failed")],
    command: [N_("That command was refused"), N_("The command failed")],
    pairing: [N_("That pairing was refused"), N_("The pairing failed")],
    "media control": [N_("That media control was refused"), N_("The media control failed")],
    address: [N_("That address was refused"), N_("The address failed")]
};

// failure(code, what): the message for a helper's exit code.
function failure(code, what) {
    if (code === 127)
        return N_("KDE Connect is not installed");
    if (code === 69)
        return N_("KDE Connect is not answering");
    const known = Object.prototype.hasOwnProperty.call(FAILURES, what) ? FAILURES[what] : null;
    if (code === 64)
        return known ? known[0] : "That " + what + " was refused";
    return known ? known[1] : "The " + what + " failed";
}
