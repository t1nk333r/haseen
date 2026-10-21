# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 096: four of the owner's forks adopted as built-in plugins, off by
# default: haseen.typist, haseen.settings, haseen.browser-picker, haseen.vpn.
# Manifests and contracts; the forks' own suites (browser-picker model and
# scanner, VPN models) under node and bash; the typist worker, CLI and
# picker, the browser-picker shim, the OpenConnect helper; the pure JS under
# the Qt JS engine; each plugin in the real engine (qs, offscreen); and the
# migration that re-points the old ids. Nothing here types into a session,
# opens a browser or touches a VPN.

PLUGINS="$HASEEN_PATH/shell/plugins"
IDS=(haseen.typist haseen.settings haseen.browser-picker haseen.vpn)
OLD=(t1nk33r.typist t1nk33r.settings t1nk33r.browser-picker t1nk33r.vpn)
QS_BIN=${QS_BIN:-/usr/bin/qs}
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
MIG=1791560100-adopt-tools-forks.sh

engine_skip() {
    echo "  skip: $1" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} == 1 ]] && assert_eq "$1: required engine prerequisite" available unavailable
    return 0
}

# harness DIR — a shell dir whose modules and plugins are the tree's.
harness() {
    mkdir -p "$1"
    for module in Haseen Compat Ui Commons; do ln -s "$HASEEN_PATH/shell/$module" "$1/$module"; done
    ln -s "$HASEEN_PATH/shell/plugins" "$1/plugins"
}

# engine DIR ENV... — run the harness in DIR offscreen; OUTPUT/STATUS set.
engine() {
    local dir=$1
    shift
    # The ENV applies to qs alone, so a scenario can narrow its PATH.
    capture timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- \
        env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 "$@" "$QS_BIN" -p "$dir"
}

result() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT" | head -n1; }

have_engine() { [[ -x $QS_BIN ]] && command -v dbus-run-session >/dev/null; }

# --- manifests, contracts, off by default --------------------------------------
sandbox adopted-validate
# haseen.typist requires wl-paste, which a CI image need not have; without it
# validate reports the plugin unmet and exits 1.
stub wl-paste 'exit 0'
capture haseen plugin validate "${IDS[@]}"
assert_status "the four adopted plugins validate" 0 "$STATUS"
for id in "${IDS[@]}"; do
    assert_contains "$id ok" "$OUTPUT" "ok: $id (builtin:"
done
# haseen.vpn asks checkip.amazonaws.com for the exit address; nothing else
# here reaches the network.
assert_eq "only haseen.vpn requests network" "1" "$(grep -c '^warning:' <<<"$OUTPUT")"
assert_eq "haseen.vpn declares network" "exec network" "$(jq -r '.permissions | join(" ")' "$PLUGINS/haseen.vpn/manifest.json")"
DEFAULT="$HASEEN_PATH/default/shell.json"
# CLAUDE.md's adopted list wraps; read it with the line breaks folded.
ADOPTED=$(tr -s ' \n' ' ' <"$REPO/CLAUDE.md")
assert_contains "CLAUDE.md records the adoption as first-party, off by default" "$ADOPTED" \
    "Adopted as first-party plugins, off by default (owner, 2026-10-20)."
ADOPTED_096=$(grep -o 'plan 096, [^;]*;' <<<"$ADOPTED")
for id in "${IDS[@]}"; do
    dir="$PLUGINS/$id"
    assert_eq "$id is off by default (in no default section or service)" "false" \
        "$(jq --arg id "$id" '[.bar.left, .bar.center, .bar.right, .services] | add | index($id) != null' "$DEFAULT")"
    assert_eq "$id keeps the upstream licence" "MIT License" "$(head -n1 "$dir/LICENSE")"
    assert_contains "$id records its upstream" "$(cat "$dir/UPSTREAM.md")" "plan \`plans/096-adopt-tools-forks.md\`"
    assert_contains "NOTICE.md lists $id" "$(cat "$REPO/NOTICE.md")" "share/haseen/shell/plugins/$id/"
    assert_contains "CLAUDE.md records the owner's adoption of $id" "$ADOPTED_096" "$id"
    for f in "$dir"/*.qml; do
        # An adapted file names its upstream and licence; a file written for
        # the port says it holds no upstream code.
        assert_eq "${f#"$PLUGINS"/}: says where it comes from" "1" "$(head -n12 "$f" | grep -cE 'MIT|no upstream code' | sed 's/^[1-9][0-9]*$/1/')"
    done
    for kind in $(jq -r '.kinds[]' "$dir/manifest.json"); do
        entry="$dir/$(jq -r --arg k "$kind" '.entry[$k]' "$dir/manifest.json")"
        assert_contains "$id $kind entry takes pluginId" "$(cat "$entry")" "property string pluginId"
        assert_contains "$id $kind entry takes settings" "$(cat "$entry")" "property var settings: ({})"
    done
    # Native: no Omarchy or DMS module, command or path.
    assert_eq "$id imports no compat module" "" "$(grep -rnE '^import qs\.(Commons|Ui|Common|Services|Widgets|Modules)\b' "$dir" --include='*.qml' || true)"
    assert_eq "$id runs no omarchy command and reads no Omarchy path" "" \
        "$(grep -rnE '"omarchy-[a-z-]+"|OMARCHY_PATH|omarchy-shell|\.config/omarchy|state/omarchy' "$dir" --include='*.qml' --include='*.js' | grep -vE '^[^:]+:[0-9]+:\s*//' || true)"
    assert_eq "$id: no privilege escalation" "" "$(grep -rnE '"(sudo|pkexec|run0|doas)"' "$dir" --include='*.qml' --include='*.js' || true)"
    assert_eq "$id: outside text is never rich text" "" "$(grep -rn 'Text.RichText\|Text.StyledText' "$dir" --include='*.qml' || true)"
