# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Shell recovery and safe mode (plan 061): the suspect named from a journal
# tail, the offer and its fixes, the last good shell.json, and safe mode
# holding back every plugin that is not built in, in the real engine.
sandbox recovery
cfg="$HOME/.config/haseen"
state="$HOME/.local/state/haseen"
mkdir -p "$cfg/plugins/me.broken" "$HOME/.config/omarchy/plugins/ticker" "$state"
cat >"$cfg/plugins/me.broken/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.broken","name":"Broken","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"Widget.qml"}}
JSON
: >"$cfg/plugins/me.broken/Widget.qml"
cat >"$HOME/.config/omarchy/plugins/ticker/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"ticker","name":"Ticker","version":"1.0.0","kinds":["service"],"entryPoints":{"service":"Service.qml"}}
JSON
: >"$HOME/.config/omarchy/plugins/ticker/Service.qml"
cat >"$cfg/shell.json" <<'JSON'
{"bar":{"left":["haseen.workspaces"],"center":["haseen.clock"],"right":["me.broken","haseen.tray"]}}
JSON

# systemctl answers like a unit the start limit stopped and logs what runs.
calls="$SANDBOX/systemctl.calls"
: >"$calls"
unit_state=failed
stub systemctl "
echo \"\$*\" >>'$calls'
case \"\$*\" in
*is-failed*) [ \"\$(cat '$SANDBOX/unit-state')\" = failed ] ;;
*is-active*) cat '$SANDBOX/unit-state' ;;
*'-P ActiveState'*) cat '$SANDBOX/unit-state' ;;
*'-P ActiveEnterTimestamp'*) cat '$SANDBOX/unit-since' ;;
esac"
echo "$unit_state" >"$SANDBOX/unit-state"
echo "@$((EPOCHSECONDS - 3600))" >"$SANDBOX/unit-since"

# use_journal NAME — journalctl prints the fixture, with this sandbox's paths.
use_journal() {
    sed -e "s|@HASEEN_PATH@|$HASEEN_PATH|g" -e "s|@CONFIG@|$HOME/.config|g" \
        "$FIXTURES/recovery/journal-$1.log" >"$SANDBOX/journal"
    stub journalctl "cat '$SANDBOX/journal'"
}
failure() { jq -r "$1" "$state/recovery/last-failure.json"; }

# --- suspect detection -------------------------------------------------------
stub foot "exit 0"
use_journal user-plugin
capture env TERMINAL=foot haseen-shell-recover present --dry-run
assert_status "present --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "present" "$OUTPUT"
assert_contains "dry run names the suspect" "$OUTPUT" "suspect: me.broken (user)"
assert_contains "dry run shows the record it would write" "$OUTPUT" "last-failure.json"
assert_contains "dry run shows the floating offer" "$OUTPUT" "DRYRUN: foot --app-id=haseen.floating"
assert_eq "dry run writes nothing" "" "$(ls -A "$state")"

HASEEN_INLINE=1 capture haseen-shell-recover present <<<"q"
assert_status "present records and offers inline" 0 "$STATUS"
assert_eq "a user plugin's file URL beats later built-in mentions" me.broken "$(failure .suspect.id)"
assert_eq "the suspect's origin is recorded" user "$(failure .suspect.origin)"
assert_eq "the suspect's directory is recorded" "$cfg/plugins/me.broken" "$(failure .suspect.dir)"
assert_contains "the blaming line is kept" "$(failure .suspect.line)" "Widget.qml:7:5: TypeError"
assert_contains "the offer names the suspect" "$OUTPUT" "d  Disable me.broken"
assert_contains "the offer has safe mode" "$OUTPUT" "s  Safe mode"
assert_not_contains "no restore without a last good shell.json" "$OUTPUT" "r  Restore"
assert_not_contains "leaving it stopped starts nothing" "$(cat "$calls")" "start"

