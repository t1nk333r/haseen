# shellcheck shell=bash
# System surfaces (plan 010): the notifications, osd, launcher, lock, idle,
# polkit and session built-ins. Manifests validate, IPC roles have exactly
# one provider, widgets use Theme tokens only, and timers follow the
# architecture 6 rule (none under 2 s except marked single-shot UI timeouts).

SHELL_DIR="$HASEEN_PATH/shell"
PLUGINS="$SHELL_DIR/plugins"
SURFACES=(haseen.notifications haseen.osd haseen.launcher haseen.lock haseen.idle haseen.polkit haseen.session)
SERVICES=(haseen.notifications haseen.osd haseen.polkit haseen.idle haseen.lock)

# timer_violations DIR... — one line per Timer that breaks the rule: an
# unmarked Timer needs a literal interval >= 2000; a Timer whose previous
# line is `// haseen:ui-timeout` must say `repeat: false`.
timer_violations() {
    find "$@" -name '*.qml' -print0 | xargs -0 -r awk '
        FNR == 1 { depth = 0; inside = 0 }
        !inside && /^[[:space:]]*Timer[[:space:]]*\{/ {
            inside = 1; depth = 0; start = FNR
            marked = (prev ~ /\/\/[[:space:]]*haseen:ui-timeout/)
            interval = ""; single = 0; repeating = 0
        }
        inside {
            if (match($0, /^[[:space:]]*interval:[[:space:]]*[0-9]+[[:space:]]*$/)) {
                interval = $0; gsub(/[^0-9]/, "", interval)
            }
            if ($0 ~ /^[[:space:]]*repeat:[[:space:]]*false/) single = 1
            if ($0 ~ /^[[:space:]]*repeat:[[:space:]]*true/) repeating = 1
            n = split($0, ch, "")
            for (i = 1; i <= n; i++) { if (ch[i] == "{") depth++; else if (ch[i] == "}") depth-- }
            if (depth <= 0) {
                inside = 0
                if (marked && (!single || repeating))
                    print FILENAME ":" start ": ui-timeout Timer must be repeat: false"
                else if (!marked && (interval == "" || interval + 0 < 2000))
                    print FILENAME ":" start ": Timer under 2000 ms without // haseen:ui-timeout"
            }
        }
        { prev = $0 }
    '
}

# --- manifests ---------------------------------------------------------------
sandbox surfaces-validate
capture haseen plugin validate "${SURFACES[@]}"
assert_status "surfaces validate" 0 "$STATUS"
for id in "${SURFACES[@]}"; do
    assert_contains "surface $id ok" "$OUTPUT" "ok: $id (builtin:"
done
assert_not_contains "surfaces request no network" "$OUTPUT" "warning:"

# --- roles: unique, and every routed IPC role has a built-in provider --------
assert_eq "provides roles are unique across built-ins" "" \
    "$(jq -r '.provides[]?' "$PLUGINS"/*/manifest.json | sort | uniq -d)"
role_provider() { # ROLE -> the built-in ids providing it
    jq -r --arg r "$1" 'select((.provides // []) | index($r)) | .id' "$PLUGINS"/*/manifest.json | paste -sd' '
}
assert_eq "notifications role" "haseen.notifications" "$(role_provider notifications)"
assert_eq "launcher role" "haseen.launcher" "$(role_provider launcher)"
assert_eq "lock role" "haseen.lock" "$(role_provider lock)"
while read -r role; do
    assert_eq "routed role '$role' has one provider" "1" "$(role_provider "$role" | wc -w)"
done < <(grep -o 'routeRole("[a-z-]*"' "$SHELL_DIR/shell.qml" | cut -d'"' -f2 | sort -u)
# The functions shell.qml routes to (architecture 5.5) exist on the providers.
svc="$PLUGINS/haseen.notifications/Service.qml"
assert_contains "notifications.clear()" "$(cat "$svc")" "function clear(): void"
assert_contains "notifications.toggleDnd()" "$(cat "$svc")" "function toggleDnd(): void"
assert_contains "lock.lock()" "$(cat "$PLUGINS/haseen.lock/Service.qml")" "function lock(): void"
assert_contains "launcher is a panel (toggle via the panel host)" \
    "$(jq -r '.kinds | join(" ")' "$PLUGINS/haseen.launcher/manifest.json")" "panel"

# --- default shell.json starts the services ----------------------------------
for id in "${SERVICES[@]}"; do
    assert_eq "default services list $id" "yes" \
        "$(jq -r --arg id "$id" 'if (.services | index($id)) then "yes" else "no" end' "$HASEEN_PATH/default/shell.json")"
done
while read -r id; do
    assert_contains "service id $id has a service entry" \
        "$(jq -r '.kinds | join(" ")' "$PLUGINS/$id/manifest.json")" "service"
done < <(jq -r '.services[]' "$HASEEN_PATH/default/shell.json")

# --- entry contract: every entry file takes pluginId/settings/screen ---------
for id in "${SURFACES[@]}"; do
    while read -r entry; do
        body="$(cat "$PLUGINS/$id/$entry")"
        for prop in "property string pluginId" "property var settings" "property var screen"; do
            assert_contains "$id/$entry declares $prop" "$body" "$prop"
        done
    done < <(jq -r '.entry[]' "$PLUGINS/$id/manifest.json")
done

# --- resource and theme rules -------------------------------------------------
surface_dirs=()
for id in "${SURFACES[@]}"; do surface_dirs+=("$PLUGINS/$id"); done
assert_eq "no hex colour literals in surfaces" "" \
    "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "${surface_dirs[@]}" --include='*.qml' --include='*.js' || true)"
assert_eq "no Timer under 2000 ms except marked single-shot UI timeouts" "" "$(timer_violations "$SHELL_DIR")"
# Windows owned by services exist only while shown (LazyLoader), apart from
# the session lock, whose surfaces Quickshell creates only while locked.
for id in "${SERVICES[@]}"; do
    f="$PLUGINS/$id/Service.qml"
    assert_eq "$id: every PanelWindow sits in a LazyLoader" \
        "$(grep -c 'PanelWindow {' "$f")" "$(grep -c 'LazyLoader {' "$f")"
done
assert_eq "notifications are memory-only (no FileView/Process)" "" \
    "$(grep -rnE 'FileView|Process \{|execDetached' "$PLUGINS/haseen.notifications" || true)"

# The checker itself: it must flag what the rule forbids and pass the rest.
T="$SANDBOX/timers"
mkdir -p "$T"
printf 'Item {\n    Timer {\n        interval: 500\n    }\n}\n' >"$T/Fast.qml"
printf 'Item {\n    // haseen:ui-timeout\n    Timer {\n        interval: 500\n        repeat: true\n    }\n}\n' >"$T/MarkedRepeat.qml"
printf 'Item {\n    Timer {\n        interval: root.ms\n    }\n}\n' >"$T/Expr.qml"
printf 'Item {\n    Timer {\n        interval: 2000\n        repeat: true\n    }\n}\n' >"$T/Slow.qml"
printf 'Item {\n    // haseen:ui-timeout\n    Timer {\n        interval: Math.max(a, 1)\n        repeat: false\n        onTriggered: { x() }\n    }\n}\n' >"$T/Marked.qml"
out="$(timer_violations "$T")"
assert_contains "checker flags an unmarked 500 ms timer" "$out" "Fast.qml:2:"
assert_contains "checker flags a repeating ui-timeout" "$out" "MarkedRepeat.qml:3:"
assert_contains "checker flags an unmarked expression interval" "$out" "Expr.qml:2:"
assert_not_contains "checker accepts a 2 s timer" "$out" "Slow.qml"
assert_not_contains "checker accepts a marked single-shot timer" "$out" "Marked.qml"

# --- lock safety and session commands ----------------------------------------
assert_eq "lock preview defaults to off" "false" \
    "$(jq -r '.settings.preview.default' "$PLUGINS/haseen.lock/manifest.json")"
assert_eq "lock uses the system login PAM service by default" "login" \
    "$(jq -r '.settings.pamConfig.default' "$PLUGINS/haseen.lock/manifest.json")"
assert_contains "session lock starts unlocked" "$(cat "$PLUGINS/haseen.lock/Service.qml")" "locked: false"
session="$(cat "$PLUGINS/haseen.session/Panel.qml")"
for cmd in '"systemctl", "suspend"' '"systemctl", "reboot"' '"systemctl", "poweroff"' '"loginctl", "lock-session"' 'hl.dsp.exit()'; do
    assert_contains "session runs $cmd" "$session" "$cmd"
done
