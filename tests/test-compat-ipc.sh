# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Canonical false must turn an actual bool setting off, and multiple screen
# handlers sharing one IPC target must dispatch to one owner with clean failover.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; typed IPC scenario not run" >&2
else
    sandbox compat-ipc
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-ipc.XXXXXX")"
    export XDG_RUNTIME_DIR
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    launcher="" probe_pid=""
    cleanup_ipc() {
        [[ -z $probe_pid ]] || kill "$probe_pid" 2>/dev/null || true
        [[ -z $launcher ]] || { kill "$launcher" 2>/dev/null || true; wait "$launcher" 2>/dev/null || true; }
        rm -rf "$XDG_RUNTIME_DIR"
    }
    trap cleanup_ipc EXIT
    h="$SANDBOX/shell"
    mkdir -p "$h"
    for module in Commons Ui Haseen Compat Common Services Widgets Modules; do
        ln -s "$HASEEN_PATH/shell/$module" "$h/$module"
    done
    cat >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
ShellRoot {
    ShellIpc {
        target: "compat-probe"
        property int count: 0
        property bool selected: true
        property string label: "none"
        function add(value: int): int { count += value; return count; }
        function select(value: bool): bool { selected = value; return selected; }
        function name(value: string): string { label = value; return label; }
        function state(): string { return JSON.stringify({owner: "first", count: count, selected: selected, label: label}); }
    }
    ShellIpc {
        target: "compat-probe"
        property int count: 100
        property bool selected: true
        property string label: "none"
        function add(value: int): int { count += value; return count; }
        function select(value: bool): bool { selected = value; return selected; }
        function name(value: string): string { label = value; return label; }
        function state(): string { return JSON.stringify({owner: "second", count: count, selected: selected, label: label}); }
    }
    IpcHandler {
        target: "probe-driver"
        function failover(): void { IpcRegistry.handlerFor("compat-probe").enabled = false; }
        function quit(): void { Qt.quit(); }
    }
    FileView { id: pidFile; path: Quickshell.env("COMPAT_PID_FILE"); blockWrites: true; printErrors: false }
    Component.onCompleted: Qt.callLater(() => pidFile.setText(String(Quickshell.processId)))
}
QML
    env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software COMPAT_PID_FILE="$SANDBOX/pid" \
        dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$h" >"$SANDBOX/qs.log" 2>&1 &
    launcher=$!
    for ((i = 0; i < 100; i++)); do
        [[ -s $SANDBOX/pid ]] && break
        sleep 0.05
    done
    if [[ -s $SANDBOX/pid ]]; then
        probe_pid="$(cat "$SANDBOX/pid")"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe state
        before="$OUTPUT"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe add 3
        assert_status "numeric IPC argument accepted" 0 "$STATUS"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe select false
        assert_status "boolean IPC argument accepted" 0 "$STATUS"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe state
        after="$OUTPUT"
        assert_eq "false actually disables the selected setting" false "$(jq -r .selected <<<"$after")"
        assert_eq "numeric action executes exactly once" "$(($(jq -r .count <<<"$before") + 3))" "$(jq -r .count <<<"$after")"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe select 0
        assert_status "integer boolean argument accepted" 0 "$STATUS"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe name 0
        assert_status "numeric-looking string argument accepted" 0 "$STATUS"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe state
        typed="$OUTPUT"
        assert_eq "0 turns a bool setting off" false "$(jq -r .selected <<<"$typed")"
        assert_eq "0 stays text for a string setting" 0 "$(jq -r .label <<<"$typed")"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe select 1
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe state
        assert_eq "1 turns a bool setting on" true "$(jq -r .selected <<<"$OUTPUT")"
        assert_eq "target retains the same owner before failover" "$(jq -r .owner <<<"$before")" "$(jq -r .owner <<<"$after")"
        capture "$QS_BIN" ipc --pid "$probe_pid" call probe-driver failover
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe add 7
        assert_status "successor accepts the next action" 0 "$STATUS"
        capture "$QS_BIN" ipc --pid "$probe_pid" call compat-probe state
        next="$OUTPUT"
        assert_eq "disabled owner yields to its live successor" true "$(printf '%s\n%s\n' "$after" "$next" | jq -sr '.[0].owner != .[1].owner')"
        expected=7
        [[ $(jq -r .owner <<<"$next") == first ]] || expected=107
        assert_eq "successor owns independent state and dispatches once" "$expected" "$(jq -r .count <<<"$next")"
        capture "$QS_BIN" ipc --pid "$probe_pid" call probe-driver quit
        wait "$launcher" || true
        launcher="" probe_pid=""
    else
        _fail "IPC engine did not become ready" "$(cat "$SANDBOX/qs.log")"
    fi
fi
