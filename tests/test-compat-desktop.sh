# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-info bin/haseen-plugin-validate share/haseen/VERSION
# haseen:covers share/haseen/default/shell.json share/haseen/omarchy/bin/omarchy
# haseen:covers share/haseen/shell/Compat/** share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/*/manifest.json tools/smoke-session.conf
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# DMS desktop widgets, the startupCheck gate, DMSNetworkService and the
# ydotool shim (architecture 5.4).

# --- ydotool shim: keys reach Hyprland's send_key_state, never uinput -------
sandbox compat-desktop-ydotool
XDG_RUNTIME_DIR="$SANDBOX/run"
mkdir -p "$XDG_RUNTIME_DIR"
export XDG_RUNTIME_DIR HYPRLAND_INSTANCE_SIGNATURE=fixture-sig
log="$SANDBOX/hyprctl.log"
stub hyprctl "printf '%s\n' \"\$*\" >>'$log'; echo ok"
shim="$HASEEN_PATH/shell/Compat/bin/ydotool"
send() { printf 'dispatch hl.dsp.send_key_state({ mods = "%s", key = "%s", state = "%s", window = "activewindow" })' "$@"; }

capture "$shim" key -d 0 30:1 30:0
assert_status "a key press and release are accepted" 0 "$STATUS"
assert_eq "press and release dispatch code+8 down then up to the active window" \
    "$(send "" 38 down)"$'\n'"$(send "" 38 up)" "$(cat "$log")"

: >"$log"
capture "$shim" key -d 0 42:1
assert_eq "a modifier alone dispatches nothing" "" "$(cat "$log")"
capture "$shim" key -d 0 35:1 35:0
assert_eq "a held Shift is sent as mods with the next key" \
    "$(send SHIFT 43 down)"$'\n'"$(send SHIFT 43 up)" "$(cat "$log")"
: >"$log"
capture "$shim" key -d 0 42:0 23:1 23:0
assert_eq "42:0 releases Shift for the keys after it" \
    "$(send "" 31 down)"$'\n'"$(send "" 31 up)" "$(cat "$log")"

: >"$log"
capture "$shim" key --dry-run -d 0 30:1 30:0
assert_status "dry run accepted" 0 "$STATUS"
assert_eq "--dry-run sends nothing to Hyprland" "" "$(cat "$log" 2>/dev/null)"
assert_contains "--dry-run shows the dispatch it would send" "$OUTPUT" "send_key_state"

capture "$shim" key 30:2
assert_status "a state other than 0/1 is refused" 2 "$STATUS"

# Codes and delays are decimal even with a leading zero: bash arithmetic
# would read 010 as octal 8 and refuse 08 outright.
: >"$log"
capture "$shim" key -d 0 010:1 08:0
assert_status "leading-zero codes are accepted" 0 "$STATUS"
assert_eq "a leading-zero code is decimal: 010 is 10, 08 is 8" \
    "$(send "" 18 down)"$'\n'"$(send "" 16 up)" "$(cat "$log")"
: >"$log"
capture "$shim" key -d 0 042:1 30:1 042:0 30:0
assert_eq "a leading-zero modifier code is held like 42" \
    "$(send SHIFT 38 down)"$'\n'"$(send "" 38 up)" "$(cat "$log")"
# The delay between keys is whole seconds plus milliseconds.
sleeps="$SANDBOX/sleep.log"
stub sleep "printf '%s\n' \"\$*\" >>'$sleeps'"
for delay in 1500 1000 0100 7; do
    capture "$shim" key -d "$delay" 30:1 30:0
done
rm -f "$SANDBOX/stubs/sleep"
assert_eq "-d sleeps its milliseconds, past one second too" \
    $'1.500\n1.000\n0.100\n0.007' "$(cat "$sleeps")"

# Only the interpreter and path helpers accompany the passthrough fixture.
# System PATH entries would select an installed ydotool before our fake.
shim_tools="$SANDBOX/shim-tools"
mkdir -p "$shim_tools"
for tool in bash dirname readlink; do
    ln -s "$(command -v "$tool")" "$shim_tools/$tool"
done
mkdir -p "$SANDBOX/real"
printf '#!/bin/sh\necho "real ydotool: $*"\n' >"$SANDBOX/real/ydotool"
chmod +x "$SANDBOX/real/ydotool"
capture env PATH="$HASEEN_PATH/shell/Compat/bin:$SANDBOX/real:$shim_tools" ydotool mousemove -x 5 -y 6
assert_status "a non-key command reaches the real ydotool" 0 "$STATUS"
assert_eq "with its arguments untouched" "real ydotool: mousemove -x 5 -y 6" "$OUTPUT"
capture env PATH="$HASEEN_PATH/shell/Compat/bin:$shim_tools" ydotool mousemove -x 5
assert_status "without a real ydotool a non-key command fails" 2 "$STATUS"
assert_contains "missing passthrough reports its own refusal" "$OUTPUT" "only 'ydotool key' is provided under haseen"