done
for f in bin/haseen-typist bin/haseen-browser-picker bin/haseen-browser-scan bin/haseen-vpn-openconnect; do
    capture "$REPO/$f" --help
    assert_status "$f --help" 0 "$STATUS"
    assert_contains "$f says how to use it" "$OUTPUT" "sage"
    assert_contains "$f has a summary" "$(cat "$REPO/$f")" "# haseen:summary"
    assert_contains "$f keeps the MIT notice" "$(head -n12 "$REPO/$f")" "MIT"
done

# --- the forks' own suites ---------------------------------------------------------
if command -v node >/dev/null; then
    capture node "$PLUGINS/haseen.browser-picker/tests/model.test.js"
    assert_status "browser-picker model suite (the fork's)" 0 "$STATUS"
    assert_contains "browser-picker model suite count" "$OUTPUT" "41 passed"
    capture node "$PLUGINS/haseen.vpn/tests/run.js"
    assert_status "VPN model suite (the fork's)" 0 "$STATUS"
    assert_contains "VPN model suite count" "$OUTPUT" "113 passed, 0 failed"
else
    engine_skip "node not installed; the forks' JS suites"
fi
capture bash "$PLUGINS/haseen.browser-picker/tests/scan.test.sh"
assert_status "browser scanner suite (the fork's, on fixtures)" 0 "$STATUS"
assert_contains "browser scanner suite count" "$OUTPUT" "27 passed"

# --- typist: the worker -------------------------------------------------------------
sandbox adopted-typist
WORKER="$PLUGINS/haseen.typist/typist-worker.py"
KEYLOG="$SANDBOX/keys.log"
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$KEYLOG" >"$SANDBOX/keys"
printf '#!/bin/sh\necho "$*" >>"%s"\n' "$SANDBOX/notify.log" >"$SANDBOX/notify"
chmod +x "$SANDBOX/keys" "$SANDBOX/notify"
work() { # TEXT ARGS... — the worker with the text on stdin
    local text=$1
    shift
    : >"$KEYLOG"
    : >"$SANDBOX/notify.log"
    set +e
    OUTPUT="$(printf '%s' "$text" | python3 -I "$WORKER" --keys "$SANDBOX/keys" --notify "$SANDBOX/notify" --startup-delay 0 --delay 5 --newline-delay 5 --punctuation-delay 5 "$@" 2>&1)"
    STATUS=$?
    set -e
}
work $'aA b\n' --layout us
assert_status "worker types on us" 0 "$STATUS"
assert_eq "key codes only: a, Shift+A, space, b, Enter" \
    "key -d 5 30:1 30:0
key -d 5 42:1 30:1 30:0 42:0
key -d 5 57:1 57:0
key -d 5 48:1 48:0
key -d 5 28:1 28:0" "$(cat "$KEYLOG")"
assert_not_contains "the text never reaches the key command" "$(cat "$KEYLOG")" "aA"
work 'z@' --layout de
assert_status "worker on de" 0 "$STATUS"
assert_eq "an AltGr character is skipped, not sent as Alt" "key -d 5 21:1 21:0" "$(cat "$KEYLOG")"
assert_contains "and the skip is reported" "$(cat "$SANDBOX/notify.log")" "skipped 1 character(s) this layout needs AltGr for"
work "$(printf 'x%.0s' {1..40})" --layout us --max-bytes 10
assert_status "over the size limit" 1 "$STATUS"
assert_eq "nothing typed over the limit" "" "$(cat "$KEYLOG")"
assert_contains "the limit is reported" "$(cat "$SANDBOX/notify.log")" "over the size limit"
work '' --layout us
assert_status "empty input is refused" 1 "$STATUS"
printf '#!/bin/sh\necho "ydotool (haseen compat): hyprctl: no" >&2\nexit 2\n' >"$SANDBOX/keys"
work 'ab' --layout us
assert_status "a refusing key command stops the run" 1 "$STATUS"
assert_contains "and says why" "$(cat "$SANDBOX/notify.log")" "Typing failed."

# --- typist: the command ------------------------------------------------------------
CFG="$XDG_CONFIG_HOME/haseen"
mkdir -p "$CFG"
printf '{"plugins":{"haseen.typist":{"settings":{"delayMs":12,"startupDelayMs":"bad"}}}}\n' >"$CFG/shell.json"
export HYPRLAND_INSTANCE_SIGNATURE=fixture-sig
capture haseen typist start --dry-run
assert_status "typist start --dry-run" 0 "$STATUS"
assert_dry_pure "typist start" "$OUTPUT"
assert_contains "the worker is a transient user unit" "$OUTPUT" "DRYRUN: systemd-run --user --unit=haseen-typist"
assert_contains "it gets the session's Hyprland" "$OUTPUT" "--setenv=HYPRLAND_INSTANCE_SIGNATURE=fixture-sig"
assert_contains "keys go through haseen's ydotool shim" "$OUTPUT" "$HASEEN_PATH/shell/Compat/bin/ydotool"
assert_contains "timings: shell.json wins, a bad value falls back" "$OUTPUT" " 65536 250 12 90 60 wl-paste -n"
printf '{"version":1,"snippets":[{"name":"sig","text":"Grüße\\nMe"}]}\n' >"$CFG/typist.json"
md5="$(printf 'Grüße\nMe' | md5sum | cut -c1-32)"
capture haseen typist type snippet 0 "$md5" --dry-run
assert_status "a snippet with its md5" 0 "$STATUS"
assert_contains "is produced by jq inside the unit" "$OUTPUT" "jq -j --argjson i 0"
stub notify-send 'exit 0'
capture haseen typist type snippet 0 00000000000000000000000000000000 --dry-run
assert_status "a snippet whose text changed is refused" 1 "$STATUS"
assert_contains "with its reason" "$OUTPUT" '"error":"pick_mismatch"'
capture haseen typist type snippet 7 "$md5" --dry-run
assert_status "an index past the end is refused" 1 "$STATUS"
stub cliphist 'case $1 in list) printf "9\ttext entry\n8\t[[ binary data 1 KiB png 2x2 ]]\n";; esac'
capture haseen typist type recent 9 --dry-run
assert_status "a recent text entry" 0 "$STATUS"
assert_contains "is decoded by cliphist inside the unit" "$OUTPUT" "cliphist decode"
capture haseen typist type recent 8 --dry-run
assert_status "an image entry is refused" 1 "$STATUS"
assert_contains "as not text" "$OUTPUT" '"error":"pick_binary"'
capture haseen typist type recent 5 --dry-run
assert_status "a vanished entry is refused" 1 "$STATUS"
capture haseen typist type recent nine
assert_status "a malformed pick is a usage error" 2 "$STATUS"
unset HYPRLAND_INSTANCE_SIGNATURE
capture haseen typist start
assert_status "without a Hyprland session nothing starts" 1 "$STATUS"
assert_contains "and it says so" "$OUTPUT" '"error":"no_session"'

