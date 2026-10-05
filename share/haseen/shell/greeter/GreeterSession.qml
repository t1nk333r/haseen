import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd
import "Greeter.js" as Greeter

// The login itself: who can log in, which sessions exist, what greetd is
// asking, and what is remembered. No visuals — GreeterCard draws this, and
// tests/test-greeter.sh drives it with no compositor at all.
//
// Flow (Quickshell's Greetd singleton, Quickshell.Services.Greetd):
//   createSession(user) -> authMessage(message, …) -> respond(answer)
//   -> readyToLaunch -> launch(argv, env, false)
// An authFailure ends the session: greetd wants a fresh createSession, so the
// card goes back to an empty password field with the message shown.
QtObject {
    id: root

    readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/haseen-greeter.json"

    property var users: []
    property var sessions: []
    property var memory: ({
            lastUser: "",
            sessions: {}
        })
    property int userIndex: 0
    property int sessionIndex: 0
    // What greetd last said: a prompt, or why the login failed.
    property string status: ""
    // An answer is expected: the next Enter responds instead of starting over.
    property bool awaitingResponse: false
    property bool secret: true

    readonly property var currentUser: users.length > 0 ? users[Math.min(userIndex, users.length - 1)] : null
    readonly property var currentSession: sessions.length > 0 ? sessions[Math.min(sessionIndex, sessions.length - 1)] : null

    signal promptChanged

    function authenticate(): void {
        if (!currentUser)
            return;
        status = "";
        awaitingResponse = false;
        if (Greetd.state !== GreetdState.Inactive)
            Greetd.cancelSession();
        Greetd.createSession(currentUser.name);
    }

    function answer(text: string): void {
        if (!awaitingResponse) {
            authenticate();
            return;
        }
        awaitingResponse = false;
        Greetd.respond(text);
    }

    function cycleUser(delta: int): void {
        if (users.length > 0) {
            userIndex = (userIndex + delta + users.length) % users.length;
            restoreSessionFor(currentUser);
        }
    }

    function cycleSession(delta: int): void {
        if (sessions.length > 0)
            sessionIndex = (sessionIndex + delta + sessions.length) % sessions.length;
    }

    function restoreSessionFor(user): void {
        if (!user)
            return;
        const remembered = sessions.findIndex(s => s.id === memory.sessions[user.name]);
        if (remembered >= 0)
            sessionIndex = remembered;
    }

    function launch(): void {
        if (!currentSession)
            return;
        // Remembered before the launch: once greetd starts the session this
        // process is on its way out, and a later write may not land.
        memoryFile.setText(JSON.stringify(Greeter.withMemory(memory, currentUser ? currentUser.name : "", currentSession.id)));
        Greetd.launch(Greeter.commandFor(currentSession.exec), [], false);
    }

    property Connections greetd: Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            root.status = message;
            if (!responseRequired) {
                Greetd.respond("");
                return;
            }
            root.secret = !echoResponse;
            root.awaitingResponse = true;
            root.promptChanged();
        }

        function onAuthFailure(message: string): void {
            root.status = message || "authentication failed";
            root.awaitingResponse = false;
            root.promptChanged();
        }

        function onReadyToLaunch(): void {
            root.launch();
        }

        function onError(message: string): void {
            root.status = message;
            root.awaitingResponse = false;
        }
    }

    // The users and sessions are read once: nothing can change them while a
    // login screen is up, so there is nothing to poll.
    property Process userScan: Process {
        running: true
        command: ["getent", "passwd"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.users = Greeter.parseUsers(text);
                const remembered = root.users.findIndex(u => u.name === root.memory.lastUser);
                if (remembered >= 0)
                    root.userIndex = remembered;
                root.restoreSessionFor(root.currentUser);
            }
        }
    }

    property Process sessionScan: Process {
        running: true
        command: ["sh", "-c", "for d in /usr/local/share/wayland-sessions /usr/share/wayland-sessions /usr/local/share/xsessions /usr/share/xsessions; do [ -d \"$d\" ] || continue; for f in \"$d\"/*.desktop; do [ -r \"$f\" ] && printf '=== %s\\n' \"$f\" && cat \"$f\"; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = [];
                let id = "";
                let body = "";
                const flush = () => {
                    if (!id)
                        return;
                    const entry = Greeter.parseSession(id, body);
                    if (entry)
                        parsed.push(entry);
                };
                for (const line of String(text).split("\n")) {
                    if (line.startsWith("=== ")) {
                        flush();
                        id = line.slice(4).split("/").pop().replace(/\.desktop$/, "");
                        body = "";
                    } else {
                        body += line + "\n";
                    }
                }
                flush();
                root.sessions = Greeter.parseSessions(parsed);
                root.restoreSessionFor(root.currentUser);
            }
        }
    }

    property FileView memoryFile: FileView {
        path: root.stateFile
        printErrors: false
        blockWrites: false
        onLoaded: {
            root.memory = Greeter.readMemory(text());
            root.restoreSessionFor(root.currentUser);
        }
    }

    // Driven by tests/test-greeter.sh and tools/smoke-greeter.sh, the way the
    // shell's other surfaces expose their state (haseen.session, keybinds).
    property IpcHandler ipc: IpcHandler {
        target: "greeter"

        function state(): string {
            return JSON.stringify({
                users: root.users.map(u => u.name),
                user: root.currentUser ? root.currentUser.name : "",
                sessions: root.sessions.map(s => s.id),
                session: root.currentSession ? root.currentSession.id : "",
                status: root.status,
                awaiting: root.awaitingResponse
            });
        }

        function login(password: string): void {
            root.authenticate();
            pending.password = password;
            pending.restart();
        }

        function selectUser(index: int): void {
            root.userIndex = Math.max(0, Math.min(index, root.users.length - 1));
            root.restoreSessionFor(root.currentUser);
        }

        function selectSession(index: int): void {
            root.sessionIndex = Math.max(0, Math.min(index, root.sessions.length - 1));
        }
    }

    // The prompt arrives a round trip after createSession; this answers it when
    // it does, which is what a human's hands do.
    property Timer pending: Timer
    {
        property string password: ""

        interval: 300
        repeat: false
        onTriggered: root.answer(password)
    }
}
