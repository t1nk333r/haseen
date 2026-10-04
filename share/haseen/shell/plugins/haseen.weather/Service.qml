import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
import "Weather.js" as Weather

// haseen.weather service: fetches wttr.in (`?format=j1`) with curl every 30
// minutes and on location change, and holds the parsed result for the bar
// widget and the panel (role `weather`). It exists only while the plugin is
// enabled (shell.json plugins.haseen.weather.enabled), so a disabled plugin
// makes no requests at all. Offline or a bad answer keeps the last good
// data and logs nothing: the widget simply stays as it was (or hidden).
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string location: typeof settings.location === "string" ? settings.location : ""
    readonly property bool imperial: settings.units === "imperial"
    // Last good parse (Weather.parse shape) or null.
    property var forecast: null
    // Raw JSON of the last good answer, re-parsed when units change.
    property string _raw: ""
    // Epoch ms of the last good answer; 0 = never.
    property real updated: 0
    property bool failed: false

    function refresh(): void {
        if (!fetch.running)
            fetch.running = true;
    }

    function accept(raw: string): bool {
        const parsed = Weather.parse(raw, imperial, new Date());
        if (!parsed.ok) {
            failed = true;
            return false;
        }
        _raw = raw;
        forecast = parsed;
        updated = Date.now();
        failed = false;
        return true;
    }

    // With the debugIpc test hook on, nothing is fetched on its own: a smoke
    // run loads a fixture (or calls refresh()) and never surprises wttr.in.
    readonly property bool autoFetch: settings.debugIpc !== true

    onLocationChanged: {
        if (autoFetch)
            refresh();
    }
    onImperialChanged: {
        if (_raw !== "")
            accept(_raw);
    }

    Process {
        id: fetch

        command: ["curl", "-fsS", "--max-time", "15", Weather.url(root.location)]
        stdout: StdioCollector {
            id: body
        }
        onExited: code => {
            if (code === 0)
                root.accept(body.text);
            else
                root.failed = true;
        }
    }

    // The service's job is a periodic fetch, every 30 min. It exists only
    // while the plugin is enabled, and pauses under the debugIpc hook.
    // haseen:sample
    Timer {
        interval: 1800000
        repeat: true
        running: root.autoFetch
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Test hook (settings.debugIpc): load a wttr.in j1 file instead of the
    // network, so a smoke run never depends on (or hits) wttr.in.
    FileView {
        id: fixture

        printErrors: false
        onLoaded: root.accept(text())
        onLoadFailed: root.failed = true
    }

    IpcHandler {
        target: "haseen.weather"
        enabled: root.settings.debugIpc === true

        function loadFixture(path: string): void {
            fixture.path = "";
            fixture.path = path;
        }

        function refresh(): void {
            root.refresh();
        }

        function state(): string {
            return JSON.stringify({
                location: root.location,
                imperial: root.imperial,
                failed: root.failed,
                updated: root.updated,
                forecast: root.forecast
            });
        }
    }
}
