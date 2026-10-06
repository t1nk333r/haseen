# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.pager (plan 025): the notification daemon ported from njpatel's
# omapager. The manifest validates and provides the notifications role,
# haseen.notifications steps aside for it, no hex colours, every Timer is
# marked, nothing Omarchy-only or Python is left, Do Not Disturb is the dnd
# flag, and the upstream pure-JS tests (Detect/Layout/Markup/Security/Store)
# pass under node and under Qt's own engine (qmltestrunner).

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
PAGER="$PLUGINS/haseen.pager"
QMLTESTRUNNER=${QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}
# Resolved before sandbox() narrows PATH to /usr/bin:/bin.
NODE_BIN=${NODE_BIN:-$(command -v node || true)}

# --- manifest ----------------------------------------------------------------
sandbox pager
capture haseen plugin validate haseen.pager haseen.notifications
assert_status "pager validate" 0 "$STATUS"
assert_contains "pager validates" "$OUTPUT" "ok: haseen.pager (builtin:"
assert_contains "notifications still validates" "$OUTPUT" "ok: haseen.notifications (builtin:"
assert_dry_pure "plugin validate" "$OUTPUT"
manifest="$PAGER/manifest.json"
assert_eq "manifest is JSON" "0" "$(jq empty "$manifest" >/dev/null 2>&1; echo $?)"
assert_eq "kinds" "service,bar-widget,panel" "$(jq -r '.kinds | join(",")' "$manifest")"
assert_eq "provides notifications" "notifications" "$(jq -r '.provides | join(",")' "$manifest")"
assert_eq "notifications is the only role besides the fallback" "haseen.notifications haseen.pager" \
    "$(jq -r 'select((.provides // []) | index("notifications")) | .id' "$PLUGINS"/*/manifest.json | sort | paste -sd' ')"
assert_eq "fetchRemoteIcons defaults off (local-first)" "false" "$(jq -r '.settings.fetchRemoteIcons.default' "$manifest")"
assert_eq "debugIpc defaults off" "false" "$(jq -r '.settings.debugIpc.default' "$manifest")"
assert_eq "historyHours defaults to 24" "24" "$(jq -r '.settings.historyHours.default' "$manifest")"
assert_eq "MIT notice kept" "1" "$(grep -c 'Copyright (c) 2026 Neil Jagdish Patel' "$PAGER/LICENSE")"
assert_contains "UPSTREAM.md records the source" "$(cat "$PAGER/UPSTREAM.md")" "https://github.com/njpatel/omapager"
while read -r entry; do
    body="$(cat "$PAGER/$entry")"
    for prop in "property string pluginId" "property var settings" "property var screen"; do
        assert_contains "$entry declares $prop" "$body" "$prop"
    done
done < <(jq -r '.entry[]' "$manifest")

# --- haseen conventions ----------------------------------------------------------
assert_eq "no hex colour literals" "" \
    "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "$PAGER" --include='*.qml' --include='*.js' || true)"
assert_eq "bar widget text uses Theme.barForeground" "1" "$(grep -c 'Theme.barForeground' "$PAGER/Widget.qml")"
# Code lines only: comments and UPSTREAM.md may name Omarchy and credit omapager.
code_lines() { # GLOB... -> file:line:text of non-comment lines
    find "$PAGER" -type f \( "$@" \) -exec awk '!/^[[:space:]]*(\/\/|#|\*)/ { print FILENAME ":" FNR ":" $0 }' {} +
}
src=(-name '*.qml' -o -name '*.js' -o -name '*.sh' -o -name '*.json')
assert_eq "no Omarchy-only APIs or modules" "" \
    "$(code_lines "${src[@]}" | grep -E 'qs\.(Commons|Ui|Common|Services|Widgets|Modules)\b|OMARCHY|[Oo]marchy' || true)"
assert_eq "no oma* names left in code (the njpatel credit aside)" "" \
    "$(code_lines "${src[@]}" | grep -iE '(^|[^a-z])oma[a-z]' | grep -v 'njpatel' || true)"
assert_eq "no Python in the shell path" "" "$(code_lines -name '*.qml' -o -name '*.sh' | grep -E 'python|\.py\b' || true)"
assert_eq "no shader effects" "" "$(code_lines -name '*.qml' | grep -E 'MultiEffect|ShaderEffect|layer\.effect' || true)"
assert_eq "no Timer one-liners (the marker check reads one per line)" "" \
    "$(grep -rnE 'Timer[[:space:]]*\{.*\}' "$PAGER" --include='*.qml' || true)"