# --- manifest: a DMS desktop surface is an overlay ---------------------------
sandbox compat-desktop-manifest
P="$XDG_CONFIG_HOME/haseen/plugins"
mkdir -p "$P/Desk" "$P/Launch"
printf '%s\n' '{"id":"deskFixture","name":"Desk","version":"1.0.0","type":"desktop","component":"./Desk.qml"}' >"$P/Desk/plugin.json"
printf 'import QtQuick\nItem {}\n' >"$P/Desk/Desk.qml"
printf '%s\n' '{"id":"launchFixture","name":"Launch","version":"1.0.0","type":"launcher","component":"./L.qml"}' >"$P/Launch/plugin.json"
printf 'import QtQuick\nItem {}\n' >"$P/Launch/L.qml"
capture haseen-plugin-info dms.desk-fixture
assert_contains "a DMS desktop plugin is an overlay" "$OUTPUT" "kinds:       overlay"
assert_contains "loaded from its component" "$OUTPUT" "overlay -> Desk.qml"
capture haseen-plugin-validate dms.desk-fixture
assert_status "a DMS desktop plugin validates" 0 "$STATUS"
capture haseen-plugin-validate dms.launch-fixture
assert_status "a DMS launcher stays unsupported" 1 "$STATUS"

# --- QML: startupCheck gate, desktop geometry, DMSNetworkService -------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; DMS desktop scenario not run" >&2
else
    sandbox compat-desktop
    XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    export XDG_RUNTIME_DIR
    unset DISPLAY WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE DBUS_SESSION_BUS_ADDRESS
    stub notify-send "printf '%s\n' \"\$*\" >>'$SANDBOX/notify.log'"
    P="$XDG_CONFIG_HOME/haseen/plugins"
    allow="$SANDBOX/allow"
    echo no >"$allow"
    plugin() { # DIR ID TYPE [CHECK-QML]
        mkdir -p "$P/$1"
        printf '{"id":"%s","name":"%s","version":"1.0.0","type":"%s","component":"./Main.qml"%s}\n' \
            "$2" "$1" "$3" "${4:+,\"startupCheck\":\"./Check.qml\"}" >"$P/$1/plugin.json"
        printf 'import QtQuick\nItem { property real defaultWidth: 240; property real defaultHeight: 160 }\n' >"$P/$1/Main.qml"
        [[ -z ${4:-} ]] || printf '%s\n' "$4" >"$P/$1/Check.qml"
    }
    # Asynchronous, so the second host asks while the first check runs.
    plugin Pass passFixture daemon 'import QtQuick
Item { function check(done) { console.log("CHECK-RAN pass"); t.done = done; t.start(); }
  Timer { id: t; property var done; interval: 300; onTriggered: done(null) } }'
    plugin Fail failFixture daemon 'import QtQuick
QtObject { function check() { return { title: "fixture-tool missing", details: "install it" }; } }'
    plugin Retry retryFixture daemon "import QtQuick