# --- browser picker: the shim ---------------------------------------------------------
sandbox adopted-browser
apps="$SANDBOX/apps"
mkdir -p "$apps"
for b in alpha beta; do
    printf '#!/bin/sh\n' >"$SANDBOX/$b"
    chmod +x "$SANDBOX/$b"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%U\nMimeType=x-scheme-handler/http;x-scheme-handler/https;\n' "${b^}" "$SANDBOX/$b" >"$apps/$b.desktop"
done
cp "$HASEEN_PATH/default/applications/haseen-browser-picker.desktop" "$apps/"
export HASEEN_BROWSER_DESKTOP_DIRS="$apps"
# The fallback asks in a terminal when it has one; this machine may.
export TERMINAL=no-such-terminal
capture haseen browser picker --list
assert_eq "the shim lists every browser, never itself" "🧭  Alpha
🧭  Beta" "$OUTPUT"
# A shell that answers: qs replies with a pid, writes the argv and releases
# the FIFO, as the service does.
stub qs 'req=$7; sel=$(jq -r .selectionFile "$req"); done=$(jq -r .doneFile "$req"); jq -c "{urls, flags}" "$req" >"$(dirname "$0")/request.seen"; printf "%s\0" /opt/beta --profile-directory=Work "$(jq -r ".urls[0]" "$req")" >"$sel"; printf "x\n" 1<>"$done"; echo $$'
capture env DRY_RUN=true haseen browser picker --private 'https://example.com/a b'
assert_status "a pick through the shell" 0 "$STATUS"
assert_eq "the request carries the URL and the translated flag" '{"urls":["https://example.com/a b"],"flags":["--incognito"]}' "$(cat "$SANDBOX/stubs/request.seen")"
assert_contains "the answer runs in its own scope, argv intact" "$OUTPUT" "DRYRUN: exec systemd-run --user --scope --slice=app-graphical.slice --collect --quiet -- /opt/beta --profile-directory=Work https://example.com/a b"
assert_eq "no request directory is left behind" "" "$(find "$XDG_RUNTIME_DIR" -name 'haseen-browser.*' -print)"
stub qs 'req=$7; done=$(jq -r .doneFile "$req"); printf "x\n" 1<>"$done"; echo $$'
capture env DRY_RUN=true haseen browser picker https://example.com
assert_status "a cancelled pick" 0 "$STATUS"
assert_not_contains "opens nothing" "$OUTPUT" "DRYRUN: exec"
stub qs 'exit 1'
capture env DRY_RUN=true haseen browser picker https://example.com
assert_status "a shell that does not answer still opens the link" 0 "$STATUS"
assert_contains "in the first browser found (no fzf here)" "$OUTPUT" "-- $SANDBOX/alpha https://example.com"
capture haseen browser picker --default --dry-run
assert_status "--default --dry-run" 0 "$STATUS"
assert_dry_pure "browser picker --default" "$OUTPUT"
assert_contains "it is haseen setup default browser browser-picker" "$OUTPUT" "DRYRUN: xdg-settings set default-web-browser haseen-browser-picker.desktop"
entry="$(cat "$HASEEN_PATH/default/applications/haseen-browser-picker.desktop")"
assert_contains "the vendor entry runs the shim" "$entry" "Exec=haseen-browser-picker %U"
assert_contains "and is hidden from launchers" "$entry" "NoDisplay=true"
assert_eq "Helium stays haseen's default browser" "x-scheme-handler/http=helium.desktop" \
    "$(grep '^x-scheme-handler/http=' "$HASEEN_PATH/default/applications/mimeapps.list")"
unset HASEEN_BROWSER_DESKTOP_DIRS TERMINAL

# --- the OpenConnect helper -----------------------------------------------------------
sandbox adopted-openconnect
printf '#!/bin/sh\n' >"$SANDBOX/dialog"
chmod +x "$SANDBOX/dialog"
capture env HASEEN_OPENCONNECT_AUTH_DIALOG="$SANDBOX/dialog" haseen vpn openconnect --dialog-path
assert_eq "the auth dialog override" "$SANDBOX/dialog" "$OUTPUT"
capture env HASEEN_OPENCONNECT_AUTH_DIALOG="$SANDBOX" haseen vpn openconnect --dialog-path
assert_status "a directory is not a dialog" 1 "$STATUS"
capture haseen vpn openconnect
assert_status "no connection is a usage error" 2 "$STATUS"

# --- pure JS under the Qt JS engine -------------------------------------------------------
if [[ -x $QML_BIN ]]; then
    sandbox adopted-js
    cat >"$SANDBOX/Units.qml" <<EOF
