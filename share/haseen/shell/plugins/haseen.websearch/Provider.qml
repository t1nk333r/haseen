import QtQuick
import Quickshell
import qs.Haseen
import "WebSearch.js" as WebSearch

// Launcher provider (plan 081): `?text` opens a web search for text in the
// default browser: settings.url with %s replaced by the percent-encoded
// query, started as `xdg-open URL` through Apps.launch (its own scope, plan
// 074). The shell makes no network request; only http(s) templates open.
Scope {
    id: root

    // Contract (architecture 5.2): every entry component gets these.
    property string pluginId
    property var settings: ({})
    property var screen: null

    readonly property string prefix: "?"
    readonly property string template: typeof settings.url === "string" && settings.url.trim() !== "" ? settings.url.trim() : WebSearch.DEFAULT_TEMPLATE

    function open(target: string): void {
        const argv = WebSearch.openArgv(target);
        if (argv.length > 0)
            Apps.launch(argv, {
                desktopId: "haseen-websearch"
            });
    }

    function query(text: string): var {
        if (!WebSearch.validTemplate(template))
            return [
                {
                    title: "Web search is off: the URL template is not http(s)",
                    subtitle: "plugins.haseen.websearch.settings.url needs https://…%s",
                    icon: "dialog-warning",
                    glyph: "\uf071",
                    exec: () => {}
                }
            ];
        const target = WebSearch.url(template, text);
        if (target === "")
            return [
                {
                    title: "Web search",
                    subtitle: "Type what to search for on " + WebSearch.host(template),
                    icon: "web-browser",
                    glyph: "\uf002",
                    exec: () => {}
                }
            ];
        return [
            {
                title: "Search “" + text.trim() + "”",
                subtitle: WebSearch.host(template) + "  ·  Enter opens the browser",
                icon: "web-browser",
                glyph: "\uf002",
                exec: () => root.open(target)
            }
        ];
    }
}
