.pragma library

// Pure classification for haseen.privacy. Widget.qml snapshots the PipeWire
// link groups into plain objects; tests/test-widgets-a.sh runs these headless.
//
// group: { source: node, target: node, active }
// node:  { id, name, description, nickname, audio, video, source, stream, props }
// The type flags come from the registry globals (no binding needed); props
// are filled only for bound nodes.

const CAMERA_APIS = ["v4l2", "libcamera"];

function appName(node) {
    if (!node)
        return "";
    const p = node.props || {};
    return p["application.name"] || p["application.process.binary"] || node.nickname || node.description || node.name || ("node " + node.id);
}

// A device video source (not a stream): a webcam or a portal screencast.
function isVideoSource(node) {
    return !!node && node.video && node.source && !node.stream;
}

// WirePlumber tags camera nodes media.role=Camera and device.api
// v4l2/libcamera; the portal's screencast stream (xdph-streaming-N) has
// neither. The node.name prefix covers a source whose props are not bound yet.
function isCamera(node) {
    if (!isVideoSource(node))
        return false;
    const p = node.props || {};
    if (p["media.role"] === "Camera" || CAMERA_APIS.indexOf(p["device.api"]) >= 0)
        return true;
    return /^(v4l2|libcamera)_input/.test(node.name || "");
}

// An audio capture device (Audio/Source, virtual sources included). Sink
// monitors are sinks, so recording desktop audio is not microphone use.
function isMic(node) {
    return !!node && node.audio && node.source && !node.stream;
}

// The capture side of a mic link: Stream/Input/Audio (Audio|Source|Stream).
function isAudioCapture(node) {
    return !!node && node.audio && node.source && node.stream;
}

// Groups worth binding: mic -> capture stream, and anything reading a video
// source. Idle cost is nil because nothing matches while nothing captures.
function interesting(group) {
    return !!group && (isVideoSource(group.source) || (isMic(group.source) && isAudioCapture(group.target)));
}

// Streams that are not real use: PulseAudio peak meters (pavucontrol and
// similar) and apps named in settings.ignore.
function isIgnored(node, ignore) {
    if (!node)
        return true;
    const p = node.props || {};
    if (p["stream.monitor"] === "true" || p["media.name"] === "Peak detect")
        return true;
    const names = [appName(node), p["application.process.binary"] || "", node.name || ""].map(s => String(s).toLowerCase());
    return (ignore || []).some(i => names.indexOf(String(i).toLowerCase()) >= 0);
}

function uniq(list) {
    return list.filter((v, i) => v !== "" && list.indexOf(v) === i);
}

// Only active links count: a corked or paused stream keeps its links in
// Init/Paused. -> { camera: [app], mic: [app], screen: [app] }
function classify(groups, ignore) {
    const camera = [], mic = [], screen = [];
    for (const g of groups || []) {
        if (!g || !g.active || !interesting(g) || isIgnored(g.target, ignore))
            continue;
        const app = appName(g.target);
        if (isMic(g.source))
            mic.push(app);
        else if (isCamera(g.source))
            camera.push(app);
        else
            screen.push(app);
    }
    return {
        camera: uniq(camera),
        mic: uniq(mic),
        screen: uniq(screen)
    };
}

// One line from geoclue-watch.sh (gdbus monitor output) -> true / false, or
// null when the line says nothing about GeoClue's InUse.
function parseGeoclue(line) {
    const s = String(line || "");
    const m = /'InUse':\s*<(true|false)>/.exec(s);
    if (m)
        return m[1] === "true";
    if (/does not have an owner|^unavailable$/.test(s.trim()))
        return false;
    return null;
}
