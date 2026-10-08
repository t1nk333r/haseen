# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 068: back selects the submenu's row in its parent, including after a
# nested traversal; search-only drilldowns leave a valid selection on return.

QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; menu back scenarios were not run" >&2
    return 0
fi

sandbox menu-back
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/share/haseen" "$FAKE/bin"
for entry in "$HASEEN_PATH"/*; do ln -s "$entry" "$FAKE/share/haseen/${entry##*/}"; done
cat >"$FAKE/bin/haseen" <<'SH'
#!/bin/sh
# Menu guard readers are harmless and deterministic in this panel harness.
case "$*" in
    "setup dns") printf 'dhcp\n' ;;
    *) exit 1 ;;
esac
SH
chmod +x "$FAKE/bin/haseen"

harness="$SANDBOX/shell"
mkdir -p "$harness"
for module in Haseen Compat Ui Commons plugins; do
    ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
done
cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.menu" as Menu

ShellRoot {
    Window {
        width: 1300
        height: 1000
        visible: true

        Menu.Panel {
            pluginId: "haseen.menu"
            settings: JSON.parse(Quickshell.env("MENU_SETTINGS"))
        }
    }
}
QML

settings='{"debugIpc":true}'
setsid env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
    QT_NO_XDG_DESKTOP_PORTAL=1 HASEEN_PATH="$FAKE/share/haseen" MENU_SETTINGS="$settings" \
    timeout 120 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness" \
    >"$SANDBOX/qs.log" 2>&1 &
qs_pid=$!
cleanup_menu_panel() {
    kill -- -"$qs_pid" 2>/dev/null || true
    wait "$qs_pid" 2>/dev/null || true
}
trap cleanup_menu_panel EXIT

ipc() { "$QS_BIN" -p "$harness" ipc call "$@" 2>/dev/null; }
state() { ipc haseen.menu state; }
s() { jq -c "$1" <<<"$(state)"; }
row_index() { jq -r --arg row "$1" '.rows | index($row) // -1' <<<"$(state)"; }
# until_state LABEL JQ — the panel state once JQ holds (10 s at most).
until_state() {
    local i summary
    for ((i = 0; i < 100; i++)); do
        STATE="$(state || true)"
        if [[ -n $STATE ]] && jq -e "$2" <<<"$STATE" >/dev/null 2>&1; then
            _pass
            return 0
        fi
        sleep 0.1
    done
    summary="$(jq -c . <<<"$STATE" 2>/dev/null || printf '%s' "$STATE")"
    _fail "$1" "state: $summary"$'\n'"$(cat "$SANDBOX/qs.log")"
}

until_state "the real menu panel loads the root tree" \
    '.menu == "root" and (.rows | index("System >")) != null'
system_index="$(row_index 'System >')"
assert_eq "System is not the first root row" true "$( ((system_index > 0)) && echo true || echo false )"
ipc haseen.menu select "$system_index" >/dev/null
ipc haseen.menu accept >/dev/null
until_state "accept enters System" '.menu == "system"'
ipc haseen.menu back >/dev/null
until_state "back from System returns to the root" '.menu == "root"'
assert_eq "back selects System's root row" "$system_index" "$(s .current)"

trigger_index="$(row_index 'Trigger >')"
ipc haseen.menu select "$trigger_index" >/dev/null
ipc haseen.menu accept >/dev/null
until_state "the nested scenario enters Trigger" '.menu == "trigger"'
capture_index="$(row_index 'Capture >')"
ipc haseen.menu select "$capture_index" >/dev/null
ipc haseen.menu accept >/dev/null
until_state "the nested scenario enters Capture" '.menu == "trigger.capture"'
ipc haseen.menu back >/dev/null
until_state "first back returns to Trigger" '.menu == "trigger"'
assert_eq "first back selects Capture's row" "$capture_index" "$(s .current)"
ipc haseen.menu back >/dev/null
until_state "second back returns to the root" '.menu == "root"'
assert_eq "second back selects Trigger's root row" "$trigger_index" "$(s .current)"

ipc haseen.menu search reminder >/dev/null
until_state "search finds the deep Reminder submenu" \
    '.menu == "root" and .query == "reminder" and (.rows | index("Reminder >")) != null'
reminder_index="$(row_index 'Reminder >')"
ipc haseen.menu select "$reminder_index" >/dev/null
ipc haseen.menu accept >/dev/null
until_state "search opens the deep Reminder submenu" '.menu == "trigger.reminder"'
ipc haseen.menu back >/dev/null
until_state "back from search-only submenu returns to root" '.menu == "root" and .query == ""'
search_back_state="$(state)"
assert_eq "the search-only submenu row is absent from root" -1 \
    "$(jq -r '.rows | index("Reminder >") // -1' <<<"$search_back_state")"
assert_eq "search back leaves a valid selection on the root" true \
    "$(jq -r '.current >= 0 and .current < (.rows | length) and .rows[.current] == "Apps >"' <<<"$search_back_state")"

cleanup_menu_panel
trap - EXIT
