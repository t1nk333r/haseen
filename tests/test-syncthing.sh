# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 098: haseen.syncthing, ported from ilyaZar's omarchy-syncthing without
# its prebuilt Go core. The manifest validates and the plugin is off by
# default; `haseen syncthing` reads config.xml and talks to the REST API
# through a fake curl (tests/fixtures/syncthing-curl.sh) with the key on a
# file descriptor; Model.js runs under the Qt JS engine; service, widget and
# panel run in the real Quickshell engine.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGIN="$SHELL_DIR/plugins/haseen.syncthing"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}
PEER=BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB-BBBBBBB
NEW=CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC-CCCCCCC

sandbox syncthing
LOG="$SANDBOX/log"
export FAKE_LOG="$LOG"
cp "$FIXTURES/syncthing-curl.sh" "$SANDBOX/stubs/curl"
mkdir -p "$XDG_STATE_HOME/syncthing"
cat >"$XDG_STATE_HOME/syncthing/config.xml" <<'EOF'
<configuration version="51">
    <gui enabled="true" tls="false" sendBasicAuthPrompt="false">
        <address>127.0.0.1:8384</address>
        <apikey>fixture-key</apikey>
        <theme>default</theme>
    </gui>
</configuration>
EOF

# --- manifest, contract and house rules ---------------------------------------
capture haseen plugin validate haseen.syncthing
assert_status "syncthing validates" 0 "$STATUS"
assert_contains "syncthing is a built-in" "$OUTPUT" "ok: haseen.syncthing (builtin:"
assert_not_contains "it asks for no internet access" "$OUTPUT" "warning:"
assert_eq "service, bar widget and panel" "service bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "off by default" "" \
    "$(jq -r '[.bar.left, .bar.center, .bar.right, .services] | add | map(select(. == "haseen.syncthing")) | .[]' "$HASEEN_PATH/default/shell.json")"
for f in Service.qml Widget.qml Panel.qml; do
    entry="$(cat "$PLUGIN/$f")"
    assert_contains "$f declares pluginId" "$entry" "property string pluginId"
    assert_contains "$f declares settings" "$entry" "property var settings: ({})"
    assert_contains "$f declares screen" "$entry" "property var screen: null"
done
for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGIN"/*.qml | cut -d. -f2 | sort -u); do
    assert_eq "declares the setting $key it reads" true "$(jq --arg k "$key" '.settings | has($k)' "$PLUGIN/manifest.json")"
done
assert_eq "no binary is shipped" "" "$(find "$PLUGIN" -type f ! -name '*.qml' ! -name '*.js' ! -name '*.json' || true)"
assert_eq "no hex colour literals" "" "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "$PLUGIN" --include='*.qml' --include='*.js' || true)"
# (omarchy-syncthing is the upstream repository's name, not a command)
assert_eq "no Omarchy dependency" "" "$(grep -rnE 'omarchy-|OMARCHY_PATH|qs\.Commons|qs\.Ui' "$PLUGIN" | grep -v 'omarchy-syncthing' || true)"
assert_eq "no repeating timer: Syncthing's long poll drives updates" "" "$(grep -n 'repeat: true' "$PLUGIN"/*.qml || true)"
assert_contains "the MIT notice is kept" "$(cat "$PLUGIN/Model.js")" "MIT, Copyright (c) 2026"
assert_contains "NOTICE.md lists the port" "$(cat "$REPO/NOTICE.md")" "haseen.syncthing"

# --- haseen syncthing against the fake REST API -----------------------------------
capture haseen syncthing status
assert_status "status succeeds" 0 "$STATUS"
assert_eq "status: folders with state, completion and sharing" \
    "[{\"id\":\"docs-1\",\"label\":\"Docs\",\"state\":\"syncing\",\"needBytes\":250,\"devices\":[\"$PEER\"]},{\"id\":\"pics\",\"label\":\"pics\",\"state\":\"idle\",\"needBytes\":0,\"devices\":[]}]" \
    "$(jq -c '[.folders[] | {id, label, state, needBytes, devices}]' <<<"$OUTPUT")"
assert_eq "status: other devices only, with connection" "[{\"id\":\"$PEER\",\"name\":\"Phone\",\"paused\":false,\"connected\":true}]" "$(jq -c .devices <<<"$OUTPUT")"
assert_eq "status: invitations" "[[{\"id\":\"$NEW\",\"name\":\"Laptop\",\"address\":\"192.0.2.4:22000\"}],[{\"id\":\"music\",\"device\":\"$PEER\",\"deviceName\":\"Phone\",\"label\":\"Music\"}]]" \
    "$(jq -c '[.pendingDevices, .pendingFolders]' <<<"$OUTPUT")"
assert_eq "status: the web interface" '"http://127.0.0.1:8384/"' "$(jq -c .guiUrl <<<"$OUTPUT")"
assert_eq "status: the API key never reaches argv or the log" "" "$(grep -F fixture-key "$LOG" || true)"
assert_eq "status: the folder id is URL-encoded" 1 "$(grep -c 'GET /rest/db/status?folder=docs-1' "$LOG")"

