# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Launcher providers (plan 081): haseen.windows `@`, haseen.emojisearch `:`,
# haseen.commands `/` and haseen.websearch `?`. Each is its own plugin, off
# by default and turned on by `haseen plugin enable`. Their filter and
# ranking models run in the Qt JS engine; the launcher with all four enabled
# runs in the real Quickshell engine, where every action goes to a stub that
# records its argv (hyprctl, wl-copy, systemd-run for Apps.launch, qs).

PLUGINS="$HASEEN_PATH/shell/plugins"
IDS=(haseen.windows haseen.emojisearch haseen.commands haseen.websearch)

sandbox launcher-providers
for id in "${IDS[@]}"; do
    capture haseen plugin validate "$id"
    assert_status "$id validates" 0 "$STATUS"
    assert_eq "$id is a launcher provider" "launcher-provider" "$(jq -r '.kinds | join(" ")' "$PLUGINS/$id/manifest.json")"
    assert_eq "$id is off by default" "false" "$(jq -r --arg id "$id" '.plugins[$id].enabled' "$HASEEN_PATH/default/shell.json")"
    capture haseen plugin enable "$id"
    assert_status "haseen plugin enable $id" 0 "$STATUS"
    assert_eq "haseen plugin enable $id turns it on in the user shell.json" "true" \
        "$(jq -r --arg id "$id" '.plugins[$id].enabled' "$XDG_CONFIG_HOME/haseen/shell.json")"
    assert_eq "a launcher provider goes in no bar section and no service list" "0" \
        "$(jq --arg id "$id" '[(.bar // {} | .left, .center, .right), .services] | map(. // []) | add | map(select(. == $id)) | length' "$XDG_CONFIG_HOME/haseen/shell.json")"
done
capture haseen plugin disable haseen.websearch
assert_eq "haseen plugin disable turns one off again" "false" \
    "$(jq -r '.plugins["haseen.websearch"].enabled' "$XDG_CONFIG_HOME/haseen/shell.json")"
assert_eq "the web search template defaults to DuckDuckGo" "https://duckduckgo.com/?q=%s" \
    "$(jq -r '.settings.url.default' "$PLUGINS/haseen.websearch/manifest.json")"

