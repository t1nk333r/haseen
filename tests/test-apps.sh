# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Apps (plan 074), in the actual Quickshell engine: what the shell starts runs
# in its own scope, not in haseen-shell.service's cgroup. The launcher, the
# menu (an app row and an action) and Apps.launch itself start through
#   uwsm-app        when it is on PATH in a uwsm session,
#   systemd-run     (a transient scope in app-graphical.slice) otherwise,
#   the bare argv   when neither exists,
# with the desktop entry's field codes stripped and Terminal=true entries
# opened in $TERMINAL. Every binary here is a stub that records its argv and
# working directory; nothing real is launched.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; Apps scenario not run" >&2
else
    sandbox apps
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-apps.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS \
        UWSM_FINALIZE_VARNAMES UWSM_WAIT_VARNAMES

    LOG="$SANDBOX/argv.log"
    export LOG
    # The only system binaries on the scenario PATH: no real uwsm-app or
    # systemd-run can be picked by accident.
    sysbin="$SANDBOX/sysbin"
    mkdir -p "$sysbin"
    for tool in sh bash; do
        ln -s "$(command -v "$tool")" "$sysbin/$tool"
    done
    # record NAME DIR — a stub that logs "NAME|cwd|arg|arg…" in one write
    # (the launches run concurrently) and exits.
    record() {
        printf '#!/bin/sh\nl="%s|$PWD"; for a; do l="$l|$a"; done; printf "%%s\\n" "$l" >>"$LOG"\n' "$1" >"$2/$1"
        chmod +x "$2/$1"
    }
    tools="$SANDBOX/tools"
    mkdir -p "$tools"
    for name in fakeapp faketui faketerm uwsm-app systemd-run; do
        record "$name" "$tools"
    done

    data="$SANDBOX/data"
    mkdir -p "$data/applications" "$SANDBOX/work dir"
    cat >"$data/applications/fixture-viewer.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Fixture Viewer
Exec=fakeapp --open %U "100%%" --icon=%i
Path=$SANDBOX/work dir
EOF
    cat >"$data/applications/fixture-tui.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Fixture Tui
