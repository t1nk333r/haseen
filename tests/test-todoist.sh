# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-validate share/haseen/VERSION share/haseen/default/shell.json
# haseen:covers share/haseen/shell/Compat/** share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.todoist/** tools/smoke-session.conf NOTICE.md
# haseen:covers share/haseen/shell/plugins/*/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tests/test-todoist.sh — haseen.todoist (plan 097): the manifest (off by
# default, nothing in the default shell.json), naming and theme rules, the
# upstream and haseen node suites over Model.js, haseen-todoist.sh (the token
# only in a piped curl config, only to api.todoist.com, the legacy state
# directory used in place, 0700/0600, --dry-run), and the service, bar widget
# and panel in the real Quickshell engine against a scripted curl. The token
# is a fixture string, never a real one.

P="$HASEEN_PATH/shell/plugins/haseen.todoist"
M="$P/manifest.json"
H="$P/haseen-todoist.sh"
QS_BIN=${QS_BIN:-/usr/bin/qs}
TOKEN="fixture-token-0123456789"
export TOKEN

sandbox todoist

# --- manifest ---------------------------------------------------------------------
capture "$REPO/bin/haseen" plugin validate "$P"
assert_status "todoist manifest validates" 0 "$STATUS"
assert_eq "todoist id" "haseen.todoist" "$(jq -r .id "$M")"
assert_eq "todoist kinds" "service,bar-widget,panel" "$(jq -r '.kinds | join(",")' "$M")"
assert_eq "todoist provides" "todoist" "$(jq -r '.provides | join(",")' "$M")"
assert_eq "todoist debugIpc defaults off" "false" "$(jq -r .settings.debugIpc.default "$M")"
assert_eq "todoist is off by default: not in the default shell.json" "" \
    "$(jq -r '[.bar.left, .bar.center, .bar.right, .services, (.plugins | keys)] | add | map(select(. == "haseen.todoist")) | .[]' "$HASEEN_PATH/default/shell.json")"
assert_eq "todoist keeps the upstream licence" "yes" "$([[ -f $P/LICENSE && -f $P/UPSTREAM.md ]] && echo yes)"
assert_contains "todoist LICENSE is upstream MIT" "$(cat "$P/LICENSE")" "Copyright (c) 2026 aryan-techie"
assert_contains "NOTICE.md lists todoist" "$(cat "$REPO/NOTICE.md")" "share/haseen/shell/plugins/haseen.todoist/"

# --- naming and theme rules ---------------------------------------------------------
# Relative paths: the checkout's own path may contain the owner's user name.
code() { (cd "$P" && grep -rnI --include='*.qml' --include='*.js' --include='*.sh' --include='*.json' --exclude-dir=tests -v -E '^\s*(//|#)' .); }
assert_eq "todoist code has no Omarchy identifiers or imports" "" \
    "$(code | grep -E 'qs\.(Commons|Ui)\b|OMARCHY_PATH|omarchy-|"t1nk33r\.todoist"' || true)"
assert_eq "todoist QML has no hex colours" "" "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$P"/*.qml || true)"
assert_eq "every todoist Text is plain text" "" \
    "$(for f in "$P"/*.qml; do awk -v f="${f##*/}" '/^[[:space:]]*Text[[:space:]]*\{/ { open = FNR; plain = 0 } open && /textFormat: Text.PlainText/ { plain = 1 } open && /^[[:space:]]*\}/ { if (!plain) print f ":" open; open = 0 }' "$f"; done)"
assert_eq "no token or header in any argv the shell builds" "" \
    "$(grep -nE '"(Bearer|Authorization)|apiToken.*(command|push)' "$P"/*.qml || true)"

# --- node suites ----------------------------------------------------------------------
NODE=$(command -v node || true)
if [[ -n $NODE ]]; then
    for t in model haseen; do
        capture "$NODE" --test "$P/tests/$t.test.mjs"
        assert_status "todoist $t.test.mjs" 0 "$STATUS"
        ((STATUS == 0)) || printf '%s\n' "$OUTPUT" | tail -20 >&2
    done
