import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

// One connection to wootingd (plan 099), shared by the bar widget, the panel
// and the keyboard drawing. Adapted from the socket lifecycle the owner's
// t1nk33r.wooting repeated in Panel.qml and LayoutPanel.qml (MIT, Copyright
// (c) 2026 t1nk33r); Model.linkStep is that lifecycle's state machine,
// unchanged. A consumer exists only while it wants a connection (the bar
// always, the panel while open, the drawing while shown), so the link is
// always wanted while it lives.
//
// There is no HID code here and there never can be: Quickshell has no HID
// access. wootingd owns the keyboard's vendor interface and answers one JSON
// line per verb on its unix socket.
//
// wootingd runs only while a Wooting keyboard is attached (udev starts it,
// BindsTo= stops it, and it removes its socket on SIGTERM), so a missing
// socket is the normal state of a desk without the keyboard. It is watched,
// not polled: FileView's watchChanges inotifies the socket's directory and
// fires fileChanged when the socket appears or goes; reload() then tells the
// two apart (a socket is not a file, an absent path is FileNotFound). The
// original's notes: a reconnect Timer re-created the Socket forever while the
// daemon was absent and logged a ServerNotFoundError each time, and a Socket
// that has disconnected never reopens, so each attempt is a fresh Socket.
Item {
    id: link

    // Lines written as soon as the socket is up, e.g. "subscribe\n".
    property string hello: "subscribe\n"
    // Model.linkStep's state; not `state`, which would shadow Item.state.
    property var linkState: Model.emptyLink(true)
    readonly property bool connected: linkState.connected
    // What to say while there is no live connection; "" once there is one.
    readonly property string hint: Model.linkHint(linkState)
    // Same resolution as wootingd (core/wootingd/src/main.rs socket_path) and
    // share/haseen/lib/wooting.sh, including the uid-suffixed /tmp fallback.
    readonly property string socketPath: {
        const explicit = Quickshell.env("WOOTINGD_SOCKET");
        if (explicit)
            return explicit;
        const runtime = Quickshell.env("XDG_RUNTIME_DIR");
        if (runtime)
            return runtime + "/wootingd.sock";
        return "/tmp/wootingd-" + (Quickshell.env("UID") || Quickshell.env("EUID") || "") + ".sock";
    }

    // One JSON line from the daemon. A line, not a parsed object: a JS
    // object passed through a signal's var parameter comes back with its
    // arrays no longer Arrays, and Model.js tests Array.isArray.
    signal received(string line)
    signal up
    signal down

    visible: false
    width: 0
    height: 0

    // Writes one verb on the live connection; false when there is none.
    function send(verb: string): bool {
        const socket = socketLoader.item;
        if (!socket || !link.linkState.connected)
            return false;
        socket.write(verb + "\n");
        socket.flush();
        return true;
    }

    // Feeds one lifecycle event to the state machine and does what it says.
    // The only place a Socket is created or destroyed: the old one goes before
    // the new state is committed, so its dying signals are about a dead object.
    function step(event: string): void {
        const next = Model.linkStep(link.linkState, event);
        if (next.action === "connect" || next.action === "drop")
            socketLoader.active = false;
        link.linkState = next.link;
        if (next.action === "connect")
            socketLoader.active = true;
        else if (next.action === "drop")
            link.down();
        else if (next.action === "retry")
            retry.restart();
    }

    function ingest(line: string): void {
        if (line.trim() !== "")
            link.received(line);
    }

    FileView {
        id: watch

        path: link.socketPath
        watchChanges: true
        printErrors: false
        onFileChanged: watch.reload()
        // A regular file there would be a misconfiguration; the connect
        // attempt says so rather than a guess here.
        onLoaded: link.step("present")
        onLoadFailed: error => link.step(error === FileViewError.FileNotFound ? "absent" : "present")
    }

    Loader {
        id: socketLoader

        active: false
        sourceComponent: Socket {
            id: socket

            path: link.socketPath
            parser: SplitParser {
                onRead: line => link.ingest(line)
            }

            Component.onCompleted: socket.connected = true
            onConnectionStateChanged: {
                if (socket.connected) {
                    link.step("connected");
                    link.up();
                    socket.write(link.hello);
                    socket.flush();
                } else {
                    link.down();
                    link.step("failed");
                }
            }
            // A refused connect is not a state change, so presence is cleared
            // here too, or a consumer keeps drawing a profile that is gone.
            onError: () => {
                link.down();
                link.step("failed");
            }
        }
    }

    // The only timer: a bounded retry (Model.LINK_RETRY_LIMIT attempts) after
    // a connect fails while the socket file exists. The file appears at
    // bind(2), a moment before listen(2), and a crashed daemon leaves a stale
    // one until systemd restarts it. Never runs while the socket is absent.
    // haseen:ui-timeout
    Timer {
        id: retry

        interval: 2000
        repeat: false
        onTriggered: link.step("retry")
    }
}