import QtQuick
import "file://$PLUGINS/haseen.typist/Picker.js" as T
import "file://$PLUGINS/haseen.settings/Model.js" as S
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const recent = T.parseCliphist("12\thello  world\n11\t[[ binary data 2 KiB png 4x4 ]]\nbad line\n10\t   \n9\tsecond\n");
        out("cliphist", recent);
        out("recentRows", T.recentRows(recent, 1).map(r => r.id + "|" + r.preview + "|" + (r.text === undefined)));
        const cfg = T.parseSnippets('{"snippets":[{"text":"aaa"},{"name":"B","text":"bbb"},{"text":"  "},7]}');
        out("snippets", cfg.snippets.map(s => s.name + "=" + s.text));
        out("pin", T.pinSnippet(cfg, "bbb").snippets.map(s => s.text));
        out("remove", T.removeSnippet(cfg, 0).snippets.map(s => s.text));
        out("size", [T.sizeOf("Grüße"), T.sizeOf("😀"), T.snippetRows(cfg, 2).map(r => r.tooLarge)]);
        out("filter", T.filterRows(T.snippetRows(cfg, 99), "B").map(r => r.text));
        const reg = {
            "haseen.clock": { name: "Clock", origin: "builtin", dir: "/usr/share/haseen/shell/plugins/haseen.clock", kinds: ["bar-widget"], valid: true, unmet: [], settings: { format: {} } },
            "me.demo": { name: "Demo", origin: "user", dir: "/h/.config/haseen/plugins/me.demo", kinds: ["panel"], valid: true, unmet: [], settings: {} },
            "omarchy.x": { name: "X", origin: "omarchy", dir: "/h/.config/omarchy/plugins/x", kinds: ["bar-widget"], valid: true, unmet: ["needs foo"] },
            "dms.y": { name: "Y", origin: "user:dms", dir: "/h/.config/haseen/plugins/../y", kinds: ["service"], valid: false, unmet: [] }
        };
        const rows = S.rows(reg, id => ({ listed: id === "haseen.clock", enabled: id !== "me.demo" }), "/h/.config/haseen/plugins");
        out("rows", rows.map(r => r.id + ":" + r.deleteName + ":" + S.stateLabel(r) + ":" + r.readonly));
        out("filters", S.FILTERS.map(f => f + "=" + S.countFor(rows, f)));
        out("query", S.filterRows(rows, "all", "dem").map(r => r.id));
        out("parse", [S.parseValue("integer", " 42 "), S.parseValue("integer", "4.2"), S.parseValue("number", "4.5"), S.parseValue("array", "[1]"), S.parseValue("array", "{}"), S.parseValue("boolean", "true")]);
        out("fields", S.fields({ b: { type: "boolean", default: true }, a: { type: "integer", default: 3 }, debugIpc: { type: "boolean" } }, { a: 5 }));
        out("request", S.request("me.demo", { a: 1 }, ["b", "a"]));
        out("summary", S.deleteSummary("ok me.a\nfail me.b me.b is not installed\nnoise\n"));
        Qt.quit();
    }
}
EOF
    capture env QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" "$SANDBOX/Units.qml"
    assert_eq "Picker: text entries of cliphist, binary and blank dropped" '[{"id":"12","preview":"hello  world"},{"id":"9","preview":"second"}]' "$(result cliphist)"
    assert_eq "Picker: recent rows by id, capped, without the truncated text" '["12|hello world|true"]' "$(result recentRows)"
    assert_eq "Picker: snippets named, blank and malformed dropped" '["aaa=aaa","B=bbb"]' "$(result snippets)"
    assert_eq "Picker: pinning moves an existing snippet to the top" '["bbb","aaa"]' "$(result pin)"
    assert_eq "Picker: remove by index" '["bbb"]' "$(result remove)"
    assert_eq "Picker: UTF-8 sizes and the byte cap" '[7,4,[true,true]]' "$(result size)"
    assert_eq "Picker: filter by name" '["bbb"]' "$(result filter)"
    assert_eq "Settings: rows; only a dir directly in haseen's plugin dir is deletable" \
        '["dms.y::invalid:false","haseen.clock::enabled:false","me.demo:me.demo:disabled:false","omarchy.x::unmet:true"]' "$(result rows)"
    assert_eq "Settings: filter counts" '["all=4","enabled=1","builtin=1","installed=1","readonly=1","configurable=1"]' "$(result filters)"
    assert_eq "Settings: search" '["me.demo"]' "$(result query)"
    assert_eq "Settings: typed values parsed per type" \
        '[{"ok":true,"value":42},{"ok":false,"error":"a whole number"},{"ok":true,"value":4.5},{"ok":true,"value":[1]},{"ok":false,"error":"a JSON array"},{"ok":true,"value":true}]' "$(result parse)"
    assert_eq "Settings: fields, effective values, debugIpc hidden" \
        '[{"key":"a","type":"integer","description":"","defaultValue":3,"value":5,"set":true},{"key":"b","type":"boolean","description":"","defaultValue":true,"value":true,"set":false}]' "$(result fields)"
    assert_eq "Settings: one request, an edit beats a reset of the same key" \
        '{"changes":[{"path":["plugins","me.demo","settings","a"],"value":1},{"path":["plugins","me.demo","settings","b"],"remove":true}]}' "$(result request)"
    assert_eq "Settings: the delete summary" '{"ok":["me.a"],"failed":[{"name":"me.b","reason":"me.b is not installed"}]}' "$(result summary)"
else
    engine_skip "$QML_BIN missing; Picker.js and the settings model"
fi

# --- the plugins in the real engine ----------------------------------------------------------
if ! have_engine; then
    engine_skip "qs or dbus-run-session missing; engine scenarios"
