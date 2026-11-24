# shellcheck shell=bash
# haseen:covers share/haseen/shell/shell.qml tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# What the shell answers over IPC when a role has no plugin (plan 196):
# `lock lock` says "unavailable" instead of succeeding silently, so
# `haseen system lock` falls back to logind; `menu select` says
# "unavailable" with no menu on, and with a menu that does not take the pick
# writes the caller's FIFO the line a closed menu writes. shell.qml's own
# routeRole, lock() and select() run in Quickshell against a stand-in
# Plugins singleton, and are called through `qs ipc call`, as the CLI does.

QS_BIN=${QS_BIN:-/usr/bin/qs}
SHELL_QML="$HASEEN_PATH/shell/shell.qml"

# The three functions, cut out of shell.qml as they are.
route_fn="$(awk '/^    function routeRole\(/,/^    }$/' "$SHELL_QML")"
lock_fn="$(awk '/^        function lock\(\): string \{/,/^        }$/' "$SHELL_QML")"
select_fn="$(awk '/^        function select\(request: string\): string \{/,/^        }$/' "$SHELL_QML")"
assert_contains "routeRole is found in shell.qml" "$route_fn" "function routeRole"
assert_contains "lock() is found in shell.qml" "$lock_fn" "function lock"
assert_contains "select() is found in shell.qml" "$select_fn" "function select"

if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; the shell's IPC answers not exercised" >&2
else
    sandbox shell-routes
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-routes.XXXXXX")"
    export XDG_RUNTIME_DIR
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    launcher="" probe_pid=""
    cleanup_routes() {
        [[ -z $probe_pid ]] || kill "$probe_pid" 2>/dev/null || true
        [[ -z $launcher ]] || { kill "$launcher" 2>/dev/null || true; wait "$launcher" 2>/dev/null || true; }
        rm -rf "$XDG_RUNTIME_DIR"
    }
    trap cleanup_routes EXIT
    h="$SANDBOX/shell"
    mkdir -p "$h/Haseen"
    # Plugins as shell.qml uses it: callRole, provider, componentUrl.
    cat >"$h/Haseen/Plugins.qml" <<'QML'
pragma Singleton
import QtQuick
import Quickshell
Singleton {
    property var roles: ({})
    property var providers: ({})
    property var picks: []
    function callRole(role, fn, args) {
        const o = roles[role];
        if (!o || typeof o[fn] !== "function")
            return false;
        o[fn].apply(o, args || []);
        return true;
    }
    function provider(role) { return providers[role] || ""; }
    function componentUrl(id, kind) { return ""; }
}
QML
    {
        cat <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
ShellRoot {
    id: shell
    property var toggled: []
    function togglePanel(id) { toggled = toggled.concat([id]); }
QML
        printf '%s\n' "$route_fn"
        printf '    IpcHandler {\n        target: "lock"\n%s\n    }\n' "$lock_fn"
        printf '    IpcHandler {\n        target: "menu"\n%s\n    }\n' "$select_fn"
        cat <<'QML'
    IpcHandler {
        target: "probe"
        // none: no plugin at all; lock: a lock plugin; menu: a menu that
        // takes picks; menu-broken: the menu is on but never takes a pick.
        function setup(mode: string): void {
            Plugins.roles = mode === "lock" ? { lock: { lock: () => {} } }
                : mode === "menu" ? { menu: { pick: r => { Plugins.picks = Plugins.picks.concat([r]); } } } : {};
            Plugins.providers = mode === "menu" || mode === "menu-broken" ? { menu: "haseen.menu" } : {};
        }
        function picks(): int { return Plugins.picks.length; }
        function quit(): void { Qt.quit(); }
    }
    FileView { id: pidFile; path: Quickshell.env("ROUTES_PID_FILE"); blockWrites: true; printErrors: false }
    Component.onCompleted: Qt.callLater(() => pidFile.setText(String(Quickshell.processId)))
}
QML
    } >"$h/shell.qml"
    env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software ROUTES_PID_FILE="$SANDBOX/pid" \
        dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$h" >"$SANDBOX/qs.log" 2>&1 &
    launcher=$!
    for ((i = 0; i < 100; i++)); do
        [[ -s $SANDBOX/pid ]] && break
        sleep 0.05
    done
    if [[ -s $SANDBOX/pid ]]; then
        probe_pid="$(cat "$SANDBOX/pid")"
        call() { capture "$QS_BIN" ipc --pid "$probe_pid" call "$@"; }

        call probe setup none
        call lock lock
        assert_status "lock with no lock plugin still answers" 0 "$STATUS"
        assert_eq "and says it is unavailable" "unavailable" "$OUTPUT"
        call probe setup lock
        call lock lock
        assert_eq "lock with a lock plugin answers ok" "ok" "$OUTPUT"

        # A pick request as haseen menu select writes it, with its FIFO.
        mkfifo -m 0600 "$SANDBOX/done"
        exec 3<>"$SANDBOX/done"
        printf '{"prompt":"Pick","options":["a"],"selectionFile":"%s","doneFile":"%s"}\n' \
            "$SANDBOX/selection" "$SANDBOX/done" >"$SANDBOX/request.json"
        call probe setup none
        call menu select "$SANDBOX/request.json"
        assert_eq "select with no menu plugin says unavailable" "unavailable" "$OUTPUT"
        call probe setup menu
        call menu select "$SANDBOX/request.json"
        assert_eq "select with a menu answers the shell's PID" "$probe_pid" "$OUTPUT"
        call probe picks
        assert_eq "and the menu has the request" 1 "$OUTPUT"
        call probe setup menu-broken
        call menu select "$SANDBOX/request.json"
        assert_eq "select with a menu that will not take it still answers the PID" "$probe_pid" "$OUTPUT"
        line=""
        read -r -t 5 -u 3 line || line="(nothing)"
        assert_eq "and the caller's FIFO gets the closed menu's line" "x" "$line"
        assert_contains "the shell says why" "$(cat "$SANDBOX/qs.log")" "the menu did not take the pick request"
        exec 3<&-

        call probe quit
        wait "$launcher" || true
        launcher="" probe_pid=""
    else
        _fail "IPC engine did not become ready" "$(cat "$SANDBOX/qs.log")"
    fi
fi