use_journal builtin-only
HASEEN_INLINE=1 capture haseen-shell-recover present <<<"q"
assert_eq "only built-ins mentioned: the latest mention" haseen.clock "$(failure .suspect.id)"
assert_eq "a built-in suspect says so" builtin "$(failure .suspect.origin)"

use_journal omarchy-plugin
HASEEN_INLINE=1 capture haseen-shell-recover present <<<"q"
assert_eq "an Omarchy plugin is found by its directory" omarchy.ticker "$(failure .suspect.id)"
assert_eq "and named by its origin" omarchy "$(failure .suspect.origin)"

use_journal no-plugin
HASEEN_INLINE=1 capture haseen-shell-recover present <<<"q"
assert_eq "no plugin in the log: no suspect" null "$(failure .suspect)"
assert_contains "the offer shows the last lines instead" "$OUTPUT" "undefined symbol"
assert_not_contains "nothing to disable" "$OUTPUT" "d  Disable"

# --- the fixes -----------------------------------------------------------------
use_journal user-plugin
: >"$calls"
HASEEN_INLINE=1 capture haseen-shell-recover present <<<"d"
assert_status "disable the suspect" 0 "$STATUS"
assert_eq "the suspect is off in shell.json" false "$(jq -r '.plugins["me.broken"].enabled' "$cfg/shell.json")"
assert_eq "and out of its bar section" '["haseen.tray"]' "$(jq -c .bar.right "$cfg/shell.json")"
assert_contains "the failed shell is reset" "$(cat "$calls")" "--user reset-failed haseen-shell.service"
assert_contains "and started again" "$(cat "$calls")" "--user start haseen-shell.service"
assert_eq "the plugin's own files are untouched" "Widget.qml manifest.json" "$(cd "$cfg/plugins/me.broken" && LC_ALL=C ls | tr '\n' ' ' | sed 's/ $//')"

: >"$calls"
echo inactive >"$SANDBOX/unit-state"
capture haseen-shell-recover disable-suspect
assert_not_contains "a shell stopped on purpose is not started" "$(cat "$calls")" "start"
echo failed >"$SANDBOX/unit-state"

capture haseen-shell-recover safe-mode on --dry-run
assert_dry_pure "safe-mode on" "$OUTPUT"
assert_eq "safe-mode on --dry-run writes nothing" false "$([[ -e $state/safe-mode ]] && echo true || echo false)"
: >"$calls"
HASEEN_INLINE=1 capture haseen-shell-recover offer <<<"x
s"
assert_status "an unknown key asks again, then safe mode" 0 "$STATUS"
assert_eq "safe mode records why" "the shell kept failing; suspect me.broken" "$(jq -r .reason "$state/safe-mode")"
assert_contains "safe mode records since when" "$(jq -r .since "$state/safe-mode")" "T"
assert_contains "safe mode restarts the failed shell" "$(cat "$calls")" "--user start haseen-shell.service"
capture haseen-shell-recover safe-mode status --quiet
assert_status "status --quiet: on" 0 "$STATUS"
capture haseen-shell-recover status
assert_contains "status shows safe mode" "$OUTPUT" "safe mode: on since"
assert_contains "status shows the suspect" "$OUTPUT" "suspect me.broken (user)"
capture haseen-shell-recover safe-mode off --dry-run
assert_dry_pure "safe-mode off" "$OUTPUT"
assert_eq "off --dry-run keeps the flag" true "$([[ -e $state/safe-mode ]] && echo true)"
capture haseen-shell-recover safe-mode toggle
assert_eq "toggle turns it off" false "$([[ -e $state/safe-mode ]] && echo true || echo false)"
capture haseen-shell-recover safe-mode status --quiet
assert_status "status --quiet: off" 1 "$STATUS"

# --- last good shell.json ------------------------------------------------------
capture haseen-shell-recover restore-last
assert_status "restore-last without a snapshot fails" 1 "$STATUS"
assert_contains "and says when one is taken" "$OUTPUT" "after the shell has run 10 minutes"

