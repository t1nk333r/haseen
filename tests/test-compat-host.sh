# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Scoped persistence boundaries; no original plugin runs.
sandbox compat-host-settings
p="$XDG_CONFIG_HOME/haseen/plugins/me.host"
mkdir -p "$p" "$XDG_CONFIG_HOME/omarchy"
printf '%s\n' '{"schemaVersion":1,"id":"me.host","name":"Host fixture","version":"1.0.0","kinds":["service"],"entry":{"service":"Service.qml"},"settings":{},"permissions":[]}' >"$p/manifest.json"
printf 'import QtQuick\nQtObject {}\n' >"$p/Service.qml"
printf '%s\n' '{"owner":"untouched"}' >"$XDG_CONFIG_HOME/omarchy/shell.json"
config="$XDG_CONFIG_HOME/haseen/shell.json"
request='{"settings":{"value":7,"nested":{"new":true}}}'
capture haseen-plugin-settings me.host --dry-run <<<"$request"
assert_status "settings dry run accepted" 0 "$STATUS"
assert_dry_pure "settings dry run" "$OUTPUT"
assert_eq "dry run creates neither config nor lock" 0 "$(find "$XDG_CONFIG_HOME/haseen" -maxdepth 1 -type f | wc -l)"
printf '%s\n' '{"owner":{"custom":true},"bar":{"height":31},"plugins":{"me.host":{"enabled":false,"settings":{"keep":9,"nested":{"old":true}}},"me.other":{"settings":{"secret":"fixture-only"}}}}' >"$config"
capture haseen-plugin-settings me.host <<<"$request"
assert_status "own settings write accepted" 0 "$STATUS"
assert_eq "nested own settings merge preserves existing keys" '{"old":true,"new":true}' "$(jq -c '.plugins["me.host"].settings.nested' "$config")"
assert_eq "unrelated user setting remains" true "$(jq '.owner.custom and (.plugins["me.other"].settings.secret == "fixture-only") and (.plugins["me.host"].enabled == false) and (.bar.height == 31)' "$config")"
assert_eq "Omarchy config never changes" '{"owner":"untouched"}' "$(cat "$XDG_CONFIG_HOME/omarchy/shell.json")"
assert_eq "atomic temporary file gone" no "$([[ -e $config.new ]] && echo yes || echo no)"
before="$(cat "$config")"
for request in \
    '{"changes":[{"path":["plugins","me.other","settings","value"],"value":1}]}' \
    '{"changes":[{"path":["services"],"value":[]}]}' \
    '{"settings":{"__proto__":{"bad":true}}}' \
    '{"changes":[{"path":["bar","position"],"value":"diagonal"}]}' \
    '{"changes":[{"path":["bar","height","nested"],"value":1}]}' \
    '{} {}'; do
    capture haseen-plugin-settings me.host <<<"$request"
    assert_status "invalid/out-of-scope request refused" 1 "$STATUS"
    assert_eq "refused mutation leaves user config unchanged" "$before" "$(cat "$config")"
done
request='{"changes":[{"path":["idle","screensaver"],"value":180}],"idleProvider":"haseen.idle"}'
capture haseen-plugin-settings me.host <<<"$request"
assert_status "legacy screensaver timeout accepted" 0 "$STATUS"
assert_eq "idle timeout uses actual haseen key" 180 "$(jq '.plugins["haseen.idle"].settings.screensaverAfter' "$config")"
assert_eq "legacy idle branch is not written" false "$(jq 'has("idle")' "$config")"
# Concurrent screens/widgets read under the same lock, so neither update
# overwrites the other's independent key.
haseen-plugin-settings me.host <<< '{"settings":{"first":1}}' >"$SANDBOX/first.out" 2>"$SANDBOX/first.err" &
first=$!
haseen-plugin-settings me.host <<< '{"settings":{"second":2}}' >"$SANDBOX/second.out" 2>"$SANDBOX/second.err" &
second=$!
wait "$first" && wait "$second"
assert_eq "concurrent settings writes both survive" true "$(jq '.plugins["me.host"].settings | .first == 1 and .second == 2 and .keep == 9' "$config")"
printf 'owner is currently editing\n' >"$config"
capture haseen-plugin-settings me.host <<< '{"settings":{"value":0}}'
assert_status "malformed user config is never overwritten" 1 "$STATUS"
assert_eq "malformed user's bytes remain" 'owner is currently editing' "$(cat "$config")"


# Root declarations (Compat/Host.js propertiesFor): a plugin rooted at a module
# type with no QML file of that name (Row, MouseArea, RowLayout, ...) declares
# only its own properties, as for Item; a same-directory base file is still
# followed, and one that exists but cannot be parsed, or a cycle, still
# refuses the entry. Real engine, no windows.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; root declarations not exercised" >&2
else
    sandbox compat-host-roots
    XDG_RUNTIME_DIR="$(mktemp -d "${TMPDIR:-/tmp}/haseen-compat-host.XXXXXX")"
    export XDG_RUNTIME_DIR
    trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
    chmod 700 "$XDG_RUNTIME_DIR"
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    roots="$SANDBOX/roots"
    mkdir -p "$roots"
    printf 'import QtQuick\nRow { property var bar; readonly property int fixed: 1 }\n' >"$roots/RowRoot.qml"
    printf 'import QtQuick.Layouts as L\nL.RowLayout { property var settings }\n' >"$roots/Aliased.qml"
    printf 'import QtQuick\nItem { property string moduleName }\n' >"$roots/Base.qml"
    printf 'import QtQuick\nBase { property var bar }\n' >"$roots/Derived.qml"
    printf 'not qml at all\n' >"$roots/Broken.qml"
    printf 'import QtQuick\nBroken { property var bar }\n' >"$roots/OnBroken.qml"
    printf 'import QtQuick\nCycleB { property var a }\n' >"$roots/CycleA.qml"
    printf 'import QtQuick\nCycleA { property var b }\n' >"$roots/CycleB.qml"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    # Host.js reads files through a FileView created beside it, so the Compat
    # directory needs its qs.* modules as in the shell.
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<QML
import QtQuick
import Quickshell
import "Compat/Host.js" as Host
ShellRoot {
    id: probe
    function declared(name) {
        try {
            const props = Host.propertiesFor("file://$roots/" + name + ".qml", null, probe);
            return Object.keys(props).sort().map(k => k + (props[k].writable ? "" : "!")).join(",");
        } catch (e) { return "error: " + String(e); }
    }
    Component.onCompleted: {
        const r = {};
        for (const name of ["RowRoot", "Aliased", "Derived", "OnBroken", "CycleA"]) r[name] = declared(name);
        console.warn("RESULT " + JSON.stringify(r));
        Qt.callLater(Qt.quit);
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        QT_FORCE_STDERR_LOGGING=1 timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    assert_status "root declarations scenario completes in the real engine" 0 "$STATUS"
    roots_result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $roots_result ]]; then
        root_of() { jq -r --arg k "$1" '.[$k]' <<<"$roots_result"; }
        assert_eq "a Row root declares its own properties" "bar,fixed!" "$(root_of RowRoot)"
        assert_eq "an aliased module root declares its own properties" settings "$(root_of Aliased)"
        assert_eq "a same-directory base file is still followed" bar,moduleName "$(root_of Derived)"
        assert_contains "a base file that cannot be parsed refuses the entry" "$(root_of OnBroken)" "cannot resolve root Broken"
        assert_contains "a cycle refuses the entry" "$(root_of CycleA)" "cyclic QML root inheritance"
    else
        _fail "root declarations scenario produced no result" "$OUTPUT"
    fi
fi
