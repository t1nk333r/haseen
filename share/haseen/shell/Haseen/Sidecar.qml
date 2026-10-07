pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The shell's connection to haseen-sidecar: one unix socket, one JSON object
// per line. The daemon does the sampling that QML used to do with timers and
// FileViews; this singleton owns the socket, the capability list and the
// subscriptions.
//
// Client shape adapted from DankMaterialShell Services/DMSService.qml and
// DgopService.qml (MIT, Copyright (c) 2025 Avenge Media LLC): every feature is
// gated on `capabilities`, so a daemon that is missing, older or killed makes
// the feature disappear instead of breaking the shell.
//
// Started on demand: the first consumer connects, and if nothing is listening
// the daemon is launched and announces `ready <socket>` on stdout, which is
// what reconnects the socket. There is no retry timer and no polling here.
// A daemon that dies is not restarted on its own; the capability goes away,
// consumers hide, and `haseen sidecar start` (or a new consumer after a reload)
// brings it back.
Singleton {
    id: root

    readonly property string socketPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/haseen/sidecar.sock"
    readonly property string binary: Paths.haseenPath + "/sidecar/haseen-sidecar"

    readonly property bool connected: socket.connected
    property var capabilities: []
    property string version: ""
    property int daemonPid: 0

    // Last payload per stream, by name. Consumers read their own.
    property var streams: ({})

    // Every consumer's wishes, by a key it owns. The merged subscription is
    // what the daemon is told, so two bars and a panel are one sampler.
    property var _consumers: ({})
    property int _nextId: 1
    property bool _starting: false

    function has(capability: string): bool {
        return capabilities.indexOf(capability) >= 0;
    }

    // want(key, stream, params) — register or update one consumer.
    // params for `sysusage`: intervalMs, gpu ("auto"/"off"/"cardN"), processes,
    // system (cpuTempC, cpuFreqMHz, net and disks, for the DMS compat layer).
    // params for `borderwipe`: signature (the Hyprland instance to turn).
    function want(key: string, stream: string, params: var): void {
        const next = Object.assign({}, _consumers);
        next[key] = {
            stream: stream,
            params: params || {}
        };
        _consumers = next;
        ensure();
        _sync();
    }

    function drop(key: string): void {
        if (_consumers[key] === undefined)
            return;
        const next = Object.assign({}, _consumers);
        delete next[key];
        _consumers = next;
        _sync();
    }

    function send(request: var): void {
        if (!socket.connected)
            return;
        socket.write(JSON.stringify(request) + "\n");
        socket.flush();
    }

    // ensure — make sure a daemon is listening, then connect. A consumer calls
    // this as soon as it exists, before it subscribes: until the hello frame
    // arrives there is no capability, and a gated widget stays hidden.
    //
    // The connection is never attempted blind. Quickshell keeps a failed
    // QLocalSocket around (src/io/socket.cpp onSocketError), so a connect to a
    // socket that is not there yet poisons every later attempt. Starting the
    // daemon first costs nothing: it prints `ready` and exits again when
    // another one already owns the socket.
    function ensure(): void {
        if (socket.connected || _starting)
            return;
        _starting = true;
        daemon.running = true;
    }

    // _sync — one subscribe per stream, merged from every consumer: the
    // shortest interval, the first GPU choice that is not "off", and processes
    // and system when anyone asked for them.
    function _sync(): void {
        if (!socket.connected)
            return;
        const merged = {};
        for (const key in _consumers) {
            const consumer = _consumers[key];
            const params = consumer.params || {};
            if (consumer.stream !== "sysusage") {
                // One wish for the whole shell; the last consumer's params stand.
                merged[consumer.stream] = Object.assign({}, params);
                continue;
            }
            const m = merged.sysusage || (merged.sysusage = {
                intervalMs: 0,
                gpu: "off",
                processes: false,
                system: false
            });
            if (typeof params.intervalMs === "number" && params.intervalMs > 0)
                m.intervalMs = m.intervalMs === 0 ? params.intervalMs : Math.min(m.intervalMs, params.intervalMs);
            if (typeof params.gpu === "string" && params.gpu !== "off")
                m.gpu = params.gpu;
            m.processes = m.processes || params.processes === true;
            m.system = m.system || params.system === true;
        }
        for (const stream of ["sysusage", "borderwipe"]) {
            if (merged[stream] !== undefined)
                send({
                    id: _nextId++,
                    method: "subscribe",
                    stream: stream,
                    params: merged[stream]
                });
            else if (streams[stream] !== undefined)
                send({
                    id: _nextId++,
                    method: "unsubscribe",
                    stream: stream
                });
        }
    }

    function _onLine(line: string): void {
        let frame = null;
        try {
            frame = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (frame.type === "hello") {
            capabilities = Array.isArray(frame.capabilities) ? frame.capabilities : [];
            version = String(frame.version || "");
            daemonPid = Number(frame.pid || 0);
            _sync();
        } else if (frame.type === "event" && frame.stream) {
            const next = Object.assign({}, streams);
            next[frame.stream] = frame.data;
            streams = next;
        }
    }

    Socket {
        id: socket

        path: root.socketPath
        parser: SplitParser {
            onRead: line => root._onLine(line)
        }
        onConnectionStateChanged: {
            if (connected) {
                root._starting = false;
                return;
            }
            // A daemon that went away takes its capabilities with it, so every
            // consumer hides until something connects again.
            root.capabilities = [];
            root.version = "";
            root.daemonPid = 0;
            root.streams = ({});
        }
    }

    Process {
        id: daemon

        command: [root.binary]
        stdout: SplitParser {
            onRead: line => {
                if (line.startsWith("ready ")) {
                    socket.connected = true;
                    root._starting = false;
                } else if (line.startsWith("failed")) {
                    root._starting = false;
                }
            }
        }
        // A daemon that could not start (missing binary, broken build) leaves
        // no capability behind, which is exactly what a consumer gates on.
        onExited: root._starting = false
    }
}