else
    # typist: the picker lists, pins in full and hands haseen typist the pick.
    sandbox adopted-engine-typist
    h="$SANDBOX/shell"
    harness "$h"
    mkdir -p "$SANDBOX/bin" "$XDG_CONFIG_HOME/haseen"
    printf '#!/bin/sh\ncase $1 in list) printf "12\\thello world\\n11\\t[[ binary data 2 KiB png 4x4 ]]\\n10\\tsecond entry\\n";; decode) read l; printf "FULL TEXT of %%s" "${l%%%%\t*}";; esac\n' >"$SANDBOX/bin/cliphist"
    chmod +x "$SANDBOX/bin/cliphist"
    printf '{"version":1,"snippets":[{"name":"sig","text":"Best,\\nMe"}]}\n' >"$XDG_CONFIG_HOME/haseen/typist.json"
    cat >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.typist" as T
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 600; implicitHeight: 600
        T.Panel { id: p; pluginId: "haseen.typist"; settings: ({ recentCount: 5 }) }
    }
    function rows() { return p.rows.map(r => r.kind + ":" + (r.id || r.index || "")); }
    Timer {
        interval: 1500; running: true
        onTriggered: {
            console.warn("RESULT open " + JSON.stringify({ rows: rows(), cursor: p.cursorActive }));
            p.activate();
            console.warn("RESULT firstEnter " + JSON.stringify({ cursor: p.cursorActive, command: p.lastCommand }));
            p.cursorIndex = 2;
            p.pin();
            next.running = true;
        }
    }
    Timer {
        id: next; interval: 1000
        onTriggered: {
            console.warn("RESULT pinned " + JSON.stringify({ notice: p.notice, snippets: p.snippetConfig.snippets.map(s => s.text) }));
            p.cursorIndex = 1; p.activate();
            console.warn("RESULT typeSnippet " + JSON.stringify(p.lastCommand));
            p.cursorActive = true; p.cursorIndex = p.rows.length - 1; p.activate();
            console.warn("RESULT typeRecent " + JSON.stringify(p.lastCommand));
            p.cursorIndex = 3; p.armDelete(); p.armDelete();
            console.warn("RESULT deleteRecent " + JSON.stringify(p.notice));
            p.cursorIndex = 2; p.armDelete(); p.armDelete();
            console.warn("RESULT deleteSnippet " + JSON.stringify(p.snippetConfig.snippets.map(s => s.text)));
            Qt.quit();
        }
    }
}
QML
    engine "$h" PATH="$SANDBOX/bin:$PATH"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "typist: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    assert_eq "typist: clipboard, snippet, then text recents" '{"rows":["clipboard:","snippet:","recent:12","recent:10"],"cursor":false}' "$(result open)"
    assert_eq "typist: a first Enter only shows the cursor" '{"cursor":true,"command":[]}' "$(result firstEnter)"
    assert_eq "typist: a pin decodes the whole entry" '{"notice":"Pinned to snippets.","snippets":["FULL TEXT of 12","Best,\nMe"]}' "$(result pinned)"
    assert_eq "typist: a snippet is typed by index and md5" "[\"type\",\"snippet\",\"0\",\"$(printf 'FULL TEXT of 12' | md5sum | cut -c1-32)\"]" "$(result typeSnippet)"
    assert_eq "typist: a recent entry is typed by cliphist id" '["type","recent","10"]' "$(result typeRecent)"
    assert_eq "typist: the clipboard history is not typist's to delete" '"Only Snippets rows can be deleted."' "$(result deleteRecent)"
    assert_eq "typist: dd deletes the cursor snippet" '["FULL TEXT of 12"]' "$(result deleteSnippet)"
    assert_eq "typist: the snippets file holds what the panel shows" '["FULL TEXT of 12"]' "$(jq -c '[.snippets[].text]' "$XDG_CONFIG_HOME/haseen/typist.json")"

    # browser picker: a rule answers without the card, a pick answers through
    # the done file, Ctrl+Enter learns a rule, rankings persist.
    sandbox adopted-engine-browser
    h="$SANDBOX/shell"
    harness "$h"
    mkdir -p "$SANDBOX/apps" "$XDG_CONFIG_HOME/haseen"
    for b in alpha beta; do
        printf '#!/bin/sh\n' >"$SANDBOX/$b"
        chmod +x "$SANDBOX/$b"
        printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%U\nMimeType=x-scheme-handler/http;x-scheme-handler/https;\n' "${b^}" "$SANDBOX/$b" >"$SANDBOX/apps/$b.desktop"
    done
    printf '{"version":1,"rules":[{"pattern":"work.example","entryId":"beta:","learned":false}]}\n' >"$XDG_CONFIG_HOME/haseen/browser-picker.json"
    printf '{"selectionFile":"%s/sel1","doneFile":"%s/done1","urls":["https://app.work.example/x"],"flags":[]}' "$SANDBOX" "$SANDBOX" >"$SANDBOX/req1.json"
    printf '{"selectionFile":"%s/sel2","doneFile":"%s/done2","urls":["https://other.example/y"],"flags":["--incognito"]}' "$SANDBOX" "$SANDBOX" >"$SANDBOX/req2.json"
    sed "s|@S@|$SANDBOX|g" >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.browser-picker" as B