# --- the models in the Qt JS engine ---------------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
{
    printf 'var defaultMenu = %s;\n' "$(jq -Rs . "$HASEEN_PATH/default/menu.jsonc")"
    printf 'var emojis = %s;\n' "$(cat "$PLUGINS/haseen.emoji/emojis.json")"
} >"$H/Data.js"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.windows/Windows.js" as W
import "file://$PLUGINS/haseen.emojisearch/Emoji.js" as E
import "file://$PLUGINS/haseen.commands/Commands.js" as C
import "file://$PLUGINS/haseen.menu/MenuModel.js" as M
import "file://$PLUGINS/haseen.websearch/WebSearch.js" as S
import "Data.js" as D

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }
    function addresses(list) {
        return list.map(w => w.address);
    }
    function glyphs(list) {
        return list.map(x => x.e);
    }
    function ids(list) {
        return list.map(r => r.id);
    }

    Component.onCompleted: {
        try {
            // Windows: rank and focus.
            const wins = [
                { address: "0x1a", title: "Mozilla Firefox — news", wmClass: "firefox", workspace: "2", focus: 1 },
                { address: "0x2b", title: "~/src: nvim", wmClass: "foot", workspace: "1", focus: 0 },
                { address: "0x3c", title: "Files", wmClass: "org.gnome.Nautilus", workspace: "special:scratch", focus: 2 },
                { address: "abc\")}) os.execute(\"x", title: "Bad", wmClass: "evil", workspace: "1", focus: 3 },
                { address: "0x4d", title: "Terminal", wmClass: "foot", workspace: "4", focus: 5 },
                { address: "0x5e", title: "Terminal", wmClass: "foot", workspace: "5", focus: 4 }
            ];
            eq("windows: empty query lists every window, most recent first", ["0x2b", "0x1a", "0x3c", "0x5e", "0x4d"], addresses(W.rank(wins, "")));
            eq("windows: a bad address is never listed", false, addresses(W.rank(wins, "bad")).length > 0);
            eq("windows: the title matches", "0x3c", addresses(W.rank(wins, "files"))[0]);
            eq("windows: the class matches", ["0x2b", "0x5e", "0x4d"], addresses(W.rank(wins, "foot")));
            eq("windows: the workspace name matches", ["0x3c"], addresses(W.rank(wins, "scratch")));
            eq("windows: a title beats a class", "0x1a", addresses(W.rank(wins, "fire"))[0]);
            eq("windows: equal titles go to the more recently focused", ["0x5e", "0x4d"], addresses(W.rank(wins, "terminal")));
            eq("windows: no match", [], W.rank(wins, "zzzz"));
            eq("windows: no windows", [], W.rank([], ""));
            eq("windows: hyprlang focus argv", ["hyprctl", "dispatch", "focuswindow", "address:0x1a"], W.focusArgv("0x1a", false));
            eq("windows: Lua focus argv", ["hyprctl", "dispatch", 'hl.dsp.focus({window = hl.get_window("address:0x1a")})'], W.focusArgv("0x1a", true));
            eq("windows: an address that is not hex runs nothing", [], W.focusArgv('0x1")}) os.execute("x', true));
            eq("windows: Quickshell's bare address gets its 0x", ["0x55d0", "0x55d0", ""], [W.normalAddress("55d0"), W.normalAddress("0x55d0"), W.normalAddress("")]);
            eq("windows: subtitle is class and workspace", "foot  ·  workspace 1", W.subtitle(wins[1]));
            eq("windows: a plain class is an icon-theme name", ["foot", "org.gnome.nautilus", "firefox-esr"], ["foot", "org.gnome.Nautilus", "firefox-esr"].map(W.themeIcon));
            eq("windows: a class that is a URL or a path never becomes an icon source",
               ["application-x-executable", "application-x-executable", "application-x-executable", "application-x-executable", "application-x-executable"],
               ["http://127.0.0.1:8765/window-class.png", "file:///etc/passwd", "/tmp/x/y.svg", "../x", "a b"].map(W.themeIcon));

            // Emoji: haseen.emoji's match, whole words first.
            const fx = [
                { e: "🍳", k: "cooking catering egg" },
                { e: "🦆", k: "duck bird scatter" },
                { e: "😺", k: "grinning cat" },
                { e: "🐱", k: "cat face pet" },
                { e: "😀", k: "grinning face" }
            ];
            eq("emoji: whole word, then word start, then substring", ["🐱", "😺", "🍳", "🦆"], glyphs(E.rank(fx, "cat", 50)));
            eq("emoji: the query is trimmed and lowercased", ["🐱", "😺", "🍳", "🦆"], glyphs(E.rank(fx, "  CAT ", 50)));
            eq("emoji: a phrase", ["😺"], glyphs(E.rank(fx, "grinning cat", 50)));
            eq("emoji: empty query keeps the data's order up to the limit", ["🍳", "🦆", "😺"], glyphs(E.rank(fx, "", 3)));
            eq("emoji: the limit holds for a query", ["🐱"], glyphs(E.rank(fx, "cat", 1)));
            eq("emoji: no match", [], E.rank(fx, "zzz", 50));
            eq("emoji: the real list loads", true, D.emojis.length > 1000);
            eq("emoji: cat in the real list: the cat-named emoji first", ["😹", "😼", "🐱", "🐈"], glyphs(E.rank(D.emojis, "cat", 4)));
            eq("emoji: red heart in the real list", "❤️", E.rank(D.emojis, "red heart", 50)[0].e);
            eq("emoji: 50 rows at most", 50, E.rank(D.emojis, "", 50).length);
            eq("emoji: Enter copies with wl-copy", ["wl-copy", "--", "❤️"], E.copyArgv("❤️"));

            // Commands: the menu's leaves, guards respected.
            const menu = M.mergeMenuSources(M.parseMenuJsonc(JSON.stringify({
                "style": { "label": "Style" },
                "style.theme": { "label": "Theme", "aliases": ["themes"], "action": "haseen theme pick" },
                "style.font": { "label": "Font", "description": "pick a font", "action": "haseen font pick" },
                "capture": { "label": "Capture" },
                "capture.stop": { "label": "Stop Recording", "when": "pgrep wf-recorder", "action": "haseen capture stop" },
                "laptop": { "label": "Laptop", "when": "test -d /sys/class/power_supply/BAT0" },
                "laptop.limit": { "label": "Charge Limit", "action": "haseen battery limit 80" },
                "display": { "label": "Display", "action": "haseen shell ipc panel toggle haseen.display" },
                "busy": { "label": "Busy Thing", "disabled": "true", "action": "haseen busy" },
                "gone": { "label": "Gone", "hidden": true },
                "gone.child": { "label": "Orphan", "action": "haseen orphan" },
                "dark": { "label": "Dark", "checked": "true", "action": "haseen dark" }
            })), []);
            const it = menu.items, order = menu.itemOrder;
            eq("commands: unknown guards hide guarded rows", ["style.theme", "style.font", "display", "dark"], ids(C.leaves(it, order, null)));
            eq("commands: a guard answered true shows its row", true, ids(C.leaves(it, order, { w: { "capture.stop": true }, c: {}, d: {} })).indexOf("capture.stop") >= 0);
            eq("commands: a guard answered false hides it", false, ids(C.leaves(it, order, { w: { "capture.stop": false }, c: {}, d: {} })).indexOf("capture.stop") >= 0);
            eq("commands: a submenu's when guards its leaves", [false, true],
               [ids(C.leaves(it, order, { w: { "laptop": false }, c: {}, d: {} })).indexOf("laptop.limit") >= 0,
                ids(C.leaves(it, order, { w: { "laptop": true }, c: {}, d: {} })).indexOf("laptop.limit") >= 0]);
            eq("commands: disabled shows only once it answered false", [false, true],
               [ids(C.leaves(it, order, { w: {}, c: {}, d: { "busy": true } })).indexOf("busy") >= 0,
                ids(C.leaves(it, order, { w: {}, c: {}, d: { "busy": false } })).indexOf("busy") >= 0]);
            eq("commands: a hidden submenu's leaves are not listed", false, ids(C.leaves(it, order, null)).indexOf("gone.child") >= 0);
            const rows = C.leaves(it, order, { w: {}, c: { "dark": true }, d: {} });
            eq("commands: the breadcrumb is the submenu path", ["Style", ""], [rows[0].path, rows[2].path]);
            eq("commands: a checked row keeps its ✓", "Dark ✓", rows[3].label);
            eq("commands: empty query keeps menu order", ["style.theme", "style.font", "display", "dark"], ids(C.rank(it, rows, "")));
            eq("commands: an alias finds a row", ["style.theme"], ids(C.rank(it, rows, "themes")));
            eq("commands: a description word finds a row", ["style.font"], ids(C.rank(it, rows, "pick")));
            eq("commands: the label prefix ranks first", "display", ids(C.rank(it, rows, "d"))[0]);
            eq("commands: no match", [], C.rank(it, rows, "zzz"));
            eq("commands: an action runs in bash with bin/ first", ["bash", "-c", 'PATH="\$1:\$PATH"; eval "\$2"', "bash", "/opt/haseen/bin", "haseen theme pick"],
               C.command("haseen theme pick", "/opt/haseen/bin").argv);
            eq("commands: a panel toggle stays in the shell", { panel: "haseen.display", argv: [] }, C.command("haseen shell ipc panel toggle haseen.display", "/b"));
            eq("commands: new guard answers merge over the cached ones", { w: { a: true, b: false }, c: { x: true }, d: {} },
               C.mergeGuards({ w: { a: false, b: false }, c: { x: true }, d: {} }, { w: { a: true }, c: {}, d: {} }));
            const real = M.mergeMenuSources(M.parseMenuJsonc(D.defaultMenu), []);
            const realRows = C.leaves(real.items, real.itemOrder, null);
            eq("commands: the default menu gives many unguarded commands", true, realRows.length > 50);
            eq("commands: no default row with an unknown when is listed", [], realRows.filter(r => r.entry.when !== "").map(r => r.id));
            eq("commands: update is found", true, C.rank(real.items, realRows, "update").length > 0);

            // Web search: the URL and the argv; only http(s) templates.
            const ddg = S.DEFAULT_TEMPLATE;
            eq("web: the query is percent-encoded", "https://duckduckgo.com/?q=a%20b%26c%3Dd%2F%C3%A9%23x", S.url(ddg, " a b&c=d/é#x "));
            eq("web: a literal %s in the query stays text", "https://duckduckgo.com/?q=100%25s", S.url(ddg, "100%s"));
            eq("web: every %s is filled", "https://example.org/s?x=q&y=q", S.url("https://example.org/s?x=%s&y=%s", "q"));
            eq("web: an empty query opens nothing", "", S.url(ddg, "   "));
            eq("web: http and https templates", [true, true, true], [S.validTemplate(ddg), S.validTemplate("http://localhost:8080/?q=%s"), S.validTemplate("HTTPS://Example.com/?q=%s")]);
            eq("web: other schemes, no host, spaces or no %s are refused", [false, false, false, false, false, false, false],
               [S.validTemplate("javascript:alert(1)//%s"), S.validTemplate("file:///etc/passwd?%s"), S.validTemplate("ftp://example.com/%s"),
                S.validTemplate("https:///?q=%s"), S.validTemplate("https://exa mple.com/%s"), S.validTemplate("https://duckduckgo.com/"),
                S.validTemplate("https://%s.example.com/")]);
            eq("web: a refused template opens nothing", "", S.url("file:///tmp/%s", "x"));
            eq("web: %s in the authority, userinfo, escapes or a backslash are refused (the query never picks the host)",
               [false, false, false, false, false, false, false, false],
               [S.validTemplate("https://search.%s/?q=fixed"), S.validTemplate("https://search.example%s/?q=%s"), S.validTemplate("https://example.com:%s/"),
                S.validTemplate("https://%s@example.com/?q=%s"), S.validTemplate("https://user@example.com/?q=%s"), S.validTemplate("https://exa%6dple.com/?q=%s"),
                S.validTemplate("https://example.com\\@evil.example/?q=%s"), S.validTemplate("https://example.com%s")]);
            eq("web: a hostname-slot template opens nothing", "", S.url("https://search.%s/?q=fixed", "attacker.example"));
            eq("web: IPv4, IPv6 and a port are fixed hosts", [true, true, true],
               [S.validTemplate("http://127.0.0.1:8888/search?q=%s"), S.validTemplate("http://[::1]:8888/?q=%s"), S.validTemplate("https://example.com./#q=%s")]);
            eq("web: the host is shown", ["duckduckgo.com", "www.google.com"], [S.host(ddg), S.host("https://www.google.com/search?q=%s")]);
            eq("web: xdg-open opens the URL", ["xdg-open", "https://duckduckgo.com/?q=x"], S.openArgv("https://duckduckgo.com/?q=x"));
            eq("web: nothing to open, nothing runs", [], S.openArgv(""));
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e + " " + e.stack);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    set -e
    while read -r line; do
        _fail "js: ${line#*UNIT-FAIL }"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "provider model unit count" "59" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the launcher with the four providers in the real engine -------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: qs missing; engine scenario not run" >&2
else
    sandbox launcher-providers-engine
    harness="$SANDBOX/shell"
    mkdir -p "$harness" "$XDG_CONFIG_HOME/haseen"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    LOG="$SANDBOX/argv.log"
    # Each stub logs "name|arg|arg…" in one write and exits 0.
    for name in hyprctl wl-copy systemd-run qs fakeapp; do
        stub "$name" "l='$name'; for a; do l=\"\$l|\$a\"; done; printf '%s\n' \"\$l\" >>'$LOG'"
    done
    cat >"$XDG_CONFIG_HOME/haseen/shell.json" <<'JSON'
{"bar":{"left":[],"center":[],"right":[]},"services":[],
 "plugins":{"haseen.windows":{"enabled":true},"haseen.emojisearch":{"enabled":true},
            "haseen.commands":{"enabled":true},"haseen.websearch":{"enabled":true}}}
JSON
    cat >"$XDG_CONFIG_HOME/haseen/menu.jsonc" <<'JSONC'
{
  // Fixture rows for the commands provider.
  "fixture": {"label":"Fixture"},
  "fixture.go": {"label":"Fixture Go","action":"fakeapp command \"two words\""},
  "fixture.guarded": {"label":"Fixture Guarded","when":"true","action":"fakeapp guarded"},
  "fixture.never": {"label":"Fixture Never","when":"false","action":"fakeapp never"},
  "fixture.panel": {"label":"Fixture Panel","action":"haseen shell ipc panel toggle haseen.display"}
}
JSONC
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.launcher" as Launcher
ShellRoot {
    id: probe

    property var launcher: null
    property var out: ({})
    property int step: 0

    function provider(id: string): var {
        return launcher.providers.find(p => p.pluginId === id);
    }
    function titles(): var {
        return launcher.results.map(r => r.title);
    }
    function pick(title: string): void {
        const row = launcher.results.find(r => r.title === title);
        if (row)
            row.run();
    }

    Component {
        id: launcherComponent
        Launcher.Panel {
            pluginId: "haseen.launcher"
        }
    }

    function put(key: string, value: var): void {
        const next = Object.assign({}, probe.out);
        next[key] = value;
        probe.out = next;
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (probe.step === 0 && Plugins.ready) {
                probe.launcher = launcherComponent.createObject(null, { settings: Plugins.settingsFor("haseen.launcher") });
                probe.put("providers", probe.launcher.providers.map(p => p.pluginId + "=" + p.prefix).sort());
                probe.put("help", probe.launcher.prefixHelp);
                probe.launcher.query = "?a b&c";
                probe.put("web", probe.titles());
                probe.launcher.results[0].run();
                probe.launcher.query = "@";
                probe.put("windowsEmpty", probe.titles());
                const rows = probe.provider("haseen.windows").rowsFor([
                    { address: "0xab12", title: "Fixture window", wmClass: "fakeapp", workspace: "3", focus: 0 }
                ], "fix");
                probe.put("windowRow", [rows[0].title, rows[0].subtitle]);
                // The launcher's own resolution: only image://icon/ (or
                // nothing, when the sandbox theme lacks the icon), never the
                // client's URL or path.
                const iconRows = probe.provider("haseen.windows").rowsFor([
                    { address: "0xab12", title: "Fixture window", wmClass: "fakeapp", workspace: "3", focus: 0 },
                    { address: "0xab13", title: "Hostile window", wmClass: "http://127.0.0.1:8765/window-class.png", workspace: "3", focus: 1 },
                    { address: "0xab14", title: "Path window", wmClass: "/etc/haseen-probe.svg", workspace: "3", focus: 2 }
                ], "");
                probe.put("windowIcons", iconRows.map(row => row.title + "=" + row.icon).sort());
                probe.put("windowSources", iconRows.every(row => {
                    const s = probe.launcher.iconSource(row.icon);
                    return s === "" || s.startsWith("image://icon/");
                }));
                rows[0].exec();
                probe.step = 1;
            } else if (probe.step === 1 && probe.provider("haseen.commands").defaultText !== "" && probe.provider("haseen.commands").userText !== "") {
                // The first `/` query: no guard has answered yet.
                probe.launcher.query = "/fixture";
                probe.put("commandsBefore", probe.titles());
                probe.step = 2;
            } else if (probe.step === 2 && probe.provider("haseen.emojisearch").emojis.length > 0 && probe.provider("haseen.commands").guards) {
                probe.put("commandsAfter", probe.titles());
                probe.put("commandsSubtitle", probe.launcher.results[0].subtitle);
                probe.pick("Fixture Go");
                probe.pick("Fixture Guarded");
                probe.pick("Fixture Panel");
                probe.launcher.query = ":red heart";
                probe.put("emoji", probe.titles().slice(0, 2));
                probe.launcher.results[0].run();
                // A second open: the shell-wide cache now holds this
                // open's answers, but a new open must not run a guarded row
                // on them before its own batch answers.
                probe.launcher.destroy();
                probe.launcher = launcherComponent.createObject(null, { settings: Plugins.settingsFor("haseen.launcher") });
                probe.step = 3;
            } else if (probe.step === 3 && probe.provider("haseen.commands").defaultText !== "" && probe.provider("haseen.commands").userText !== "") {
                probe.launcher.query = "/fixture";
                probe.put("commandsReopen", probe.titles());
                probe.step = 4;
                quit.start();
            }
        }
    }

    Timer {
        id: quit
        interval: 1500
        onTriggered: {
            console.warn("RESULT " + JSON.stringify(probe.out));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 "$QS_BIN" -p "$harness"
    assert_status "the launcher with four providers runs in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    ARGV="$(cat "$LOG" 2>/dev/null || true)"
    r() { jq -c "$1" <<<"${RESULT:-null}"; }
    assert_eq "the four providers load with their prefixes beside the default ones" \
        '["haseen.calculator==","haseen.clipboard=>","haseen.commands=/","haseen.emojisearch=:","haseen.websearch=?","haseen.windows=@"]' "$(r .providers)"
    for want in "@ Windows" ": Emoji search" "/ Commands" "? Web search"; do
        assert_contains "the empty launcher lists the prefix $want" "$(r .help)" "$want"
    done
    assert_eq "web: one row for the query" '["Search “a b&c”"]' "$(r .web)"
    assert_contains "web: Enter opens xdg-open through Apps.launch (its own scope)" "$ARGV" \
        "systemd-run|--user|--scope|--slice=app-graphical.slice|--collect|--quiet|--unit=app-haseen-haseen_websearch-"
    assert_contains "web: the URL is the template with the encoded query" "$ARGV" "|--|xdg-open|https://duckduckgo.com/?q=a%20b%26c"
    assert_eq "windows: without Hyprland the list says so" '["No open windows"]' "$(r .windowsEmpty)"
    assert_eq "windows: a row is the title over class and workspace" '["Fixture window","fakeapp  ·  workspace 3"]' "$(r .windowRow)"
    assert_contains "windows: Enter focuses it through hyprctl" "$ARGV" "hyprctl|dispatch|focuswindow|address:0xab12"
    assert_eq "windows: a client-set class that is a URL or a path becomes the generic icon" \
        '["Fixture window=fakeapp","Hostile window=application-x-executable","Path window=application-x-executable"]' "$(r .windowIcons)"
    assert_eq "windows: the launcher resolves every window icon through the icon theme only" "true" "$(r .windowSources)"
    assert_eq "commands: before the guards answer, guarded rows are left out" '["Fixture Go","Fixture Panel"]' "$(r .commandsBefore)"
    assert_eq "commands: after the batch, a guard that answered true shows, false never" \
        '["Fixture Go","Fixture Guarded","Fixture Panel"]' "$(r .commandsAfter)"
    assert_eq "commands: a new open never shows a guarded row on the cached answers of an earlier one" \
        '["Fixture Go","Fixture Panel"]' "$(r .commandsReopen)"
    assert_eq "commands: the breadcrumb is the subtitle" '"Fixture"' "$(r .commandsSubtitle)"
    assert_contains "commands: Enter runs the action in bash through Apps.launch" "$ARGV" \
        "|--|bash|-c|PATH=\"\$1:\$PATH\"; eval \"\$2\"|bash|$REPO/bin|fakeapp command \"two words\""
    assert_contains "commands: a guarded row that answered true runs" "$ARGV" "|fakeapp guarded"
    assert_not_contains "commands: a guard that answered false never runs" "$ARGV" "fakeapp never"
    assert_contains "commands: a panel toggle goes to this shell over qs ipc" "$ARGV" "|call|panel|toggle|haseen.display"
    assert_eq "emoji: :red heart lists the red heart first" '"❤️"' "$(r '.emoji[0] | split(" ")[0]')"
    assert_contains "emoji: Enter copies it with wl-copy" "$ARGV" "wl-copy|--|❤️"
    assert_not_contains "nothing reached a stubbed binary" "$OUTPUT" "STUB-CALLED"
fi
