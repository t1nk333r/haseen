# shellcheck shell=bash
# haseen:covers bin/haseen-notification-send bin/haseen-plugin-settings bin/haseen-plugin-validate
# haseen:covers share/haseen/VERSION share/haseen/default/shell.json share/haseen/shell/Compat/**
# haseen:covers share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.omarr/** tools/smoke-session.conf NOTICE.md
# haseen:covers share/haseen/shell/plugins/*/manifest.json
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# tests/test-omarr.sh — haseen.omarr (plan 097): the manifest (off by default,
# nothing in the default shell.json), naming and theme rules, the upstream
# model suite adapted to haseen, and the service, bar widget and panel in the
# real Quickshell engine against a scripted curl: upstream's legacy state
# directory used in place, the API key only in the 0600 header file, the
# notifications through `haseen notification send`, the live download card.
# Keys and addresses are fixture values on 127.0.0.1, never a real setup.

P="$HASEEN_PATH/shell/plugins/haseen.omarr"
M="$P/manifest.json"
QS_BIN=${QS_BIN:-/usr/bin/qs}
FIXTURE="fixture-sonarr-0123"
export FIXTURE

sandbox omarr

# --- manifest ---------------------------------------------------------------------
capture "$REPO/bin/haseen" plugin validate "$P"
assert_status "omarr manifest validates" 0 "$STATUS"
assert_eq "omarr id" "haseen.omarr" "$(jq -r .id "$M")"
assert_eq "omarr kinds" "service,bar-widget,panel" "$(jq -r '.kinds | join(",")' "$M")"
assert_eq "omarr provides" "omarr" "$(jq -r '.provides | join(",")' "$M")"
assert_eq "omarr defaults: no services, 30 s, 20 rows, comfortable, card on, debug off" "[]|30|20|comfortable|true|false" \
    "$(jq -r '.settings | [(.services.default | tojson), .pollSeconds.default, .pageSize.default, .density.default, .showProgressToast.default, .debugIpc.default] | map(tostring) | join("|")' "$M")"
assert_eq "omarr is off by default: not in the default shell.json" "" \
    "$(jq -r '[.bar.left, .bar.center, .bar.right, .services, (.plugins | keys)] | add | map(select(. == "haseen.omarr")) | .[]' "$HASEEN_PATH/default/shell.json")"
assert_contains "omarr LICENSE is upstream MIT" "$(cat "$P/LICENSE")" "Copyright (c) 2026 luccast"
assert_eq "omarr keeps UPSTREAM.md and the icons' notices" "yes" "$([[ -f $P/UPSTREAM.md && -f $P/icons/NOTICE && -f $P/icons/LICENSE-APACHE ]] && echo yes)"
assert_contains "NOTICE.md lists omarr" "$(cat "$REPO/NOTICE.md")" "share/haseen/shell/plugins/haseen.omarr/"
assert_contains "NOTICE.md lists the Apache-2.0 icons" "$(cat "$REPO/NOTICE.md")" "share/haseen/shell/plugins/haseen.omarr/icons/"

# --- naming and theme rules ---------------------------------------------------------
code() { (cd "$P" && grep -rnI --include='*.qml' --include='*.js' --include='*.json' --exclude-dir=tests -v -E '^\s*(//|#)' .); }
assert_eq "omarr code has no Omarchy commands or imports" "" \
    "$(code | grep -E 'qs\.(Commons|Ui)\b|OMARCHY_PATH|omarchy-|"omarchy"|"t1nk33r\.omarr"' || true)"