ShellRoot {
    B.Service { id: s; pluginId: "haseen.browser-picker"; settings: ({}) }
    Timer {
        interval: 1500; running: true
        onTriggered: {
            console.warn("RESULT entries " + JSON.stringify(s.entries.map(e => e.id)));
            s.pick("@S@/req1.json");
            t2.running = true;
        }
    }
    Timer {
        id: t2; interval: 800
        onTriggered: {
            console.warn("RESULT rule " + JSON.stringify({ answer: s.lastAnswer, opened: s.opened }));
            s.pick("@S@/req2.json");
            t3.running = true;
        }
    }
    Timer {
        id: t3; interval: 800
        onTriggered: {
            console.warn("RESULT asks " + JSON.stringify({ opened: s.opened, host: s.host }));
            s.finish(s.entries[0], true);
            console.warn("RESULT picked " + JSON.stringify({ answer: s.lastAnswer, opened: s.opened, rules: s.rules.map(r => r.pattern + "=" + r.entryId + "=" + r.learned) }));
            Qt.quit();
        }
    }
}
QML
    engine "$h" HASEEN_BROWSER_DESKTOP_DIRS="$SANDBOX/apps"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "browser-picker: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    assert_eq "browser-picker: the service scans" '["alpha:","beta:"]' "$(result entries)"
    assert_eq "browser-picker: a rule for the site answers without asking" "{\"answer\":[\"$SANDBOX/beta\",\"https://app.work.example/x\"],\"opened\":false}" "$(result rule)"
    assert_eq "browser-picker: another site opens the card" '{"opened":true,"host":"other.example"}' "$(result asks)"
    assert_eq "browser-picker: the pick answers; a private flag a plain browser lacks is dropped; Ctrl+Enter learns" \
        "{\"answer\":[\"$SANDBOX/alpha\",\"https://other.example/y\"],\"opened\":false,\"rules\":[\"other.example=alpha:=true\",\"work.example=beta:=false\"]}" "$(result picked)"
    assert_eq "browser-picker: the argv is NUL-separated in the selection file" "$SANDBOX/alpha|https://other.example/y|" "$(tr '\0' '|' <"$SANDBOX/sel2")"
    assert_eq "browser-picker: both callers were released" "x x" "$(cat "$SANDBOX/done1" "$SANDBOX/done2" | tr '\n' ' ' | sed 's/ $//')"
    assert_eq "browser-picker: the rules file holds rules only" '["rules","version"]' "$(jq -c keys "$XDG_CONFIG_HOME/haseen/browser-picker.json")"
    assert_eq "browser-picker: rankings in haseen's state" '["alpha:","beta:"]' "$(jq -c '.entries | keys' "$XDG_STATE_HOME/haseen/browser-picker.json")"

    # VPN: on a PATH that has only NetworkManager and WireGuard, the
    # NetworkManager backend is found, lists its VPN profile and connects it.
    sandbox adopted-engine-vpn
    h="$SANDBOX/shell"
    harness "$h"
    vb="$SANDBOX/vpnbin"
    mkdir -p "$vb"
    for c in sh bash env cat dirname readlink; do ln -s "$(command -v "$c")" "$vb/$c"; done
    printf '#!/bin/sh\necho "nmcli $*" >>"%s/calls"\ncase "$*" in *"connection show"*) printf "Office:11111111-2222-3333-4444-555555555555:wireguard:no:/etc/NetworkManager/system-connections/Office.nmconnection\\nHome:aaaaaaaa-2222-3333-4444-555555555555:802-11-wireless:yes:/x\\n";; esac\n' "$SANDBOX" >"$vb/nmcli"
    printf '#!/bin/sh\nexit 0\n' >"$vb/wg"
    printf '#!/bin/sh\necho "curl $*" >>"%s/calls"\necho 203.0.113.7\n' "$SANDBOX" >"$vb/curl"
    chmod +x "$vb/nmcli" "$vb/wg" "$vb/curl"
    cat >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.vpn" as V
ShellRoot {
    V.Service { id: s; pluginId: "haseen.vpn"; settings: ({}) }
    Timer {
        interval: 3500; running: true
        onTriggered: {
            console.warn("RESULT detected " + JSON.stringify({ backends: s.availableBackends.map(b => b.backendId), active: s.active ? s.active.backendId : "", targets: s.active ? s.active.targets.map(t => t.label) : [], summary: s.barSummary, ip: s.publicIp }));
            s.connectVia(s.active, s.active.targets[0]);
            next.running = true;
        }
    }
    Timer { id: next; interval: 1500; onTriggered: Qt.quit() }
}
QML
    engine "$h" PATH="$vb"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "vpn: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    assert_eq "vpn: only NetworkManager is found, with its VPN profile only" \
        '{"backends":["networkmanager"],"active":"networkmanager","targets":["Office"],"summary":"Not connected","ip":"203.0.113.7"}' "$(result detected)"
    assert_contains "vpn: the exit address over HTTPS" "$(cat "$SANDBOX/calls")" "curl --silent --fail --max-time 6 https://checkip.amazonaws.com"
    assert_contains "vpn: a connect goes through nmcli by uuid" "$(cat "$SANDBOX/calls")" "nmcli connection up uuid 11111111-2222-3333-4444-555555555555"

    # settings: the registry's plugins, a form saved through the CLI, and a
    # delete that reaches only haseen's own plugin directory.
    sandbox adopted-engine-settings
    h="$SANDBOX/shell"
    harness "$h"
    U="$XDG_CONFIG_HOME/haseen/plugins/me.demo"
    O="$XDG_CONFIG_HOME/omarchy/plugins/ro.thing"
    mkdir -p "$U" "$O"
    printf '{"schemaVersion":1,"id":"me.demo","name":"Demo","version":"1.0.0","kinds":["panel"],"entry":{"panel":"P.qml"},"settings":{"count":{"type":"integer","default":3},"tags":{"type":"array","default":[]},"mode":{"type":"string","default":"a"}}}\n' >"$U/manifest.json"
    echo 'import QtQuick; Item {}' >"$U/P.qml"
    printf '{"schemaVersion":1,"id":"ro.thing","name":"RO","version":"1.0.0","kinds":["bar-widget"],"entryPoints":{"barWidget":"W.qml"}}\n' >"$O/manifest.json"
    echo 'import QtQuick; Item {}' >"$O/W.qml"
    printf '{"plugins":{"me.demo":{"settings":{"mode":"b"}}}}\n' >"$XDG_CONFIG_HOME/haseen/shell.json"
    before="$(cd "$O" && find . -type f -print0 | sort -z | xargs -0 sha256sum)"
    cat >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.settings" as S
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 600; implicitHeight: 700
        S.Panel { id: p; pluginId: "haseen.settings"; settings: ({}) }
    }
    function ids() { return p.shown.map(r => r.id + ":" + r.deleteName); }
    Timer {
        interval: 3000; running: true
        onTriggered: {
            p.filter = "installed";
            const installed = ids();
            p.filter = "readonly";
            console.warn("RESULT lists " + JSON.stringify({ installed: installed, readonly: ids() }));
            p.requestDelete([""]);
            p.requestDelete(["../omarchy/plugins/ro.thing"]);
            p.openForm("me.demo");
            const f = p.formFields;
            console.warn("RESULT form " + JSON.stringify(f.map(x => x.key + "=" + JSON.stringify(x.value) + (x.set ? "*" : ""))));
            p.stage(f[2], "[oops");
            const errors = p.fieldErrors;
            p.stage(f[2], "[\"x\"]");
            p.stage(f[0], "9");
            p.reset(f[1]);
            p.save();
            console.warn("RESULT staged " + JSON.stringify({ errors: errors, live: p.formFields.map(x => x.key + "=" + JSON.stringify(x.value)) }));
            next.running = true;
        }
    }
    Timer {
        id: next; interval: 2500
        onTriggered: {
            console.warn("RESULT saved " + JSON.stringify(p.notice));
            p.formId = "";
            p.filter = "all";
            p.toggleSelected(p.allRows.find(r => r.id === "me.demo"));
            p.requestDelete(p.selectedNames);
            console.warn("RESULT armed " + JSON.stringify(p.notice));
            p.requestDelete(p.selectedNames);
            last.running = true;
        }
    }
    Timer { id: last; interval: 4000; onTriggered: { console.warn("RESULT deleted " + JSON.stringify(p.notice)); Qt.quit(); } }
}
QML
    engine "$h"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "settings: harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    assert_eq "settings: installed is haseen's dir, Omarchy's is listed but kept" \
        '{"installed":["me.demo:me.demo"],"readonly":["ro.thing:"]}' "$(result lists)"
    assert_eq "settings: fields with effective values, set ones marked" '["count=3","mode=\"b\"*","tags=[]"]' "$(result form)"
    assert_eq "settings: a value that does not parse is refused, typed values apply live" \
        '{"errors":{"tags":"expects a JSON array"},"live":["count=9","mode=\"b\"","tags=[\"x\"]"]}' "$(result staged)"
    assert_eq "settings: the form was saved" '"Saved to shell.json."' "$(result saved)"
    assert_eq "settings: shell.json through haseen plugin settings (reset drops a key)" '{"count":9,"tags":["x"]}' "$(jq -c '.plugins["me.demo"].settings' "$XDG_CONFIG_HOME/haseen/shell.json")"
    assert_contains "settings: the first press only arms the delete" "$(result armed)" "Press again to delete me.demo"
    assert_eq "settings: the selection is deleted and reported" '"Deleted me.demo."' "$(result deleted)"
    assert_eq "settings: the user plugin is gone" "absent" "$([[ -e $U ]] && echo present || echo absent)"
    assert_eq "settings: the Omarchy plugin is byte for byte untouched" "$before" "$(cd "$O" && find . -type f -print0 | sort -z | xargs -0 sha256sum)"
