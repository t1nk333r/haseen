import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets

// haseen.ai: chat with the local model (plan 012). Open it with SUPER+A
// (`haseen shell ipc panel toggle haseen.ai`).
//
// Every request goes through the CLI (`haseen ai config`, `haseen ai models`,
// `haseen ai chat --messages-file`), so the ai.json merge, the loopback-only
// `local` policy and API-key handling live in one place (layers/ai/ai.sh).
// The panel is lazy: nothing here exists until it opens, and closing it stops
// a running reply. No timers, no polling: each process runs once per action.
// The conversation is kept in ~/.local/state/haseen/ai/chat.json so closing
// the panel by accident loses nothing; "new chat" empties it.
Item {
    id: root

    // Every entry gets these from the host (docs/architecture.md 5.2).
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/haseen next to share/haseen: true for the checkout, /usr/local
    // and /usr alike.
    readonly property string cli: Paths.haseenPath + "/../../bin/haseen"
    readonly property string endpointSetting: typeof settings.endpoint === "string" ? settings.endpoint : ""

    property string endpoint: ""
    property string policy: ""
    property string endpointModel: ""
    property var models: []
    property string model: ""
    property string savedModel: ""
    property string notice: ""
    property bool picking: false
    property bool stopping: false
    property string errText: ""
    readonly property bool busy: chat.running

    implicitWidth: Theme.fontSize * 36
    implicitHeight: Math.min(Theme.fontSize * 46, screen ? Math.round(screen.height * 0.75) : Theme.fontSize * 46)

    function pickModel(): void {
        if (models.length === 0) {
            model = endpointModel || savedModel;
            return;
        }
        for (const m of [model, savedModel, endpointModel])
            if (m !== "" && models.indexOf(m) >= 0) {
                model = m;
                return;
            }
        model = models[0];
    }

    // The conversation as the CLI wants it; failed turns are left out.
    function history(withModel: bool): var {
        const out = [];
        for (let i = 0; i < messages.count; i++) {
            const m = messages.get(i);
            if (m.phase === "error" || m.content === "")
                continue;
            const turn = {
                role: m.role,
                content: m.content
            };
            if (withModel && m.modelName !== "")
                turn.model = m.modelName;
            out.push(turn);
        }
        return out;
    }

    function save(): void {
        store.setText(JSON.stringify({
            version: 1,
            model: root.model,
            messages: history(true)
        }, null, 1) + "\n");
    }

    function send(): void {
        const text = input.text.trim();
        if (text === "" || busy)
            return;
        picking = false;
        messages.append({
            role: "user",
            content: text,
            modelName: "",
            phase: "done"
        });
        const conversation = history(false);
        messages.append({
            role: "assistant",
            content: "",
            modelName: root.model,
            phase: "streaming"
        });
        input.text = "";
        Qt.callLater(list.positionViewAtEnd);
        save();

        // The history goes through a 0600 mktemp file in $XDG_RUNTIME_DIR,
        // never argv. It is unlinked as soon as it is open on fd 3, so a
        // stop, a closed panel or a killed shell leaves nothing behind (a
        // trap would not run when the host kills the process). setsid makes
        // the chat the leader of its own process group, so stop() ends curl
        // and jq too, not only bash.
        const cmd = ["setsid", "bash", "-c", 'f=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/haseen-ai-chat.XXXXXX") || exit 1; cat >"$f" && exec 3<"$f"; rm -f "$f"; exec "$@" --messages-file /dev/fd/3 </dev/null', "haseen-ai-chat", cli, "ai", "chat", "--endpoint", endpoint];
        if (model !== "")
            cmd.push("--model", model);
        chat.pending = JSON.stringify(conversation);
        errText = "";
        stopping = false;
        chat.stdinEnabled = true;
        chat.command = cmd;
        chat.running = true;
    }

    function appendChunk(data: string): void {
        const last = messages.count - 1;
        if (last < 0)
            return;
        const follow = list.atYEnd;
        messages.setProperty(last, "content", messages.get(last).content + data);
        if (follow)
            Qt.callLater(list.positionViewAtEnd);
    }

    function finish(code: int): void {
        const last = messages.count - 1;
        if (last < 0 || messages.get(last).phase !== "streaming")
            return;
        const content = messages.get(last).content.replace(/\s+$/, "");
        messages.setProperty(last, "content", content);
        if (stopping) {
            messages.setProperty(last, "phase", "stopped");
        } else if (code !== 0) {
            const why = errText.trim() || "haseen ai chat exited with " + code;
            messages.setProperty(last, "content", content === "" ? why : content + "\n\n" + why);
            messages.setProperty(last, "phase", "error");
        } else {
            messages.setProperty(last, "phase", "done");
        }
        stopping = false;
        save();
        Qt.callLater(list.positionViewAtEnd);
    }

    function stop(): void {
        if (!chat.running)
            return;
        stopping = true;
        Quickshell.execDetached(["kill", "-TERM", "--", "-" + chat.processId]);
    }

    function newChat(): void {
        stop();
        messages.clear();
        save();
        input.forceActiveFocus();
    }

    Component.onCompleted: {
        configProc.running = true;
        input.forceActiveFocus();
    }
    Component.onDestruction: stop()

    ListModel {
        id: messages
    }

    FileView {
        id: store

        path: Paths.userState + "/ai/chat.json"
        printErrors: false
        onLoaded: {
            try {
                const data = JSON.parse(text());
                root.savedModel = typeof data.model === "string" ? data.model : "";
                if (messages.count === 0 && Array.isArray(data.messages))
                    for (const m of data.messages)
                        if (m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
                            messages.append({
                                role: m.role,
                                content: m.content,
                                modelName: typeof m.model === "string" ? m.model : "",
                                phase: "done"
                            });
            } catch (e) {
                console.warn(root.pluginId + ": ignoring unreadable chat.json:", e.message);
            }
            root.pickModel();
            Qt.callLater(list.positionViewAtEnd);
        }
    }

    // `haseen ai config`: the merged, validated ai.json.
    Process {
        id: configProc

        command: [root.cli, "ai", "config"]
        stdout: StdioCollector {
            id: configOut
        }
        stderr: StdioCollector {
            id: configErr
        }
        onExited: code => {
            if (code !== 0) {
                root.notice = configErr.text.trim() || "haseen ai config failed";
                return;
            }
            let cfg = {};
            try {
                cfg = JSON.parse(configOut.text);
            } catch (e) {
                root.notice = "haseen ai config: " + e.message;
                return;
            }
            root.policy = cfg.policy || "";
            root.endpoint = root.endpointSetting || cfg.default || "";
            const ep = (cfg.endpoints || {})[root.endpoint];
            if (!ep) {
                root.notice = "ai.json has no endpoint '" + root.endpoint + "'";
                return;
            }
            root.endpointModel = ep.model || "";
            root.pickModel();
            modelsProc.running = true;
        }
    }

    // `haseen ai models`: one id per line; an info line when none are pulled.
    Process {
        id: modelsProc

        command: [root.cli, "ai", "models", "--endpoint", root.endpoint]
        stdout: StdioCollector {
            id: modelsOut
        }
        stderr: StdioCollector {
            id: modelsErr
        }
        onExited: code => {
            const lines = modelsOut.text.split("\n").filter(l => l.trim() !== "");
            root.models = lines.filter(l => !l.startsWith("[*] "));
            const info = lines.filter(l => l.startsWith("[*] ")).map(l => l.slice(4));
            root.notice = code !== 0 ? (modelsErr.text.trim() || "haseen ai models failed") : info.join("\n");
            root.pickModel();
        }
    }

    Process {
        id: chat

        property string pending: ""

        stdout: SplitParser {
            splitMarker: ""
            onRead: data => root.appendChunk(data)
        }
        stderr: SplitParser {
            onRead: line => root.errText += line + "\n"
        }
        onStarted: {
            write(pending);
            stdinEnabled = false;
        }
        onExited: code => root.finish(code)
    }

    // Header: endpoint and policy, model picker, new chat.
    Item {
        id: header

        anchors.left: parent.left
        anchors.right: parent.right
        height: Theme.fontSize * 2

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Glyph {
                glyph: "\udb81\udea9"
                color: Theme.accent
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.endpoint || "AI"
                color: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                font.bold: true
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.policy === "local" ? "local only" : root.policy === "any" ? "remote allowed" : ""
                color: root.policy === "local" ? Theme.success : Theme.warning
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize - 2
            }
        }

        Row {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            BarButton {
                height: parent.height
                glyph: "\uf078"
                text: root.model || "no model"
                color: root.model ? Theme.foreground : Theme.muted
                highlighted: root.picking
                onClicked: {
                    if (root.models.length === 0 && !modelsProc.running && root.endpoint !== "")
                        modelsProc.running = true;
                    root.picking = !root.picking && root.models.length > 0;
                }
            }

            BarButton {
                height: parent.height
                glyph: "\uf067"
                color: Theme.muted
                onClicked: root.newChat()
            }
        }
    }

    Text {
        id: noticeLine

        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        visible: root.notice !== ""
        text: root.notice
        color: Theme.warning
        wrapMode: Text.Wrap
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize - 1
    }

    ListView {
        id: list

        anchors.top: noticeLine.visible ? noticeLine.bottom : header.bottom
        anchors.topMargin: Theme.gap
        anchors.bottom: inputBox.top
        anchors.bottomMargin: Theme.gap
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        spacing: Theme.gap
        boundsBehavior: Flickable.StopAtBounds
        model: messages

        delegate: MessageView {
            width: ListView.view.width
            onCopyRequested: text => Quickshell.clipboardText = text
        }
    }

    Text {
        anchors.centerIn: list
        width: list.width - Theme.gap * 4
        visible: messages.count === 0
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: root.policy === "local" ? "Chats stay on this machine: the local policy only allows loopback endpoints." : "Ask anything."
        color: Theme.muted
        font.family: Theme.fontFamily
        font.pixelSize: Theme.fontSize
    }

    // Input: Enter sends, Shift+Enter breaks the line. Escape closes the
    // model picker, else stops a running reply, else closes the panel.
    Rectangle {
        id: inputBox

        readonly property int maxText: Theme.fontSize * 8

        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        height: Math.min(input.contentHeight, maxText) + Theme.gap * 2
        color: Theme.background
        radius: Theme.radius
        border.color: input.activeFocus ? Theme.accent : Theme.border
        border.width: Theme.borderWidth

        Flickable {
            id: inputScroll

            anchors.left: parent.left
            anchors.right: sendButton.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.margins: Theme.gap
            clip: true
            contentWidth: width
            contentHeight: input.contentHeight
            boundsBehavior: Flickable.StopAtBounds

            function follow(r: rect): void {
                if (r.y < contentY)
                    contentY = r.y;
                else if (r.y + r.height > contentY + height)
                    contentY = r.y + r.height - height;
            }

            TextEdit {
                id: input

                width: inputScroll.width
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: Theme.foreground
                selectionColor: Theme.selection
                selectedTextColor: Theme.foreground
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSize
                onCursorRectangleChanged: inputScroll.follow(cursorRectangle)

                Keys.onReturnPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier)
                        event.accepted = false;
                    else
                        root.send();
                }
                Keys.onEnterPressed: event => {
                    if (event.modifiers & Qt.ShiftModifier)
                        event.accepted = false;
                    else
                        root.send();
                }
                Keys.onEscapePressed: event => {
                    if (root.picking)
                        root.picking = false;
                    else if (root.busy)
                        root.stop();
                    else
                        event.accepted = false;
                }

                Text {
                    visible: input.text === ""
                    text: root.busy ? "Replying…" : "Message " + (root.model || root.endpoint || "the model")
                    color: Theme.muted
                    font: input.font
                }
            }
        }

        BarButton {
            id: sendButton

            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.fontSize + Theme.gap * 2
            glyph: root.busy ? "\uf04d" : "\uf1d8"
            color: root.busy ? Theme.urgent : input.text.trim() !== "" ? Theme.accent : Theme.muted
            onClicked: root.busy ? root.stop() : root.send()
        }
    }

    // Model picker, over the message list.
    Rectangle {
        anchors.top: header.bottom
        anchors.right: parent.right
        visible: root.picking
        z: 1
        width: Math.min(root.width, pickList.implicitWidth + Theme.gap * 2)
        height: pickList.implicitHeight + Theme.gap * 2
        color: Theme.surface
        radius: Theme.radius
        border.color: Theme.border
        border.width: Theme.borderWidth

        Column {
            id: pickList

            x: Theme.gap
            y: Theme.gap

            Repeater {
                model: root.models

                BarButton {
                    required property string modelData

                    height: Theme.fontSize * 2
                    text: modelData
                    highlighted: modelData === root.model
                    onClicked: {
                        root.model = modelData;
                        root.picking = false;
                        root.save();
                        input.forceActiveFocus();
                    }
                }
            }
        }
    }
}