Exec=faketui -x %f
Terminal=true
EOF
    mkdir -p "$HOME/.config/haseen"
    cat >"$HOME/.config/haseen/shell.json" <<'JSON'
{"bar":{"left":[],"center":[],"right":[]}}
JSON
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.launcher" as Launcher
import "plugins/haseen.menu" as Menu
ShellRoot {
    id: probe
    property Item launcher: Launcher.Panel {}
    property Item menu: Menu.Panel {}
    property bool done: false
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (!probe.done && DesktopEntries.byId("fixture-viewer") && DesktopEntries.byId("fixture-tui")) {
                probe.done = true;
                probe.launcher.query = "Fixture Viewer";
                probe.launcher.results[0].run();
                probe.launcher.query = "Fixture Tui";
                probe.launcher.results[0].run();
                probe.menu.launchApp("fixture-viewer");
                probe.menu.run("fakeapp menu-action \"two words\"");
                Apps.launch(["fakeapp", "plain"]);
                quit.start();
            }
        }
    }
    Timer {
        id: quit
        interval: 1500
        onTriggered: Qt.quit()
    }
}
QML

    # scenario NAME PATH [ENV…] — run the harness; leaves the log in $LOG.
    scenario() {
        : >"$LOG"
        capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
            XDG_DATA_DIRS="$data" TERMINAL=faketerm "${@:3}" \
            timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- \
            env PATH="$2" "$QS_BIN" -p "$harness"
        assert_status "$1: harness completes in the real engine" 0 "$STATUS"
        LINES="$(sort "$LOG")"
    }
    # line PREFIX — the log line starting with PREFIX (cwd field elided).
    line() { grep -F -- "$1" <<<"$LINES" | cut -d'|' -f1,3- | head -1; }
    # tail of a wrapped argv: everything after "--".
    after() { sed 's/^.*|--|//' <<<"$1"; }

    # --- uwsm session: uwsm-app ------------------------------------------------
    scenario uwsm "$tools:$sysbin" UWSM_WAIT_VARNAMES=HYPRLAND_INSTANCE_SIGNATURE
    viewer="$(line 'uwsm-app|'"$SANDBOX/work dir"'|-a|fixture-viewer|--|fakeapp')"
    assert_eq "uwsm: launcher entry → uwsm-app -a ID -- Exec, field codes stripped" \
        'uwsm-app|-a|fixture-viewer|--|fakeapp|--open|100%|--icon=' "$viewer"
    assert_contains "uwsm: the entry's Path= is the working directory" "$(sort -u "$LOG")" "uwsm-app|$SANDBOX/work dir|-a|fixture-viewer"
    assert_eq "uwsm: Terminal=true entry opens in \$TERMINAL" \
        'faketui|-x' "$(after "$(line '|-a|fixture-tui|')" | cut -d'|' -f5-)"
    assert_contains "uwsm: terminal wrapper runs \$TERMINAL -e" "$(line '|-a|fixture-tui|')" '|--|sh|-c|exec "${TERMINAL:-foot}" -e "$@"|sh|faketui|-x'
    assert_eq "uwsm: menu app row and launcher row start the same argv" 2 \
        "$(grep -c -F 'uwsm-app|'"$SANDBOX/work dir"'|-a|fixture-viewer|--|fakeapp|--open|100%|--icon=' "$LOG")"
    assert_contains "uwsm: menu action runs in bash inside uwsm-app" "$(line '|-a|haseen-menu|')" \
        "uwsm-app|-a|haseen-menu|--|bash|-c|PATH=\"\$1:\$PATH\"; eval \"\$2\"|bash|$REPO/bin|fakeapp menu-action \"two words\""
    assert_eq "uwsm: bare launch() takes no app name" 'uwsm-app|--|fakeapp|plain' "$(line '|--|fakeapp|plain')"
    assert_not_contains "uwsm: systemd-run unused" "$LINES" "systemd-run|"

    # --- uwsm-app present but no uwsm session: systemd-run ----------------------
    scenario systemd-run "$tools:$sysbin"
    viewer="$(line 'systemd-run|'"$SANDBOX/work dir")"
    # The id's "-" becomes "_": dashes separate the unit name's parts.
    assert_contains "systemd-run: user scope in app-graphical.slice" "$viewer" \
        'systemd-run|--user|--scope|--slice=app-graphical.slice|--collect|--quiet|--unit=app-haseen-fixture_viewer-'
    assert_contains "systemd-run: then the stripped Exec" "$viewer" '.scope|--|fakeapp|--open|100%|--icon='
    unit="$(grep -o 'app-haseen-fixture_viewer-[0-9a-f]*\.scope' <<<"$viewer")"
    assert_eq "systemd-run: unit is app-haseen-<id>-<8 hex>.scope" 1 "$(grep -cE '^app-haseen-fixture_viewer-[0-9a-f]{8}\.scope$' <<<"$unit")"
    assert_contains "systemd-run: terminal entry" "$(line '--unit=app-haseen-fixture_tui-')" '|--|sh|-c|exec "${TERMINAL:-foot}" -e "$@"|sh|faketui|-x'
    assert_contains "systemd-run: menu action" "$(line '--unit=app-haseen-haseen_menu-')" "|--|bash|-c|"
    assert_contains "systemd-run: bare launch() is named after the command" "$(line '--unit=app-haseen-fakeapp-')" '|--|fakeapp|plain'
    assert_not_contains "systemd-run: uwsm-app unused outside a uwsm session" "$LINES" "uwsm-app|"

    # --- neither: the bare argv ------------------------------------------------
    rm "$tools/uwsm-app" "$tools/systemd-run"
    scenario fallback "$tools:$sysbin" UWSM_WAIT_VARNAMES=HYPRLAND_INSTANCE_SIGNATURE
    assert_contains "fallback: the entry's argv runs directly, in its Path=" "$LINES" "fakeapp|$SANDBOX/work dir|--open|100%|--icon="
    assert_contains "fallback: terminal entry runs \$TERMINAL -e" "$LINES" "faketerm|"
    assert_contains "fallback: terminal gets the stripped Exec" "$(line 'faketerm|')" '|-e|faketui|-x'
    assert_contains "fallback: menu action runs its command" "$LINES" "|menu-action|two words"
    assert_eq "fallback: bare launch()" 'fakeapp|plain' "$(line '|plain')"
fi