fi

# --- the migration ------------------------------------------------------------------------------
tree_sum() { (cd "$1" && find . -mindepth 1 -printf '%p %y\n' | LC_ALL=C sort && find . -type f -print0 | LC_ALL=C sort -z | xargs -0r sha256sum); }
mig() { capture env "$@" HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIG" bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIG"; }

sandbox adopted-migrate
# 095's migration moves nook items into the bar under their old ids, so this
# one must sort after it. Later plans' migrations may sort after this one.
assert_eq "the migration is in plan 096's range, after plan 095's" "1791560000-adopt-bar-basics.sh $MIG" \
    "$(cd "$HASEEN_PATH/migrations" && ls 1791560000-adopt-bar-basics.sh 17915601[0-9][0-9]-*.sh | LC_ALL=C sort | paste -sd' ')"
mig
assert_status "no shell.json: nothing to do" 0 "$STATUS"
assert_eq "and nothing written" "" "$(find "$HOME" -mindepth 1 -print -quit)"

C="$XDG_CONFIG_HOME"
mkdir -p "$C/haseen" "$C/omarchy" "$XDG_STATE_HOME/omarchy"
for id in "${OLD[@]}"; do
    mkdir -p "$C/omarchy/plugins/$id" "$C/haseen/plugins/$id"
    printf '{"id":"%s"}\n' "$id" | tee "$C/omarchy/plugins/$id/manifest.json" >"$C/haseen/plugins/$id/manifest.json"
done
cat >"$C/haseen/shell.json" <<'EOF'
{"bar":{"left":["haseen.logo"],"right":["haseen.tray","t1nk33r.settings","haseen.vpn","t1nk33r.vpn","haseen.pager"],"overflow":["t1nk33r.settings"],"pinned":["haseen.pager"]},
 "services":["haseen.pager","t1nk33r.vpn","t1nk33r.browser-picker","t1nk33r.typist","t1nk33r.settings","haseen.battery"],
 "plugins":{"t1nk33r.vpn":{"enabled":true,"settings":{"refreshIntervalSec":30,"bogus":1}},
            "t1nk33r.typist":{"enabled":true,"settings":{"delayMs":20,"recentCount":4}},
            "haseen.typist":{"settings":{"delayMs":50}},
            "t1nk33r.browser-picker":{"enabled":true},"t1nk33r.settings":{"enabled":false},
            "t1nk33r.nook":{"enabled":true}}}
EOF
printf '{"version":1,"settings":{"autoOpenRules":false,"promptAfter":4,"manageFirst":true},"rules":[{"pattern":"a.example","entryId":"x:","learned":false}]}\n' >"$C/omarchy/browser-picker.json"
printf '{"version":1,"snippets":[{"name":"s","text":"hi"}]}\n' >"$C/omarchy/t1nk33r.typist.json"
printf '{"version":1,"entries":{"x:":{"count":2,"last":1}},"domains":{}}\n' >"$XDG_STATE_HOME/omarchy/browser-picker.json"
plugins_before="$(tree_sum "$C/omarchy/plugins")$(tree_sum "$C/haseen/plugins")"
old_data="$(sha256sum "$C/omarchy/browser-picker.json" "$C/omarchy/t1nk33r.typist.json" "$XDG_STATE_HOME/omarchy/browser-picker.json")"
user_before="$(cat "$C/haseen/shell.json")"
home_before="$(tree_sum "$HOME")"