assert_eq "omarr QML has no hex colours" "" "$(grep -nE '"#[0-9a-fA-F]{3,8}"' "$P"/*.qml || true)"
assert_eq "omarr QML has no shader effects or endless animations" "" "$(grep -nE 'MultiEffect|layer\.effect|Animation\.Infinite' "$P"/*.qml | grep -v ':[0-9]*: *//' || true)"
assert_eq "every omarr Text is plain text" "" \
    "$(for f in "$P"/*.qml; do awk -v f="${f##*/}" '/^[[:space:]]*Text[[:space:]]*\{/ { open = FNR; plain = 0; depth = 0 } open { n = gsub(/\{/, "{"); m = gsub(/\}/, "}"); depth += n - m } open && /textFormat: Text.PlainText/ { plain = 1 } open && depth <= 0 && FNR > open - 1 && /\}/ { if (!plain) print f ":" open; open = 0 }' "$f"; done)"
assert_eq "the panel is lazy: no window of its own" "" "$(grep -nE '^\s*(PanelWindow|FloatingWindow|Window)\s*\{' "$P"/*.qml || true)"

# --- node suite -------------------------------------------------------------------------
NODE=$(command -v node || true)
if [[ -n $NODE ]]; then
    capture "$NODE" "$P/tests/Model.test.js"
    assert_status "omarr Model.test.js" 0 "$STATUS"
    ((STATUS == 0)) || printf '%s\n' "$OUTPUT" | tail -20 >&2
else
    echo "  skip: node not installed (omarr model suite)" >&2
fi

# --- the plugin in the real Quickshell engine ----------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: Quickshell not installed; omarr engine scenarios not run" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "omarr: required engine prerequisite" available unavailable
else
    LOG="$SANDBOX/curl.log"
    NOTES="$SANDBOX/notify.log"
    FIX="$SANDBOX/fixtures"
    mkdir -p "$FIX"
    cp "$P/tests/fixtures/sonarr-queue.json" "$FIX/sonarr-queue.json"
    printf '{"appName":"Sonarr","version":"4.0.9"}' >"$FIX/status.json"
    printf '{"queue":{"paused":false,"speed":"3.1 M","kbpersec":"3174","timeleft":"0:04:12","noofslots":1,"slots":[{"nzo_id":"SABnzbd_nzo_1","filename":"Fixture.Show.S01E02","status":"Downloading","mb":"1000","mbleft":"580","percentage":"42","timeleft":"0:04:12"}]}}' >"$FIX/sab-queue.json"
    printf '{"history":{"slots":[]}}' >"$FIX/sab-history.json"
    export CURL_LOG="$LOG" CURL_FIX="$FIX" NOTIFY_LOG="$NOTES"
    stub curl 'url="" body=""
prev=""
for a in "$@"; do
    case "$prev" in --data-binary) body="${a#@}" ;; esac
    prev="$a"
    url="$a"
done
printf "%s\n" "$*" >>"$CURL_LOG"
case "$url" in
*/api/v3/system/status) cat "$CURL_FIX/status.json"; printf "\n200" ;;
*/api/v3/queue*) cat "$CURL_FIX/sonarr-queue.json"; printf "\n200" ;;
*/api/v3/calendar*) printf "[]\n200" ;;
*/api/v3/history*) printf "{\"records\":[]}\n200" ;;
*/api)
    if grep -q "mode=history" "$body" 2>/dev/null; then cat "$CURL_FIX/sab-history.json"; else cat "$CURL_FIX/sab-queue.json"; fi
    printf "\n200" ;;
*) printf "\n404" ;;
esac'
    # The download card's sender: prints an id, then waits like notify-send -A.
    # An event toast (its action is Open) answers as one that expired unclicked.
    stub notify-send 'printf "%s\n" "$*" >>"$NOTIFY_LOG"