: >"$LOG"
capture haseen syncthing events --since 6 --timeout 30
assert_contains "events: one long poll after the last id" "$(cat "$LOG")" "GET /rest/events?since=6&timeout=30&events="
assert_eq "events: the reply as is" 8 "$(jq '.[-1].id' <<<"$OUTPUT")"
capture haseen syncthing events --timeout 999
assert_status "events: an absurd wait is refused" 64 "$STATUS"

: >"$LOG"
capture haseen syncthing pause docs-1
assert_eq "pause: one PATCH" 'PATCH /rest/config/folders/docs-1 {"paused":true}' "$(cat "$LOG")"
capture haseen syncthing rescan docs-1 --dry-run
assert_contains "dry run: prints the request" "$OUTPUT" "DRYRUN: POST http://127.0.0.1:8384/rest/db/scan?folder=docs-1"
assert_eq "dry run: sends nothing" 1 "$(wc -l <"$LOG")"
capture haseen syncthing share pics "$PEER" on
assert_eq "share: the device joins the folder" "PATCH /rest/config/folders/pics {\"devices\":[{\"deviceID\":\"AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA\"},{\"deviceID\":\"$PEER\"}]}" "$(tail -1 "$LOG")"
capture haseen syncthing share docs-1 "$PEER" off
assert_eq "unshare: the device leaves it" 'PATCH /rest/config/folders/docs-1 {"devices":[{"deviceID":"AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA-AAAAAAA"}]}' "$(tail -1 "$LOG")"
capture haseen syncthing accept-device "$NEW" Laptop
assert_eq "accept-device" "POST /rest/config/devices {\"deviceID\":\"$NEW\",\"name\":\"Laptop\"}" "$(tail -1 "$LOG")"
capture haseen syncthing dismiss-folder music "$PEER"
assert_eq "dismiss-folder" "DELETE /rest/cluster/pending/folders?folder=music&device=$PEER" "$(tail -1 "$LOG")"
capture haseen syncthing accept-folder music "$PEER" /srv/sync/music Music
assert_eq "accept-folder: a new folder shared with the offering device" "POST /rest/config/folders {\"id\":\"music\",\"label\":\"Music\",\"path\":\"/srv/sync/music\",\"devices\":[{\"deviceID\":\"$PEER\"}]}" "$(tail -1 "$LOG")"
capture haseen syncthing add-folder /srv/sync/notes --share "$PEER"
assert_status "add-folder succeeds" 0 "$STATUS"
assert_eq "add-folder: label from the path, a Syncthing-shaped id, shared" '"notes" true "/srv/sync/notes" 1' \
    "$(tail -1 "$LOG" | sed 's/^POST \/rest\/config\/folders //' | jq -r '"\"\(.label)\" \(.id | test("^[a-z0-9]{5}-[a-z0-9]{5}$")) \"\(.path)\" \(.devices | length)"')"
for bad in "add-folder relative/dir" "share docs-1 not-a-device on" "pause ../x" "accept-device nope"; do
    # shellcheck disable=SC2086 # the words are the arguments under test
    capture haseen syncthing $bad
    assert_status "refuses: $bad" 64 "$STATUS"
done
capture haseen syncthing service restart --dry-run
assert_eq "service: the user unit" "DRYRUN: systemctl --user restart syncthing.service" "$OUTPUT"

FAKE_ST_DOWN=1 capture haseen syncthing status
assert_status "status: 69 while Syncthing is down" 69 "$STATUS"
sed -i 's|127.0.0.1:8384|192.0.2.9:8384|' "$XDG_STATE_HOME/syncthing/config.xml"
capture haseen syncthing status
assert_status "status: a GUI off this machine is refused" 69 "$STATUS"
assert_contains "and says why" "$OUTPUT" "only talks to a local one"
sed -i 's|192.0.2.9:8384|0.0.0.0:8384|' "$XDG_STATE_HOME/syncthing/config.xml"
capture haseen syncthing gui-url
assert_eq "a wildcard GUI address is reached on loopback" "http://127.0.0.1:8384/" "$OUTPUT"
mv "$XDG_STATE_HOME/syncthing" "$SANDBOX/st-moved"
capture haseen syncthing status
assert_status "status: 69 without a config" 69 "$STATUS"
STCONFDIR="$SANDBOX/st-moved" capture haseen syncthing gui-url
assert_eq "STCONFDIR is honoured" "http://127.0.0.1:8384/" "$OUTPUT"
mv "$SANDBOX/st-moved" "$XDG_STATE_HOME/syncthing"