timers="$(find "$PAGER" -name '*.qml' -exec awk '
    function report(why) { print FILENAME ":" start ": " why }
    intimer && /\}/ {
        if (kind == "sample" && interval < 2000) report("sample interval < 2000")
        if (kind == "sample" && running != "gated") report("sample not gated")
        if (kind == "ui" && repeat) report("ui-timeout repeats")
        intimer = 0
    }
    intimer && /interval:[[:space:]]*[0-9]+/ { match($0, /[0-9]+/); interval = substr($0, RSTART, RLENGTH) + 0 }
    intimer && /running:/ { running = ($0 ~ /running:[[:space:]]*true[[:space:]]*$/) ? "always" : "gated" }
    intimer && /repeat:[[:space:]]*true/ { repeat = 1 }
    /^[[:space:]]*Timer[[:space:]]*\{/ {
        start = FNR; interval = 0; running = ""; repeat = 0; intimer = 1
        if (prev ~ /haseen:ui-timeout/) kind = "ui"
        else if (prev ~ /haseen:sample/) kind = "sample"
        else { report("unmarked Timer"); intimer = 0 }
    }
    { prev = $0 }' {} +)"
assert_eq "every Timer is marked, samplers >= 2 s and gated, timeouts single-shot" "" "$timers"
assert_eq "two samplers (snooze expiry, card clock)" "2" "$(grep -rc 'haseen:sample' "$PAGER/Service.qml")"

# --- Do Not Disturb is the shared flag ---------------------------------------------
svc="$(cat "$PAGER/Service.qml")"
assert_contains "dnd mirrors the flag" "$svc" "readonly property bool doNotDisturb: Flags.dnd"
assert_contains "dnd is written through Flags" "$svc" 'Flags.set("dnd", !!value)'
assert_contains "role toggleDnd()" "$svc" "function toggleDnd(): void"
assert_contains "role clear()" "$svc" "function clear(): void"
assert_eq "flags are read only through qs.Haseen Flags" "" "$(grep -rn 'flags/' "$PAGER" --include='*.qml' || true)"
assert_not_contains "no IpcHandler of its own for the shell-owned notifications target" "$svc" 'target: "notifications"'
assert_contains "pager IPC target" "$svc" 'target: "pager"'
assert_contains "debug hooks gated by settings.debugIpc" "$(cat "$PAGER/Panel.qml")" "enabled: root.settings.debugIpc === true"
assert_contains "state lives under HASEEN_USER_STATE/pager" "$svc" 'Paths.userState + "/pager"'
assert_contains "remote icons only when asked" "$svc" 'fetchIcons && web.length'

# --- haseen.notifications is the fallback ---------------------------------------------
fallback="$(cat "$PLUGINS/haseen.notifications/Service.qml")"
assert_contains "fallback knows it is superseded" "$fallback" 'Config.services.indexOf("haseen.pager") >= 0'
assert_contains "fallback server only while not superseded" "$fallback" "model: root.superseded ? 0 : 1"
assert_contains "fallback gives up the role" "$fallback" 'Plugins.unregisterRole("notifications", root)'
assert_eq "fallback creates exactly one NotificationServer, inside the loader" "1" "$(grep -c 'NotificationServer {' "$PLUGINS/haseen.notifications/Service.qml")"
assert_eq "pager is the only other server" "1" "$(grep -c 'NotificationServer {' "$PAGER/Service.qml")"

# --- kdeconnect.sh -------------------------------------------------------------------
assert_eq "kdeconnect.sh parses" "0" "$(bash -n "$PAGER/kdeconnect.sh" >/dev/null 2>&1; echo $?)"
capture "$PAGER/kdeconnect.sh"
assert_status "kdeconnect.sh usage" 2 "$STATUS"
capture "$PAGER/kdeconnect.sh" reply /not/a/kdeconnect/path "hi" app body
assert_status "kdeconnect.sh refuses a foreign object path" 1 "$STATUS"

# --- upstream pure-JS tests ------------------------------------------------------------
if [[ -n $NODE_BIN && -x $NODE_BIN ]]; then
    out="$("$NODE_BIN" "$PAGER/tests/baseline.cjs" 2>&1)" && rc=0 || rc=$?
    assert_status "node baseline.cjs" 0 "$rc"
    assert_contains "baseline passed" "$out" "baseline: passed"
    out="$("$NODE_BIN" "$PAGER/tests/security.cjs" 2>&1)" && rc=0 || rc=$?
    assert_status "node security.cjs" 0 "$rc"
    assert_contains "security passed" "$out" "security: passed"
else
    echo "  (node not found: baseline.cjs/security.cjs skipped)"
fi
if [[ -x $QMLTESTRUNNER && -d /usr/lib/qt6/qml/QtTest ]]; then
    out="$(cd "$PAGER/tests" && QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' timeout 60 "$QMLTESTRUNNER" -input tst_security.qml 2>&1)" && rc=0 || rc=$?
    assert_status "qmltestrunner tst_security.qml" 0 "$rc"
    assert_contains "QtTest totals" "$out" "0 failed"
else
    echo "  (qmltestrunner/QtTest not found: tst_security.qml skipped)"
fi
