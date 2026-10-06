// Adapted from Omarchy shell/plugins/panels/audio/Model.js.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: device/stream list shaping added, MPRIS label matching dropped.

// Pure helpers for the haseen.audio panel. Nodes are PwNode-shaped objects
// (name, description, nickname, isSink, isStream, audio, type, properties).

function isPlaybackStream(node) {
    if (!node || !node.isStream)
        return false;
    if (node.isSink === true)
        return true;
    const mediaClass = String(node.type || "");
    return mediaClass.indexOf("Output") !== -1;
}

function isAudioSource(node) {
    if (!node)
        return false;
    if (node.audio)
        return true;
    return String(node.type || "").indexOf("Source") !== -1;
}

function outputVolumeName(volume, muted) {
    if (muted)
        return "Muted";
    const p = Math.round(volume * 100);
    if (p === 0)
        return "Silenced";
    if (p >= 100)
        return "Concert hall";
    if (p >= 85)
        return "Party mode";
    if (p >= 70)
        return "Cranked up";
    if (p >= 50)
        return "Steady groove";
    if (p >= 30)
        return "Easy listening";
    if (p >= 15)
        return "Murmur";
    return "Whisper";
}

function friendlyDeviceLabel(text) {
    return String(text || "").trim()
        .replace(/^sof-soundwire\s+/i, "")
        .replace(/^built-?in audio\s+/i, "")
        .replace(/\s+Output$/i, "")
        .replace(/\s+Input$/i, "")
        .replace(/\bMicrophones\b/g, "Microphone");
}

function nodeProps(node) {
    return node && node.ready !== false && node.properties ? node.properties : {};
}

function nodeLabel(node) {
    if (!node)
        return "Unknown";
    const p = nodeProps(node);
    const nick = friendlyDeviceLabel(node.nickname || p["node.nick"] || p["device.profile.description"] || "");
    if (nick)
        return nick;
    return friendlyDeviceLabel(node.description || p["node.description"] || node.name || "") || "Unknown";
}

function blobOf(node, keys) {
    const p = nodeProps(node);
    return [node.name, node.description, node.nickname].concat(keys.map(k => p[k] || "")).join(" ").toLowerCase();
}

function isHeadphones(node) {
    if (!node)
        return false;
    return /headphone|headset|earbud|earphone|airpod/.test(blobOf(node, ["device.icon-name", "device.product.name", "node.description", "node.nick"]));
}

function sinkGlyph(node) {
    if (!node)
        return "\u{F04C3}";
    if (isHeadphones(node))
        return "\u{F02CB}";
    const blob = blobOf(node, ["device.icon-name", "device.product.name"]);
    if (blob.indexOf("bluetooth") !== -1)
        return "\u{F00AF}";
    if (blob.indexOf("hdmi") !== -1 || blob.indexOf("display") !== -1)
        return "\u{F0379}";
    return "\u{F04C3}";
}

function sourceGlyph(node) {
    if (!node)
        return "\u{F036C}";
    const blob = blobOf(node, ["device.icon-name"]);
    if (blob.indexOf("headset") !== -1)
        return "\u{F02CB}";
    if (blob.indexOf("bluetooth") !== -1)
        return "\u{F00AF}";
    if (blob.indexOf("webcam") !== -1 || blob.indexOf("camera") !== -1)
        return "\u{F0100}";
    return "\u{F036C}";
}

function streamLabel(node) {
    if (!node)
        return "Stream";
    const p = nodeProps(node);
    const label = String(p["application.name"] || node.description || p["media.name"] || p["node.name"] || node.name || "").trim();
    return label.toLowerCase() === "spotify" ? "Spotify" : (label || "Stream");
}

// What the stream plays (media.name), unless it only repeats the app label.
function streamDetail(node) {
    const media = String(nodeProps(node)["media.name"] || "").trim();
    return media.toLowerCase() === streamLabel(node).toLowerCase() ? "" : media;
}

function byLabel(a, b) {
    return nodeLabel(a).localeCompare(nodeLabel(b));
}

// Hardware outputs, alphabetical.
function sinks(nodes) {
    return (nodes || []).filter(n => n && n.isSink && !n.isStream).sort(byLabel);
}

// Hardware inputs, alphabetical. Monitor sources are not inputs a person picks.
function sources(nodes) {
    return (nodes || []).filter(n => n && !n.isSink && !n.isStream && isAudioSource(n) && !/\.monitor$/.test(String(n.name || ""))).sort(byLabel);
}

// Per-app playback streams with volume control, alphabetical by app label.
function streams(nodes) {
    return (nodes || []).filter(n => isPlaybackStream(n) && n.audio).sort((a, b) => streamLabel(a).localeCompare(streamLabel(b)));
}

function clampVolume(v) {
    return Math.max(0, Math.min(1, Number(v) || 0));
}

if (typeof module !== "undefined")
    module.exports = {
        isPlaybackStream,
        isAudioSource,
        outputVolumeName,
        friendlyDeviceLabel,
        nodeLabel,
        isHeadphones,
        sinkGlyph,
        sourceGlyph,
        streamLabel,
        streamDetail,
        sinks,
        sources,
        streams,
        clampVolume
    };
