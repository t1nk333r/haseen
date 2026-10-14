# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
sandbox vapt-menu-providers
# Quickshell's IPC socket must fit Linux's pathname limit even in a long worktree.
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vmp.XXXXXX")
chmod 0700 "$XDG_RUNTIME_DIR"
trap 'rm -rf "$XDG_RUNTIME_DIR"' EXIT
QS_BIN=${QS_BIN:-/usr/bin/qs}
source "$FIXTURES/vapt-qml-lib.sh"
vapt_qml_available 'Security disabled/enabled menu provider engine scenarios' '' qs || return 0
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/share/haseen" "$FAKE/bin" "$SANDBOX/shell"
for entry in "$HASEEN_PATH"/*; do ln -s "$entry" "$FAKE/share/haseen/${entry##*/}"; done
cat >"$FAKE/bin/haseen" <<'SH'
#!/bin/sh
case "$*" in
    'vapt menu --enabled')
        # The menu answers this guard from Config; a call here is a Python start.
        printf '%s\n' menu-enabled >>"$PROVIDER_LOG"
        exit 0 ;;
    'vapt tool-list --json')
        printf '%s\n' tool-list >>"$PROVIDER_LOG"
        printf '%s\n' '{"schemaVersion":1,"tools":[],"sources":[],"privateSource":{"state":"absent","reason":"fixture"}}' ;;
    'vapt service-list --json')
        printf '%s\n' service-list >>"$PROVIDER_LOG"
        printf '%s\n' '{"schemaVersion":1,"services":[]}' ;;
    'vapt doctor --json')
        printf '%s\n' doctor >>"$PROVIDER_LOG"
        printf '%s\n' '{"schemaVersion":1,"tools":[],"sources":[],"privateSource":{"state":"absent","reason":"fixture"},"provisioning":{"state":"healthy","exitCode":0,"diagnostics":[]},"workflow":{"settings":{"schemaVersion":1,"showLocalAddresses":false,"enumerationScript":null,"bindAddress":"127.0.0.1"},"entrypoints":0,"documentationReady":0,"capabilities":[]}}' ;;
    *) exit 1 ;;
esac
SH
chmod +x "$FAKE/bin/haseen"
for module in Haseen Compat Ui Commons; do ln -s "$HASEEN_PATH/shell/$module" "$SANDBOX/shell/$module"; done
# Every plugin but the optional panel: the menu must not need its files.
mkdir "$SANDBOX/shell/plugins"
for plugin in "$HASEEN_PATH"/shell/plugins/*; do
    [[ ${plugin##*/} == haseen.security ]] || ln -s "$plugin" "$SANDBOX/shell/plugins/${plugin##*/}"
done
cat >"$SANDBOX/shell/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Haseen
import "plugins/haseen.menu" as Menu
ShellRoot {
    Window {
        visible: true; width: 720; height: 640
        Menu.Panel { id: menu; pluginId: "haseen.menu" }
        Timer {
            interval: 200; repeat: true; running: true
            property int step: 0
            property int ticks: 0
            readonly property var ids: ["setup.security.vapt.tools", "setup.security.vapt.services", "setup.security.vapt.local"]
            onTriggered: {
                if (++ticks > 100) { console.warn("PROVIDER-FAIL timeout"); Qt.quit(); return; }
                if (!menu.loaded || !Config.defaults.plugins) return;
                if (step === 0) {
                    const off = menu.whenResults["setup.security.vapt.tools"];
                    if (off === undefined) return;
                    console.warn("PROVIDER-PASS menu loaded and answered its guards");
                    if (off !== false) console.warn("PROVIDER-FAIL disabled Security guard answered " + off);
                    else console.warn("PROVIDER-PASS disabled Security guard answered false");
                    Config.setRuntime(["plugins", "haseen.security", "enabled"], false);
                    menu.itemOrder = ids;
                    menu.searchProviders();
                    for (const id of ids) menu.loadProvider(id, true);
                    step++; return;
                }
                if (step === 1) {
                    if (ids.some(id => menu.providersLoaded[id]) || menu.providerQueue.length !== 0) console.warn("PROVIDER-FAIL disabled read queued");
                    else console.warn("PROVIDER-PASS disabled search and direct load queue no reads");
                    // Shell checks the log emitted before the marker independently.
                    Config.setRuntime(["plugins", "haseen.security", "enabled"], true);
                    menu.searchProviders(); menu.evaluateGuards(); step++; return;
                }
                if (ids.some(id => !menu.items[id + ".empty"]) || menu.whenResults["setup.security.vapt.tools"] !== true) return;
                console.warn("PROVIDER-PASS enabled providers produce guarded rows");
                Qt.quit();
            }
        }
    }
}
QML
capture env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 HASEEN_PATH="$FAKE/share/haseen" PROVIDER_LOG="$SANDBOX/reads" timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$SANDBOX/shell"
assert_status 'real menu provider harness exits' 0 "$STATUS"
assert_contains 'the menu loads without the haseen.security directory' "$OUTPUT" 'PROVIDER-PASS menu loaded and answered its guards'
assert_contains 'disabled Security hides its rows without running the CLI' "$OUTPUT" 'PROVIDER-PASS disabled Security guard answered false'
assert_contains 'disabled root search and direct provider load do not queue' "$OUTPUT" 'PROVIDER-PASS disabled search and direct load queue no reads'
assert_contains 'enabled providers populate guarded rows' "$OUTPUT" 'PROVIDER-PASS enabled providers produce guarded rows'
assert_not_contains 'provider harness has no failed case' "$OUTPUT" 'PROVIDER-FAIL'
# No `menu-enabled` line: the guard never ran the CLI, Security off or on.
assert_eq 'only the three enabled provider reads execute' $'tool-list\nservice-list\ndoctor' "$(cat "$SANDBOX/reads")"