# --- Model.js under the Qt JS engine -------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    {
        printf 'var status = %s;\n' "$(haseen syncthing status | jq -Rs .)"
        printf 'var events = %s;\n' "$(haseen syncthing events | jq -Rs .)"
    } >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as M
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const s = M.parseStatus(D.status);
        out("folders", s.folders.map(f => [f.label, M.folderText(f), M.completion(f)]));
        out("overall", [M.overall(s, true), M.overall(s, false).kind, M.overall(null, true).kind]);
        const calm = M.parseStatus(D.status);
        calm.folders = calm.folders.map(f => Object.assign({}, f, { state: "idle", needBytes: 0, needFiles: 0 }));
        out("invited", M.overall(calm, true));
        calm.pendingDevices = []; calm.pendingFolders = [];
        out("idle", M.overall(calm, true));
        out("error", M.overall({ folders: [{ label: "X", paused: false, state: "error", error: "folder path missing", pullErrors: 0 }], devices: [], pendingDevices: [], pendingFolders: [] }, true));
        const e = M.parseEvents(D.events, 6, [{ item: "old" }]);
        out("events", [e.lastId, e.changed, e.activity.map(a => a.item), M.activityText(e.activity[0], s.folders)]);
        out("noevents", [M.parseEvents("[]", 9, []).lastId, M.parseEvents("garbage", 9, []).changed]);
        out("misc", [M.formatBytes(0), M.formatBytes(1536), M.formatBytes(5 * 1024 * 1024 * 1024), M.expandHome("~/Sync", "/srv/u"), M.expandHome("/abs", "/srv/u"), M.backoff(0, 60), M.backoff(3, 60), M.backoff(9, 300), M.backoff(9, 0)]);
        out("guards", [M.parseStatus("nope"), M.parseStatus('{"folders":[],"devices":[],"guiUrl":"http://example.test:80/"}').guiUrl]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "Model: folder lines" '[["Docs","Syncing 75%",75],["pics","Paused",100]]' "$(r folders)"
    assert_eq "Model: syncing wins; offline without an answer" '[{"kind":"syncing","text":"Docs: Syncing 75%"},"offline","offline"]' "$(r overall)"
    assert_eq "Model: invitations show next" '{"kind":"invited","text":"2 invitations"}' "$(r invited)"
    assert_eq "Model: then idle" '{"kind":"idle","text":"Up to date · 1 of 1 devices"}' "$(r idle)"
    assert_eq "Model: an error first" '{"kind":"error","text":"X: Error: folder path missing"}' "$(r error)"
    assert_eq "Model: events: last id, a change, activity newest first" '[8,true,["notes.md","old"],"Updated notes.md · Docs"]' "$(r events)"
    assert_eq "Model: no events, or garbage, change nothing" '[9,false]' "$(r noevents)"
    assert_eq "Model: bytes, home, backoff" '["0 B","1.5 KB","5.0 GB","/srv/u/Sync","/abs",5,40,300,60]' "$(r misc)"
    assert_eq "Model: bad input refused; a non-local web UI is not offered" '[null,""]' "$(r guards)"
else
    echo "  skip: $QML_BIN not installed, Model.js not exercised" >&2
fi

# --- service, widget and panel in the real engine -------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; engine scenario not run" >&2
else
    : >"$LOG"
    stub systemctl "echo active"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$SHELL_DIR/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.syncthing" as St
ShellRoot {
    id: shell

    property var first: null

    St.Service {
        id: svc

        pluginId: "haseen.syncthing"
        settings: ({ debugIpc: true })
    }

    St.Widget {
        id: widget

        pluginId: "haseen.syncthing"
        service: svc
    }

    St.Panel {
        pluginId: "haseen.syncthing"
        service: svc
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            shell.first = { online: svc.online, kind: svc.summary.kind, folders: svc.info.folders.length, activity: svc.activity.map(a => a.item), last: svc.lastEvent, service: svc.serviceState };
            shell.first.ran = svc.setPaused("docs-1", true);
            shell.first.second = svc.rescan("docs-1");
            shell.first.relative = svc.addFolder("relative");
            later.running = true;
        }
    }

    Timer {
        id: later

        interval: 1500
        onTriggered: {
            shell.first.message = svc.message;
            console.warn("RESULT " + JSON.stringify(shell.first));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "engine: harness completes (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    assert_eq "engine: Syncthing answered" true "$(jq .online <<<"$RESULT")"
    assert_eq "engine: the bar says syncing" '"syncing"' "$(jq -c .kind <<<"$RESULT")"
    assert_eq "engine: both folders" 2 "$(jq .folders <<<"$RESULT")"
    assert_eq "engine: the long poll brought the activity" '["notes.md"]' "$(jq -c '.activity | unique' <<<"$RESULT")"
    assert_eq "engine: and the last event id" 8 "$(jq .last <<<"$RESULT")"
    assert_eq "engine: the user unit's state" '"active"' "$(jq -c .service <<<"$RESULT")"
    assert_eq "engine: one change at a time" '[true,false]' "$(jq -c '[.ran, .second]' <<<"$RESULT")"
    assert_eq "engine: a relative folder is refused in the panel" false "$(jq .relative <<<"$RESULT")"
    assert_eq "engine: the change went through" '"Paused"' "$(jq -c .message <<<"$RESULT")"
    assert_contains "engine: as a PATCH" "$(cat "$LOG")" 'PATCH /rest/config/folders/docs-1 {"paused":true}'
    assert_contains "engine: long polls follow the last id" "$(cat "$LOG")" "GET /rest/events?since=8&timeout=60"
fi