good="$(cat "$cfg/shell.json")"
touch -d '-1 hour' "$cfg/shell.json"
echo active >"$SANDBOX/unit-state"
echo "@$EPOCHSECONDS" >"$SANDBOX/unit-since"
capture haseen-shell-recover snapshot
assert_contains "a shell up for seconds proves nothing" "$OUTPUT" "less than 10 minutes"
echo "@$((EPOCHSECONDS - 3600))" >"$SANDBOX/unit-since"
capture haseen-shell-recover snapshot --dry-run
assert_dry_pure "snapshot" "$OUTPUT"
assert_eq "snapshot --dry-run writes nothing" false "$([[ -e $state/recovery/last-good.json ]] && echo true || echo false)"
capture haseen-shell-recover snapshot
assert_status "a healthy hour is snapshot" 0 "$STATUS"
assert_eq "the snapshot is shell.json, byte for byte" "$good" "$(cat "$state/recovery/last-good.json")"

echo '{"bar":{"right":["me.other"]}}' >"$cfg/shell.json"
capture haseen-shell-recover snapshot
assert_contains "a fresh edit has not proven itself" "$OUTPUT" "shell.json changed less than 10 minutes ago"
assert_eq "the snapshot stays" "$good" "$(cat "$state/recovery/last-good.json")"
touch -d '-1 hour' "$cfg/shell.json"
echo '{}' >"$state/safe-mode"
capture haseen-shell-recover snapshot
assert_contains "no snapshot in safe mode" "$OUTPUT" "safe mode is on"
rm -f "$state/safe-mode"

echo 'not json {' >"$cfg/shell.json"
echo failed >"$SANDBOX/unit-state"
use_journal no-plugin
: >"$calls"
HASEEN_INLINE=1 capture haseen-shell-recover present <<<"r"
assert_status "restore from the offer" 0 "$STATUS"
assert_eq "the last good shell.json is back" "$good" "$(cat "$cfg/shell.json")"
assert_eq "the broken one is kept, as it was" "not json {" "$(cat "$state/recovery/shell.json.replaced")"
assert_contains "and the shell starts again" "$(cat "$calls")" "--user start haseen-shell.service"
capture haseen-shell-recover restore-last
assert_contains "restoring twice changes nothing" "$OUTPUT" "already is the last good one"

: >"$calls"
HASEEN_INLINE=1 capture haseen-shell-recover offer <<<"c"
assert_contains "continue starts the shell as it is" "$(cat "$calls")" "--user start haseen-shell.service"

# --- the crash watcher keeps snapshots coming ------------------------------------
stub journalctl "sleep 1"
rm -f "$state/recovery/last-good.json"
stub haseen-shell-recover "echo snap >>'$SANDBOX/snapshots'"
HASEEN_SNAPSHOT_INTERVAL=0.2 capture timeout 5 "$REPO/bin/haseen-crash-watch"
assert_eq "the watcher asks for a snapshot on its interval" true "$([[ -s $SANDBOX/snapshots ]] && echo true || echo false)"
n="$(wc -l <"$SANDBOX/snapshots")"
sleep 0.5
assert_eq "and stops asking when it exits" "$n" "$(wc -l <"$SANDBOX/snapshots")"
rm -f "$SANDBOX/stubs/haseen-shell-recover"

# --- safe mode in the real engine ----------------------------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; safe mode engine scenario not run" >&2
else
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-recovery.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS

    mkdir -p "$cfg/plugins/me.svc" "$cfg/plugins/haseen.clock"
    cat >"$cfg/plugins/me.svc/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"me.svc","name":"Svc","version":"1.0.0","kinds":["service"],"entry":{"service":"Service.qml"},"provides":["probe"]}
