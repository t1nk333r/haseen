import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import qs.Haseen.Widgets
import "Model.js" as Model

// Pending package updates in the bar (plan 095), adopted from the owner's
// t1nk33r.updates widget (MIT, Copyright (c) t1nk33r). `haseen update check`
// does the counting (checkupdates on a private database, the AUR helper's
// -Qua) and answers one JSON object; this file only shows it. With nothing
// pending the widget takes no room, as the original's empty text did; a
// failed check stays visible in the urgent colour, so an understated count is
// never taken for the truth.
//
// A left click runs `haseen update` (which opens its own floating terminal)
// in its own scope through Apps.launch, never Omarchy's updater; a right
// click opens the list (the panel). A check runs at start and every
// `interval` minutes; the command's flock and cache keep a bar per monitor
// from fetching more than once. The minute tick also re-reads the command's
// cache, so a check made elsewhere (the panel's Check now, another monitor,
// the CLI) reaches every bar within a minute without a fetch of its own.
// Off by default.
BarButton {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    // bin/ next to share/haseen, so a checkout runs its own commands.
    readonly property string binDir: Paths.haseenPath.replace(/\/share\/haseen\/?$/, "") + "/bin"
    // Where `haseen update check` caches a clean result.
    readonly property string cachePath: (Quickshell.env("XDG_RUNTIME_DIR") || Quickshell.env("TMPDIR") || "/tmp") + "/haseen/updates.json"
    readonly property int intervalMinutes: Model.intervalMinutes(settings.interval)
    // null until the first check answers.
    property var result: null
    // Minutes since the last check started, counted by the tick below.
    property int idleMinutes: 0
    // The cache as last read: a re-read showing the same text adopts nothing,
    // so a failed check of this widget is not papered over by an old result.
    property string seenCache: ""
    property bool cacheSeeded: false
    readonly property bool failed: result !== null && result.errors.length > 0
    readonly property bool active: Model.shown(result, settings.alwaysShow)

    visible: active
    implicitWidth: active ? contentWidth : 0
    glyph: failed ? "\u{F0026}" : "\u{F0BAF}"
    text: Model.countLabel(result, settings.splitAur === true)
    color: failed ? Theme.urgent : Theme.barForeground

    // The tooltip the Omarchy widget had and the port dropped: the summary
    // and the first `listLines` packages (plan 119).
    readonly property int tooltipLines: {
        const n = Number(settings.listLines);
        return Number.isFinite(n) && n > 0 ? Math.min(100, Math.floor(n)) : 20;
    }
    readonly property string barTooltip: {
        if (result === null)
            return "";
        return [I18n.tr(Model.summary(result, checkProc.running))]
            .concat(Model.listed(result, tooltipLines, I18n.tr)).join("\n");
    }

    function check(force: bool): void {
        idleMinutes = 0;
        if (checkProc.running)
            return;
        checkProc.command = [binDir + "/haseen-update-check"].concat(force ? ["--force"] : []);
        checkProc.running = true;
    }

    // The first read only records what was there before this widget's own
    // check; later changes are someone else's newer clean result.
    function adoptCache(text: string): void {
        const first = !cacheSeeded;
        cacheSeeded = true;
        if (text === seenCache)
            return;
        seenCache = text;
        if (!first && text.trim() !== "")
            result = Model.parse(text);
    }

    onClicked: button => {
        if (button === Qt.LeftButton)
            Apps.launch([root.binDir + "/haseen-update"]);
        else if (button === Qt.RightButton)
            Quickshell.execDetached(["qs", "ipc", "--pid", String(Quickshell.processId), "call", "panel", "toggle", root.pluginId]);
    }

    Component.onCompleted: check(false)

    Process {
        id: checkProc

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.result = Model.parse(text)
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.failed)
                root.result = Model.parse("");
        }
    }

    FileView {
        id: cache

        path: root.cachePath
        printErrors: false
        onLoaded: root.adoptCache(text())
        onLoadFailed: root.cacheSeeded = true
    }

    // One tick a minute while the widget exists: re-read the cache, and check
    // every `interval` minutes (30 by default, at least 2).
    // haseen:sample
    Timer {
        interval: 60000
        repeat: true
        running: root.pluginId !== ""
        onTriggered: {
            root.idleMinutes++;
            if (root.idleMinutes >= root.intervalMinutes)
                root.check(false);
            else
                cache.reload();
        }
    }
}