import Quickshell.Io
QtObject {
  property FileView f: FileView { path: \"$allow\"; blockLoading: true }
  function check(done) { console.log(\"CHECK-RAN retry\"); f.reload(); done(f.text().trim() === \"yes\" ? null : \"not yet\"); } }"
    plugin Silent silentFixture daemon 'import QtQuick
QtObject { function check(done) { console.log("CHECK-RAN silent"); } }'
    plugin Placed placedFixture desktop
    plugin Free freeFixture desktop
    printf '%s\n' '{"bar":{"left":[],"center":[],"right":[]},"services":[],"plugins":{"dms.placed-fixture":{"settings":{"desktop":{"x":30,"y":40,"width":200,"height":120}}},"dms.free-fixture":{}}}' >"$XDG_CONFIG_HOME/haseen/shell.json"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Common Services Widgets Modules; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    # No layer-shell backend offscreen, so the desktop window itself cannot
    # exist; its geometry is the window's own DesktopGeometry.js, fed the
    # registry's overlay entry and shell.json settings as DmsDesktopHost does.
    cat >"$harness/shell.qml" <<QML
import QtQuick
import Quickshell
import qs.Haseen
import qs.Compat as Compat
import qs.Services as Dms
import "Compat/DesktopGeometry.js" as Geometry
ShellRoot {
    id: probe
    property var r: ({})
    property int step: 0
    property double mark: 0
    function since() { return Date.now() - mark; }
    function next() { step++; mark = Date.now(); }
    function finish() { console.log("RESULT " + JSON.stringify(r)); loader.active = false; Qt.quit(); }
    function placeOf(id) {
        const c = Qt.createComponent(Plugins.entryUrl(id, "overlay"));
        const item = c.createObject(probe);
        const size = Geometry.defaultSize(item);
        const settings = Plugins.settingsFor(id);
        const g = Geometry.place(settings.desktop, 1920, 1080, { defaultWidth: size.width, defaultHeight: size.height, minWidth: 100, minHeight: 100, forceSquare: false, resizeWidth: -1, resizeHeight: -1 });
        item.destroy();
        return [g.x, g.y, g.width, g.height];
    }
    Loader {
        id: loader
        active: Plugins.ready
        sourceComponent: Item {
            property alias pass1: pass1
            property alias pass2: pass2
            property alias fail: fail
            Compat.DmsServiceHost { id: pass1; pluginId: "dms.pass-fixture" }
            Compat.DmsServiceHost { id: pass2; pluginId: "dms.pass-fixture" }
            Compat.DmsServiceHost { id: fail; pluginId: "dms.fail-fixture" }
        }
    }
    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            const h = loader.item, r = probe.r;
            if (!h) return;
            switch (probe.step) {
            case 0:
                r.passWaits = h.pass1.instance !== null || h.pass2.instance !== null;
                r.kinds = [Plugins.registry["dms.placed-fixture"].kinds, Plugins.entryUrl("dms.placed-fixture", "overlay").endsWith("/Placed/Main.qml")];
                r.placed = probe.placeOf("dms.placed-fixture");
                r.centred = probe.placeOf("dms.free-fixture");
                // A check that never calls done is refused once its time is up.
                Compat.DmsStartupGate.checkTimeoutMs = 400;
                Compat.DmsStartupGate.run("dms.silent-fixture", ok => r.silent = ok);
                probe.next(); break;
            case 1:
                if (probe.since() < 1500) break;
                r.passStarted = [h.pass1.instance !== null, h.pass2.instance !== null];
                r.failStarted = h.fail.instance !== null;
                r.errors = Plugins.errors.filter(e => e.id === "dms.fail-fixture").map(e => e.message);
                r.silentErrors = Plugins.errors.filter(e => e.id === "dms.silent-fixture").map(e => e.message);
                Compat.DmsStartupGate.run("dms.retry-fixture", ok => r.retry1 = ok);
                probe.next(); break;
            case 2:
                if (probe.since() < 300) break;
                Quickshell.execDetached(["sh", "-c", "echo yes >'$allow'"]);
                probe.next(); break;
            case 3:
                if (probe.since() < 500) break;
                Compat.DmsStartupGate.run("dms.retry-fixture", ok => r.retry2 = ok);
                probe.next(); break;
            case 4:
                if (probe.since() < 300) break;
                Compat.DmsStartupGate.run("dms.retry-fixture", ok => r.retry3 = ok);
                r.ssid = Dms.DMSNetworkService.currentWifiSSID;
                r.status = Dms.DMSNetworkService.networkStatus;
                try { Dms.DMSNetworkService.currentWifiSSID = "spoofed"; r.ssidWritable = true; }
                catch (e) { r.ssidWritable = false; }
                r.ssidAfter = Dms.DMSNetworkService.currentWifiSSID;
                probe.next(); break;
            case 5:
                if (probe.since() < 300) break;
                probe.finish();
            }
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        DBUS_SYSTEM_BUS_ADDRESS="unix:path=$SANDBOX/no-system-bus" \
        timeout 40 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    if [[ -n $result ]]; then
        get() { jq -c "$1" <<<"$result"; }
        assert_eq "the shell registry loads a DMS desktop surface as an overlay" '[["overlay"],true]' "$(get .kinds)"
        assert_eq "a host waits for its plugin's startupCheck" false "$(get .passWaits)"
        assert_eq "a passing check lets both hosts load the plugin" '[true,true]' "$(get .passStarted)"
        assert_eq "the check runs once for two hosts" 1 "$(grep -c 'CHECK-RAN pass' <<<"$OUTPUT")"
        assert_eq "a failing check keeps the plugin unloaded" false "$(get .failStarted)"
        assert_eq "the refusal is reported as a plugin error" '["dms: startup check: fixture-tool missing"]' "$(get .errors)"
        assert_contains "and as a notification with its details" "$(cat "$SANDBOX/notify.log" 2>/dev/null)" "fixture-tool missing"$'\n\n'"install it"
        assert_eq "a check that never calls done is refused after its timeout" false "$(get .silent)"
        assert_eq "with an error that says so" '["dms: startup check: startupCheck did not call done() within 0.4 s"]' "$(get .silentErrors)"
        assert_eq "settings.desktop places and sizes the widget" '[30,40,200,120]' "$(get .placed)"
        assert_eq "without settings it is centred at the plugin's own size" '[840,460,240,160]' "$(get .centred)"
        assert_eq "a refused check reports false" false "$(get .retry1)"
        assert_eq "a refusal is checked again on the next request" true "$(get .retry2)"
        assert_eq "a pass is then remembered" 2 "$(grep -c 'CHECK-RAN retry' <<<"$OUTPUT")"
        assert_eq "and answers true" true "$(get .retry3)"
        assert_eq "DMSNetworkService has no SSID without NetworkManager" '""' "$(get .ssid)"
        assert_eq "and reports disconnected" '"disconnected"' "$(get .status)"
        assert_eq "currentWifiSSID cannot be written by a plugin" false "$(get .ssidWritable)"
        assert_eq "and keeps its value" '""' "$(get .ssidAfter)"
        assert_not_contains "no QML type errors" "$OUTPUT" "TypeError"
    else
        _fail "DMS desktop result not produced" "$OUTPUT"
    fi
fi