JSON
    printf 'import QtQuick\nItem {\n    property string pluginId\n    property var settings\n    property var screen\n}\n' >"$cfg/plugins/me.svc/Service.qml"
    # A user copy of a built-in id: safe mode falls back to the built-in.
    cat >"$cfg/plugins/haseen.clock/manifest.json" <<'JSON'
{"schemaVersion":1,"id":"haseen.clock","name":"My clock","version":"1.0.0","kinds":["bar-widget"],"entry":{"bar-widget":"Widget.qml"}}
JSON
    : >"$cfg/plugins/haseen.clock/Widget.qml"
    echo '{"bar":{"left":[],"center":[],"right":[]},"services":["me.svc"]}' >"$cfg/shell.json"
    rm -f "$state/safe-mode"

    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    ln -s "$HASEEN_PATH/shell/ServiceHost.qml" "$harness/ServiceHost.qml"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Haseen
ShellRoot {
    id: probe
    property int phase: 0
    property var result: ({})
    function snap(tag) {
        const d = JSON.parse(Plugins.describe());
        result[tag] = {
            safeMode: Plugins.safeMode,
            reason: d.safeMode.reason || "",
            svcLoaded: !!Plugins.roles.probe,
            svcHeld: Plugins.held("me.svc"),
            svcEnabled: Config.isEnabled("me.svc"),
            omarchyHeld: Plugins.held("omarchy.ticker"),
            omarchyUrl: Plugins.entryUrl("omarchy.ticker", "service"),
            clockOrigin: Plugins.registry["haseen.clock"].origin,
            clockHeld: Plugins.held("haseen.clock"),
            clockUrl: Plugins.entryUrl("haseen.clock", "bar-widget"),
            describedHeld: d.plugins.filter(p => p.held).map(p => p.id).sort()
        };
    }
    Instantiator {
        model: ScriptModel { values: Plugins.serviceKeys }
        delegate: ServiceHost {}
    }
    FileView {
        id: flag
        path: Paths.userState + "/safe-mode"
        printErrors: false
    }
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            if (probe.phase === 0 && Plugins.ready && Plugins.roles.probe) {
                probe.snap("before");
                flag.setText(JSON.stringify({reason: "test", since: "2026-10-07T10:00:00+00:00"}));
                probe.phase = 1;
            } else if (probe.phase === 1 && Plugins.safeMode && !Plugins.roles.probe) {
                probe.snap("safe");
                Quickshell.execDetached(["rm", "-f", flag.path]);
                probe.phase = 2;
            } else if (probe.phase === 2 && !Plugins.safeMode && Plugins.roles.probe) {
                probe.snap("after");
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "safe mode scenario completes in the real engine" 0 "$STATUS"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        r() { jq -c "$1" <<<"$result"; }
        assert_eq "before: the user service runs" true "$(r .before.svcLoaded)"
        assert_eq "before: nothing is held" '[]' "$(r .before.describedHeld)"
        assert_eq "before: the user copy of haseen.clock wins" '"user"' "$(r .before.clockOrigin)"
        assert_eq "safe mode is seen without a restart" true "$(r .safe.safeMode)"
        assert_eq "its reason reaches the shell" '"test"' "$(r .safe.reason)"
        assert_eq "safe mode unloads the user service" false "$(r .safe.svcLoaded)"
        assert_eq "the user plugin is held" true "$(r .safe.svcHeld)"
        assert_eq "a held plugin reads as not enabled" false "$(r .safe.svcEnabled)"
        assert_eq "an Omarchy plugin is held" true "$(r .safe.omarchyHeld)"
        assert_eq "a held plugin has no entry to load" '""' "$(r .safe.omarchyUrl)"
        assert_eq "a user copy of a built-in gives way to it" '"builtin"' "$(r .safe.clockOrigin)"
        assert_eq "the built-in keeps running" false "$(r .safe.clockHeld)"
        assert_contains "the built-in entry loads" "$(r .safe.clockUrl)" "/shell/plugins/haseen.clock/Widget.qml"
        assert_eq "describe lists the held plugins" '["me.broken","me.svc","omarchy.ticker"]' "$(r .safe.describedHeld)"
        assert_eq "safe mode off loads the user service again" true "$(r .after.svcLoaded)"
        assert_eq "and the user copy wins again" '"user"' "$(r .after.clockOrigin)"
    else
        _fail "safe mode result not produced" "$OUTPUT"
    fi
fi