mig DRY_RUN=true
assert_status "migration dry run" 0 "$STATUS"
assert_dry_pure "migration" "$OUTPUT"
assert_contains "dry run shows the shell.json write" "$OUTPUT" "DRYRUN: mv -f -- $C/haseen/shell.json.new $C/haseen/shell.json"
assert_contains "dry run shows the copied snippets" "$OUTPUT" "DRYRUN: seed $C/haseen/typist.json"
assert_eq "dry run changed shell.json not at all" "$user_before" "$(cat "$C/haseen/shell.json")"
assert_eq "dry run wrote nothing anywhere in HOME" "$home_before" "$(tree_sum "$HOME")"

mig
assert_status "migration" 0 "$STATUS"
for i in "${!OLD[@]}"; do
    assert_contains "it says ${OLD[$i]} is now ${IDS[$i]}" "$OUTPUT" "${OLD[$i]} is now ${IDS[$i]}"
done
S="$C/haseen/shell.json"
assert_eq "bar: in place, a duplicate of an existing new id dropped" '["haseen.tray","haseen.settings","haseen.vpn","haseen.pager"]' "$(jq -c .bar.right "$S")"
assert_eq "bar: the overflow panel and pins too" '{"overflow":["haseen.settings"],"pinned":["haseen.pager"],"left":["haseen.logo"]}' "$(jq -c '{overflow: .bar.overflow, pinned: .bar.pinned, left: .bar.left}' "$S")"
assert_eq "services: kept where the new plugin has a service, dropped where not" '["haseen.pager","haseen.vpn","haseen.browser-picker","haseen.battery"]' "$(jq -c .services "$S")"
assert_eq "plugins: enabled kept, only declared settings carried, an existing new entry wins" \
    '{"haseen.typist":{"enabled":true,"settings":{"delayMs":50,"recentCount":4}},"haseen.vpn":{"enabled":true,"settings":{"refreshIntervalSec":30}},"haseen.settings":{"enabled":false}}' \
    "$(jq -c '.plugins | {"haseen.typist", "haseen.vpn", "haseen.settings"}' "$S")"
assert_eq "plugins: the fork's settings file settings land in shell.json" '{"enabled":true,"settings":{"autoOpenRules":false,"promptAfter":4}}' "$(jq -c '.plugins["haseen.browser-picker"]' "$S")"
assert_eq "plugins: no old entry left, other plugins untouched" '["haseen.browser-picker","haseen.settings","haseen.typist","haseen.vpn","t1nk33r.nook"]' "$(jq -c '.plugins | keys' "$S")"
assert_eq "data: snippets copied" '{"version":1,"snippets":[{"name":"s","text":"hi"}]}' "$(jq -c . "$C/haseen/typist.json")"
assert_eq "data: rules only into the routing file" '{"version":1,"rules":[{"pattern":"a.example","entryId":"x:","learned":false}]}' "$(jq -c . "$C/haseen/browser-picker.json")"
assert_eq "data: rankings copied" '{"x:":{"count":2,"last":1}}' "$(jq -c .entries "$XDG_STATE_HOME/haseen/browser-picker.json")"
assert_eq "the old plugin directories are untouched (Omarchy's and haseen's)" "$plugins_before" "$(tree_sum "$C/omarchy/plugins")$(tree_sum "$C/haseen/plugins")"
assert_eq "the old data files are copied, not moved or changed" "$old_data" "$(sha256sum "$C/omarchy/browser-picker.json" "$C/omarchy/t1nk33r.typist.json" "$XDG_STATE_HOME/omarchy/browser-picker.json")"
assert_eq "no staging file left" "" "$(find "$C/haseen" -maxdepth 1 -name 'shell.json.new*' -print)"
stub wl-paste 'exit 0'
capture haseen plugin validate "${IDS[@]}"
assert_status "the new ids the migration wrote resolve" 0 "$STATUS"

after="$(cat "$S")$(tree_sum "$C/haseen")"
mig
assert_status "a second run" 0 "$STATUS"
assert_eq "a second run changes nothing" "$after" "$(cat "$S")$(tree_sum "$C/haseen")"

printf '{"plugins":{"haseen.typist":{"enabled":true}}}\n' >"$S"
printf '{"version":1,"snippets":[{"text":"mine"}]}\n' >"$C/haseen/typist.json"
mig
assert_status "a shell.json without old ids" 0 "$STATUS"
assert_eq "is left alone" '{"plugins":{"haseen.typist":{"enabled":true}}}' "$(jq -c . "$S")"
assert_eq "and existing snippets are never overwritten" '["mine"]' "$(jq -c '[.snippets[].text]' "$C/haseen/typist.json")"
printf '{"bar":{"right":"t1nk33r.vpn"},"services":["t1nk33r.typist"],"plugins":{"t1nk33r.typist":true}}\n' >"$S"
mig
assert_status "odd shapes do not stop the migration" 0 "$STATUS"
assert_eq "non-array sections are kept, a non-object entry carries nothing" '{"bar":{"right":"t1nk33r.vpn"},"services":[],"plugins":{"haseen.typist":{}}}' "$(jq -c . "$S")"
printf '{"bar":{"right":["t1nk33r.vpn",1,null]}}\n' >"$S"
mig
assert_status "a non-string bar entry does not stop the migration" 0 "$STATUS"
assert_eq "it is kept beside the re-pointed id" '{"bar":{"right":["haseen.vpn",1,null]}}' "$(jq -c . "$S")"
printf '{"services": [' >"$S"
mig
assert_status "an unreadable shell.json is refused" 1 "$STATUS"
assert_eq "and not replaced" '{"services": [' "$(cat "$S")"