else
    echo "  skip: node not installed (todoist model suites)" >&2
fi

# --- haseen-todoist.sh ----------------------------------------------------------------
LOG="$SANDBOX/curl.log"
CONF="$SANDBOX/curl.conf"
FIX="$SANDBOX/fixtures"
mkdir -p "$FIX"
today=$(date +%Y-%m-%d)
jq -n --arg today "$today" '{results: [
    {id: "101", content: "File the report", priority: 4, due: {date: "2001-01-01", string: "1 Jan"}},
    {id: "102", content: "Water <b>plants</b>", priority: 1, due: {date: $today, string: "today"}},
    {id: "103", content: "Call Sam", priority: 3, due: {date: $today, string: "today 9am"}}
], next_cursor: null}' >"$FIX/today.json"
jq -cn '{results: [range(0; 200) | {id: ("a" + tostring), content: "task"}], next_cursor: "more"}' >"$FIX/all-page.json"
export CURL_LOG="$LOG" CURL_CONF="$CONF" CURL_FIX="$FIX"
stub curl 'method=GET url=""
for a in "$@"; do
    case "$a" in
    /dev/fd/*) cat "$a" >>"$CURL_CONF" ;;
    esac
done
prev=""
for a in "$@"; do
    [ "$prev" = "-X" ] && method="$a"
    prev="$a"
    url="$a"
done
printf "%s %s ARGV:%s\n" "$method" "$url" "$*" >>"$CURL_LOG"
case "$method $url" in
"GET https://api.todoist.com/api/v1/tasks/filter"*) cat "$CURL_FIX/today.json"; printf "\n200" ;;
"GET https://api.todoist.com/api/v1/tasks?"*) cat "$CURL_FIX/all-page.json"; printf "\n200" ;;
"POST https://api.todoist.com/api/v1/tasks/quick") printf "{\"id\":\"104\"}\n200" ;;
"POST https://api.todoist.com/api/v1/tasks/"*"/close") printf "\n204" ;;
*) printf "{\"error\":\"nope\"}\n404" ;;
esac'

state="$XDG_STATE_HOME/haseen/todoist"
legacy="$HOME/.local/state/omarchy/t1nk33r.todoist"
capture "$H" dir
assert_eq "helper: haseen's state directory by default" "$state" "$OUTPUT"

capture bash -c 'printf "{\"apiToken\":\"%s\"}" "$TOKEN" | "$1" set --dry-run' _ "$H"
assert_status "helper set --dry-run" 0 "$STATUS"
assert_dry_pure "helper set" "$OUTPUT"
assert_not_contains "helper --dry-run never prints the token" "$OUTPUT" "$TOKEN"
assert_eq "helper --dry-run writes nothing" "no" "$([[ -e $state ]] && echo yes || echo no)"

capture bash -c 'printf "{\"apiToken\":\"%s\",\"barCountMode\":\"all\"}" "$TOKEN" | "$1" set' _ "$H"
assert_status "helper set" 0 "$STATUS"
assert_eq "helper: directory 0700, settings 0600" "700 600" "$(stat -c %a "$state") $(stat -c %a "$state/settings.json")"
capture bash -c 'printf "{\"filter\":\"#Work\"}" | "$1" set' _ "$H"
assert_eq "helper set merges keys" "all|#Work|true" "$(jq -r '[.barCountMode, .filter, (.apiToken == env.TOKEN)] | map(tostring) | join("|")' "$state/settings.json")"
capture bash -c 'printf "{\"apiToken\":\"x\",\"rm\":1}" | "$1" set' _ "$H"
assert_status "helper set refuses unknown keys" 1 "$STATUS"

: >"$LOG"
: >"$CONF"
capture "$H" api GET "tasks?limit=200"
assert_status "helper api" 0 "$STATUS"
assert_contains "helper api prints the body" "$OUTPUT" 'next_cursor":"more"}'
assert_eq "helper api ends with the HTTP status" "200" "$(tail -n1 <<<"$OUTPUT")"
assert_eq "helper api: the token is in the piped config only" "header = \"Authorization: Bearer $TOKEN\"" "$(cat "$CONF")"
assert_not_contains "helper api: no token in curl's argv" "$(cat "$LOG")" "$TOKEN"
assert_contains "helper api: https only, 10 s, status written out, no -f" "$(cat "$LOG")" "-sS --max-time 10 --proto =https -X GET -w"
for bad in "https://example.org/x" "tasks/../../x" "tasks?q=a b" "//evil/tasks"; do
    capture "$H" api GET "$bad"
    assert_status "helper api refuses '$bad'" 1 "$STATUS"
done
capture "$H" api PATCH tasks
assert_status "helper api refuses an unknown method" 1 "$STATUS"
assert_not_contains "nothing refused reached curl" "$(cat "$LOG")" "example.org"

mkdir -p "$legacy" && chmod 700 "$legacy"
printf 'header = "Authorization: Bearer old"\n' >"$legacy/curl-headers.conf"
printf '{"apiToken":"old","panelWidth":400}\n' >"$legacy/settings.json"
mv "$state" "$SANDBOX/haseen-todoist-moved"
capture "$H" dir
assert_eq "helper: the legacy directory is used in place when haseen has none" "$legacy" "$OUTPUT"
capture "$H" clear-token --dry-run
assert_dry_pure "helper clear-token" "$OUTPUT"
assert_eq "helper clear-token --dry-run keeps the token" "old" "$(jq -r .apiToken "$legacy/settings.json")"
capture "$H" clear-token
assert_status "helper clear-token" 0 "$STATUS"
assert_eq "helper clear-token: token gone, the rest kept" "null|400" "$(jq -r '[.apiToken, .panelWidth] | map(tostring) | join("|")' "$legacy/settings.json")"
assert_eq "helper clear-token empties upstream's header copy" "0" "$(stat -c %s "$legacy/curl-headers.conf")"
capture "$H" api GET tasks
assert_status "helper api without a token exits 3" 3 "$STATUS"
rm -rf "$legacy"
mv "$SANDBOX/haseen-todoist-moved" "$state"
capture "$H" dir
assert_eq "helper: haseen's directory again" "$state" "$OUTPUT"

# --- the plugin in the real Quickshell engine ----------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: Quickshell not installed; todoist engine scenarios not run" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "todoist: required engine prerequisite" available unavailable
else
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    mkdir -p "$XDG_CONFIG_HOME/haseen"
    printf '{"plugins":{"haseen.todoist":{"settings":{"debugIpc":true}}}}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
    printf '{"apiToken":"%s","barCountMode":"today"}\n' "$TOKEN" >"$state/settings.json"
    : >"$LOG"
    : >"$CONF"
    cat >"$harness/shell.qml" <<EOF
import QtQuick
import Quickshell
import qs.Haseen

ShellRoot {
    id: probe

    property var svc: null
    property var widget: null
    property var panel: null
    property int step: 0
    property int ticks: 0
    property var seen: ({})

    function make(file: string, props: var): var {
        const c = Qt.createComponent("file://$P/" + file);
        const o = c.createObject(win.contentItem, props);
        if (!o)
            console.log("RESULT " + JSON.stringify({ error: file + ": " + c.errorString() }));
        return o;
    }

    FloatingWindow {
        id: win

        visible: true
        implicitWidth: 420
        implicitHeight: 560
    }

    // haseen:ui-timeout
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (++probe.ticks > 300) {
                console.log("RESULT " + JSON.stringify({ error: "timeout at step " + probe.step, seen: probe.seen }));
                Qt.quit();
                return;
            }
            if (!probe.svc) {
                if (!Plugins.registry["haseen.todoist"])
                    return;
                probe.svc = probe.make("Service.qml", { pluginId: "haseen.todoist", settings: Qt.binding(() => Plugins.settingsFor("haseen.todoist")) });
                Plugins.registerRole("todoist", "haseen.todoist", probe.svc);
                return;
            }
            const s = probe.svc;
            if (probe.step === 0 && s.lastSyncedAt > 0 && !s.loading) {
                probe.widget = probe.make("Widget.qml", { pluginId: "haseen.todoist" });
                probe.panel = probe.make("Panel.qml", { pluginId: "haseen.todoist", width: 420, height: 520 });
                probe.seen.loaded = { stateDir: s.stateDir, tasks: s.tasks.map(t => t.id), overdue: s.overdueCount,
                    bar: probe.widget.text, glyph: probe.widget.glyph !== "", tooltip: s.tooltipText, panelOpen: s.panelOpen,
                    settingsView: probe.panel.settingsView };
                s.requestComplete("103");
                probe.step = 1;
            } else if (probe.step === 1 && s.completingTaskIds.length === 0 && !s.loading) {
                probe.seen.completed = { tasks: s.tasks.map(t => t.id) };
                s.submitQuickAdd("buy milk");
                probe.step = 2;
            } else if (probe.step === 2 && s.quickAddDone > 0 && !s.loading) {
                s.selectQuickView("all");
                probe.step = 3;
            } else if (probe.step === 3 && s.quickView === "all" && !s.loading && s.tasks.length > 3) {
                probe.seen.all = { tasks: s.tasks.length, truncated: s.listTruncated, stat: s.taskCount };
                probe.panel.destroy();
                probe.step = 4;
            } else if (probe.step === 4 && !s.panelOpen && s.writing === null && s.writes.length === 0) {
                probe.seen.closed = { panelOpen: s.panelOpen, error: s.errorText };
                console.log("RESULT " + JSON.stringify(probe.seen));
                Qt.quit();
            }
        }
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
    [[ -n $result ]] || _fail "todoist engine produced no result" "$OUTPUT"
    r() { jq -r "$1" <<<"${result:-"{}"}"; }
    assert_eq "engine: no error" "null" "$(r .error)"
    assert_eq "engine: state directory" "$state" "$(r .loaded.stateDir)"
    assert_eq "engine: Today list, overdue first, then by priority" "101,103,102" "$(r '.loaded.tasks | join(",")')"
    assert_eq "engine: one overdue" "1" "$(r .loaded.overdue)"
    assert_eq "engine: bar count is today's (the list's own count)" "3" "$(r .loaded.bar)"
    assert_eq "engine: the bar mark shows" "true" "$(r .loaded.glyph)"
    assert_eq "engine: tooltip" "Todoist: 3 today" "$(r .loaded.tooltip)"
    assert_eq "engine: an open panel tells the service" "true" "$(r .loaded.panelOpen)"
    assert_eq "engine: a token opens the task list, not Settings" "false" "$(r .loaded.settingsView)"
    assert_contains "engine: completing closes the task on the server" "$(cat "$LOG")" "POST https://api.todoist.com/api/v1/tasks/103/close"
    assert_contains "engine: quick add goes through Todoist's parser, due today" "$(cat "$LOG")" 'POST https://api.todoist.com/api/v1/tasks/quick ARGV:-sS --max-time 10 --proto =https -X POST -w \n%{http_code} -H Content-Type: application/json --data-binary {"text":"buy milk today"}'
    assert_eq "engine: All pages to the cap and says so" "2000|true|2000" "$(r '[.all.tasks, .all.truncated, .all.stat] | map(tostring) | join("|")')"
    assert_eq "engine: the All view was saved" "all" "$(jq -r .quickView "$state/settings.json")"
    assert_eq "engine: saving the view kept the token" "true" "$(jq -r '.apiToken == env.TOKEN' "$state/settings.json")"
    assert_eq "engine: a closed panel tells the service" "false|" "$(r '[.closed.panelOpen, .closed.error] | map(tostring) | join("|")')"
    assert_not_contains "engine: the token never reached an argv" "$(cat "$LOG")" "$TOKEN"
    assert_eq "engine: no QML warnings" "" "$(grep -E 'ReferenceError|TypeError|is not defined|Cannot read property|Unable to assign|Binding loop|haseen.todoist/.*(error|warning)' <<<"$OUTPUT" || true)"
fi