for a in "$@"; do [ "$a" = "exec=Open" ] && { echo 8; exit 0; }; done
for a in "$@"; do [ "$a" = "-A" ] && { echo 7; exec sleep 30; }; done
for a in "$@"; do [ "$a" = "-p" ] && echo 7; done
exit 0'

    legacy="$HOME/.local/state/omarchy/omarr"
    mkdir -p "$legacy" && chmod 700 "$legacy"
    printf '{"svc-1":{"apiKey":"%s"}}\n' "$FIXTURE" >"$legacy/credentials.json"
    chmod 600 "$legacy/credentials.json"
    mkdir -p "$XDG_CONFIG_HOME/haseen"
    jq -n '{plugins: {"haseen.omarr": {settings: {debugIpc: true, pollSeconds: 60, services: [
        {id: "svc-1", kind: "sonarr", name: "Sonarr", url: "http://127.0.0.1:8989"},
        {id: "svc-2", kind: "sabnzbd", name: "SABnzbd", url: "http://127.0.0.1:8080"}]}}}}' >"$XDG_CONFIG_HOME/haseen/shell.json"

    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
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

    function up(): bool {
        return svc.snapshots.length === 2 && svc.snapshots.every(s => s.health === "up");
    }

    // Where each scroll mark (2 px, with a view) sits: "end" on its view's
    // right edge, else its x and the view's width.
    function marks(item: var, out: var): var {
        for (let i = 0; i < item.children.length; i++) {
            const c = item.children[i];
            if (c.view && c.width === 2)
                out.push(c.x === c.view.width - c.width ? "end" : "x=" + c.x + "/" + c.view.width);
            probe.marks(c, out);
        }
        return out;
    }

    FloatingWindow {
        id: win

        visible: true
        implicitWidth: 900
        implicitHeight: 720
    }

    // haseen:ui-timeout
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (++probe.ticks > 300) {
                console.log("RESULT " + JSON.stringify({ error: "timeout at step " + probe.step, seen: probe.seen,
                    snaps: probe.svc ? probe.svc.snapshots.map(s => s.id + ":" + s.health) : [] }));
                Qt.quit();
                return;
            }
            if (!probe.svc) {
                if (!Plugins.registry["haseen.omarr"])
                    return;
                probe.svc = probe.make("Service.qml", { pluginId: "haseen.omarr", settings: Qt.binding(() => Plugins.settingsFor("haseen.omarr")) });
                Plugins.registerRole("omarr", "haseen.omarr", probe.svc);
                return;
            }
            const s = probe.svc;
            if (probe.step === 0 && s.dirsReady && probe.up() && s.progressNoteId !== "" && s.reqQueue.length === 0) {
                probe.widget = probe.make("Widget.qml", { pluginId: "haseen.omarr" });
                probe.panel = probe.make("Panel.qml", { pluginId: "haseen.omarr", width: 880, height: 700 });
                probe.seen.loaded = { stateDir: s.stateDir, statusText: s.statusText, badge: s.badgeCount, urgent: s.badgeUrgent,
                    bar: probe.widget.text, glyph: probe.widget.glyph !== "", panelOpen: s.panelOpen,
                    downloads: s.nowFeed.downloadingCount, job: s.progressJob ? s.progressJob.title : "", noteId: s.progressNoteId,
                    sonarr: s.snapshots[0].statusText, queue: s.snapshots[0].queue.length };
                probe.panel.showSettings = true;
                // An event notification: the notification server keeps it,
                // so the bar badge must not count it.
                s.sendToast({ type: "grabbed", serviceName: "Sonarr", body: "Fixture Show" }, s.services[0]);
                probe.step = 1;
            } else if (probe.step === 1) {
                probe.seen.toast = { bar: probe.widget.text, badge: s.badgeCount, unread: typeof s.unreadCount };
                probe.seen.settings = { loaded: !!probe.panel.children };
                probe.panel.showSettings = false;
                probe.panel.detailId = "svc-1";
                probe.step = 2;
            } else if (probe.step === 2) {
                probe.seen.marks = probe.marks(probe.panel, []).join(",");
                probe.panel.detailId = "";
                probe.panel.destroy();
                probe.step = 3;
            } else if (probe.step === 3 && !s.panelOpen) {
                probe.seen.closed = { panelOpen: s.panelOpen };
                // Turning the card off closes it: its sender is stopped.
                s.persistSettings({ showProgressToast: false });
                probe.step = 4;
            } else if (probe.step === 4 && s.progressNoteId === "" && s.settingsWriting === null && s.settingsWrites.length === 0) {
                probe.seen.cardOff = { noteId: s.progressNoteId, dismissed: s.progressDismissedKey };
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
    [[ -n $result ]] || _fail "omarr engine produced no result" "$OUTPUT"
    r() { jq -r "$1" <<<"${result:-"{}"}"; }
    assert_eq "engine: no error" "null" "$(r .error)"
    assert_eq "engine: upstream's state directory used in place" "$legacy" "$(r .loaded.stateDir)"
    assert_eq "engine: the legacy credentials were not moved" "yes" "$([[ -f $legacy/credentials.json && ! -e $XDG_STATE_HOME/haseen/omarr ]] && echo yes || echo no)"
    assert_eq "engine: Sonarr identified with the stored key" "Sonarr 4.0.9" "$(r .loaded.sonarr)"
    assert_eq "engine: one download running" "1" "$(r .loaded.downloads)"
    assert_eq "engine: the bar badge counts it" "1|false|1|true" "$(r '[.loaded.badge, .loaded.urgent, .loaded.bar, .loaded.glyph] | map(tostring) | join("|")')"
    assert_eq "engine: an open panel tells the service" "true" "$(r .loaded.panelOpen)"
    assert_eq "engine: the download card follows the job" "Fixture.Show.S01E02|7" "$(r '[.loaded.job, .loaded.noteId] | join("|")')"
    assert_contains "engine: the card is a waiting haseen notification with the client's icon" "$(cat "$NOTES")" "-a omARR -u low -i $harness/plugins/haseen.omarr/icons/sabnzbd.svg -t 0 -p -A exec=Hide -- Fixture.Show.S01E02 42% · 3.1 MB/s · 4m left · SABnzbd"
    assert_eq "engine: the scroll marks sit on their views' right edge" "end,end,end" "$(r .marks)"
    assert_contains "engine: an event goes to the notification server" "$(cat "$NOTES")" "-a omARR -u low -i $harness/plugins/haseen.omarr/icons/sonarr.svg -p -A exec=Open -- Sonarr grabbed Fixture Show"
    assert_eq "engine: the bar badge does not count it, the server keeps it" "1|1|undefined" "$(r '[.toast.bar, .toast.badge, .toast.unread] | map(tostring) | join("|")')"
    assert_eq "engine: the feed carries no unread tally" "false|true" "$(jq -r '[has("unreadCount"), has("badgeCount")] | map(tostring) | join("|")' "$legacy/feed.json" 2>&1)"
    assert_eq "engine: a closed panel tells the service" "false" "$(r .closed.panelOpen)"
    assert_eq "engine: turning the card off closes it without hiding the job" "|" "$(r '[.cardOff.noteId, .cardOff.dismissed] | join("|")')"
    assert_eq "engine: the setting was saved" "false" "$(jq -r '.plugins["haseen.omarr"].settings.showProgressToast' "$XDG_CONFIG_HOME/haseen/shell.json")"
    assert_eq "engine: saving kept the fleet in shell.json" "2" "$(jq -r '.plugins["haseen.omarr"].settings.services | length' "$XDG_CONFIG_HOME/haseen/shell.json")"
    assert_not_contains "engine: the API key never reached an argv" "$(cat "$LOG")" "$FIXTURE"
    assert_not_contains "engine: nor shell.json" "$(cat "$XDG_CONFIG_HOME/haseen/shell.json")" "$FIXTURE"
    assert_contains "engine: the key travels in the private header file" "$(cat "$LOG")" "-H @$XDG_CACHE_HOME/haseen/omarr/header.txt"
    # The first poll waits for credentials.json: none of Sonarr's requests
    # goes out without its key (CI once saw all four of them bare).
    assert_eq "engine: every Sonarr request carries the header" "" "$(grep ':8989/' "$LOG" | grep -v -- "-H @$XDG_CACHE_HOME/haseen/omarr/header.txt" || true)"
    assert_eq "engine: the cache directory is private" "700" "$(stat -c %a "$XDG_CACHE_HOME/haseen/omarr")"
    assert_eq "engine: no QML warnings" "" "$(grep -E 'ReferenceError|TypeError|is not defined|Cannot read property|Unable to assign|Binding loop|Cannot anchor|Cannot open|haseen.omarr/.*(error|warning)' <<<"$OUTPUT" || true)"

    # Fail closed: a credentials file that cannot be read stops polling
    # instead of sending the requests without their keys; repairing it in
    # place starts polling again, with the header.
    printf 'not json\n' >"$legacy/credentials.json"
    : >"$LOG"
    # Run by the probe to repair the file in place (the key stays in env),
    # keeping the bytes it found there.
    repair="$SANDBOX/repair-creds.sh"
    printf '%s\n' "cp -- '$legacy/credentials.json' '$SANDBOX/creds-before-repair'" >"$repair"
    printf '%s\n' "printf '{\"svc-1\":{\"apiKey\":\"%s\"}}\\n' \"\$FIXTURE\" >'$legacy/credentials.json'" >>"$repair"
    # The permission step needs a reader that permissions stop: not root.
    denied=true
    [[ $(id -u) != 0 ]] || { denied=false; echo "  skip: running as root; the unreadable-credentials step is not run" >&2; }
    harness2="$SANDBOX/shell-creds"
    mkdir -p "$harness2"
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$harness/$module" "$harness2/$module"
    done
    cat >"$harness2/shell.qml" <<EOF
import QtQuick
import Quickshell
import qs.Haseen

ShellRoot {
    id: probe

    property var svc: null
    property int step: 0
    property int ticks: 0
    property int held: 0
    property var seen: ({})
    // A second fixture value, offered while the file cannot be read.
    readonly property string refused: "fixture-other-0456"

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
                if (!Plugins.registry["haseen.omarr"])
                    return;
                const c = Qt.createComponent("file://$P/Service.qml");
                probe.svc = c.createObject(probe, { pluginId: "haseen.omarr", settings: Qt.binding(() => Plugins.settingsFor("haseen.omarr")) });
                return;
            }
            const s = probe.svc;
            if (probe.step === 0 && s.dirsReady && s.credsState === "error" && s.services.length === 2) {
                // What would queue requests and write keys: opening the panel,
                // editing a service with a new key.
                s.panelOpen = true;
                s.updateService("svc-1", {}, { apiKey: probe.refused });
                probe.step = 1;
            } else if (probe.step === 1) {
                // Hold 2 s: long enough for the polls that would have run.
                if (++probe.held < 20)
                    return;
                probe.seen.broken = { credsState: s.credsState, ready: s.ready, queued: s.reqQueue.length,
                    status: s.statusText };
                Quickshell.execDetached(["sh", "$repair"]);
                probe.step = 2;
            } else if (probe.step === 2 && s.credsState === "ok" && s.snapshots.length === 2 && s.snapshots[0].health === "up"
                && s.reqQueue.length === 0 && s.currentReq === null) {
                // Only once the repaired poll has drained (the open panel's
                // wanted/missing is queued last): the permission step below
                // drops whatever is still queued.
                probe.seen.repaired = { credsState: s.credsState, sonarr: s.snapshots[0].statusText };
                if (!$denied) {
                    console.log("RESULT " + JSON.stringify(probe.seen));
                    Qt.quit();
                    return;
                }
                Quickshell.execDetached(["chmod", "000", "$legacy/credentials.json"]);
                probe.step = 3;
            } else if (probe.step === 3 && s.credsState === "error") {
                probe.seen.denied = { why: s.credsWhy, ready: s.ready };
                Quickshell.execDetached(["chmod", "600", "$legacy/credentials.json"]);
                probe.step = 4;
            } else if (probe.step === 4 && s.credsState === "ok") {
                probe.seen.restored = { ready: s.ready };
                console.log("RESULT " + JSON.stringify(probe.seen));
                Qt.quit();
            }
        }
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness2"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | tail -n1)"
    [[ -n $result ]] || _fail "omarr credentials engine produced no result" "$OUTPUT"
    assert_eq "engine: no error with broken credentials" "null" "$(r .error)"
    assert_eq "engine: unreadable credentials stop polling, even with the panel open and a service edited" "error|false|0" "$(r '[.broken.credsState, .broken.ready, .broken.queued] | map(tostring) | join("|")')"
    assert_eq "engine: the panel says the keys are unreadable" "Keys unreadable" "$(r .broken.status)"
    assert_eq "engine: a new key is not written over an unreadable file" "not json" "$(cat "$SANDBOX/creds-before-repair" 2>/dev/null)"
    assert_contains "engine: and the refusal is logged" "$OUTPUT" "haseen.omarr: not saving keys: $legacy/credentials.json cannot be read"
    assert_contains "engine: and say why" "$OUTPUT" "haseen.omarr: cannot read $legacy/credentials.json - is not a JSON object - not polling until it can be read"
    assert_eq "engine: repaired in place, polling resumes" "ok|Sonarr 4.0.9" "$(r '[.repaired.credsState, .repaired.sonarr] | join("|")')"
    assert_eq "engine: no request went out while the keys were unknown, each later one with the header" "" \
        "$(grep ':8989/' "$LOG" | grep -v -- "-H @$XDG_CACHE_HOME/haseen/omarr/header.txt" || true)"
    assert_contains "engine: the repaired key was used" "$(cat "$LOG")" ":8989/api/v3/system/status"
    assert_contains "engine: the open panel's requests came after the repair" "$(cat "$LOG")" ":8989/api/v3/wanted/missing"
    assert_eq "engine: the refused key never reached the file" "no" "$(grep -q fixture-other "$legacy/credentials.json" && echo yes || echo no)"
    if [[ $denied == true ]]; then
        assert_eq "engine: a credentials file it may not read holds polling" "Permission denied|false" "$(r '[.denied.why, .denied.ready] | map(tostring) | join("|")')"
        assert_eq "engine: readable again, polling resumes" "true" "$(r .restored.ready)"
    fi
    assert_not_contains "engine: the repaired key never reached an argv" "$(cat "$LOG")" "$FIXTURE"
fi
