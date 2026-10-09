# shellcheck shell=bash
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
sandbox vapt-menu-providers
QS_BIN=${QS_BIN:-/usr/bin/qs}
source "$FIXTURES/vapt-qml-lib.sh"
vapt_qml_available 'Security disabled/enabled menu provider engine scenarios' || return 0
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/share/haseen" "$FAKE/bin" "$SANDBOX/shell"
for entry in "$HASEEN_PATH"/*; do ln -s "$entry" "$FAKE/share/haseen/${entry##*/}"; done
cat >"$FAKE/bin/haseen" <<'SH'
#!/bin/sh
case "$*" in
    'vapt menu --enabled') exit 0 ;; # Even a stale successful guard cannot authorize a disabled provider.
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
for module in Haseen Compat Ui Commons plugins; do ln -s "$HASEEN_PATH/shell/$module" "$SANDBOX/shell/$module"; done
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
                    menu.searchProviders(); step++; return;
                }
                if (ids.some(id => !menu.items[id + ".empty"])) return;
                console.warn("PROVIDER-PASS enabled providers produce guarded rows");
                Qt.quit();
            }
        }
    }
}
QML
capture env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 HASEEN_PATH="$FAKE/share/haseen" PROVIDER_LOG="$SANDBOX/reads" timeout 30 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$SANDBOX/shell"
assert_status 'real menu provider harness exits' 0 "$STATUS"
assert_contains 'disabled root search and direct provider load do not queue' "$OUTPUT" 'PROVIDER-PASS disabled search and direct load queue no reads'
assert_contains 'enabled providers populate guarded rows' "$OUTPUT" 'PROVIDER-PASS enabled providers produce guarded rows'
assert_not_contains 'provider harness has no failed case' "$OUTPUT" 'PROVIDER-FAIL'
assert_eq 'only the three enabled provider reads execute' $'tool-list\nservice-list\ndoctor' "$(cat "$SANDBOX/reads")"
