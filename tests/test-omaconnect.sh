# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 098: haseen.omaconnect, ported from jitendradara12's OmaConnect. The
# manifest validates and the plugin is off by default; `haseen kdeconnect`
# reads and changes KDE Connect over a fake gdbus (tests/fixtures/
# kdeconnect-gdbus.sh); `haseen setup kdeconnect` plans its firewall rules;
# Model.js runs under the Qt JS engine; service, widget and panel run in the
# real Quickshell engine.

SHELL_DIR="$HASEEN_PATH/shell"
PLUGIN="$SHELL_DIR/plugins/haseen.omaconnect"
QML_BIN=${QML_BIN:-/usr/lib/qt6/bin/qml}
QS_BIN=${QS_BIN:-/usr/bin/qs}

sandbox omaconnect
LOG="$SANDBOX/log"
export FAKE_LOG="$LOG"
cp "$FIXTURES/kdeconnect-gdbus.sh" "$SANDBOX/stubs/gdbus"
for c in kdeconnect-cli kdeconnect-sms kdeconnect-app dbus-monitor; do
    stub "$c" "echo \"$c \$*\" >>'$LOG'"
done
stub busctl "echo \"busctl \$*\" >>'$LOG'"

# --- manifest, contract and house rules ---------------------------------------
capture haseen plugin validate haseen.omaconnect
assert_status "omaconnect validates" 0 "$STATUS"
assert_contains "omaconnect is a built-in" "$OUTPUT" "ok: haseen.omaconnect (builtin:"
assert_not_contains "it asks for no internet access" "$OUTPUT" "warning:"
assert_eq "service, bar widget and panel" "service bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "off by default" "" \
    "$(jq -r '[.bar.left, .bar.center, .bar.right, .services] | add | map(select(. == "haseen.omaconnect")) | .[]' "$HASEEN_PATH/default/shell.json")"
assert_eq "it needs KDE Connect's tools" '["kdeconnect-cli","gdbus","dbus-monitor"]' "$(jq -c .requires.bins "$PLUGIN/manifest.json")"
for f in Service.qml Widget.qml Panel.qml; do
    entry="$(cat "$PLUGIN/$f")"
    assert_contains "$f declares pluginId" "$entry" "property string pluginId"
    assert_contains "$f declares settings" "$entry" "property var settings: ({})"
    assert_contains "$f declares screen" "$entry" "property var screen: null"
done
for key in $(grep -ohE 'settings\.[a-zA-Z]+' "$PLUGIN"/*.qml | cut -d. -f2 | sort -u); do
    assert_eq "declares the setting $key it reads" true "$(jq --arg k "$key" '.settings | has($k)' "$PLUGIN/manifest.json")"
done
assert_eq "keeps upstream's setting names (the migration copies them)" \
    "defaultPingMessage showActionClipboard showActionFile showActionPing showActionRing showActionSms showActionText showBarBattery showBatteryStats showDeviceTypeIcons showMediaPlayer showNetworkStats showRemoteCommands showTailscale showTroubleshooting" \
    "$(jq -r '.settings | keys - ["debugIpc"] | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "no hex colour literals" "" "$(grep -rnE '#[0-9a-fA-F]{3,8}\b' "$PLUGIN" --include='*.qml' --include='*.js' || true)"
assert_eq "no Omarchy dependency" "" "$(grep -rnE 'omarchy-|OMARCHY_PATH|qs\.Commons|qs\.Ui' "$PLUGIN" || true)"
assert_eq "no sudo outside common.sh" "" "$(grep -nE '\bsudo\b' "$REPO/bin/haseen-kdeconnect" "$REPO/bin/haseen-setup-kdeconnect" | grep -v '^[^:]*:[0-9]*:#' || true)"
assert_eq "no shell strings: every command is an argv" "" "$(grep -rnE '"(ba)?sh", *"-l?c"' "$PLUGIN" || true)"
assert_eq "user apps start in their own scope" "3" "$(grep -c 'Apps.launch(' "$PLUGIN/Service.qml")"
assert_eq "the only repeating timer is the monitor-down rescan" "1" "$(grep -c 'repeat: true' "$PLUGIN/Service.qml")"
assert_contains "the MIT notice is kept" "$(cat "$PLUGIN/Model.js")" "MIT, Copyright (c) 2026 OmaConnect contributors"
assert_contains "NOTICE.md lists the port" "$(cat "$REPO/NOTICE.md")" "haseen.omaconnect"

# --- haseen kdeconnect against the fake bus ------------------------------------
capture haseen kdeconnect devices
assert_status "devices succeeds" 0 "$STATUS"
assert_eq "devices: saved addresses first" "CUSTOM_ADDRESSES_READY
CUSTOM_ADDRESS	192.0.2.7" "$(head -2 <<<"$OUTPUT")"
assert_eq "devices: the paired phone" "DEVICE	abc123	Pixel 9	phone	true	true	64	true	kdeconnect_battery,kdeconnect_ping,kdeconnect_share,kdeconnect_runcommand,kdeconnect_findmyphone,kdeconnect_clipboard,kdeconnect_connectivity_report,kdeconnect_sms,kdeconnect_mprisremote	5G	3	false	false	" \
    "$(sed -n 3p <<<"$OUTPUT")"
assert_eq "devices: the tablet asking to pair, with its key" "DEVICE	def456	Tab S9	tablet	false	true	-1	false	kdeconnect_ping		-1	false	true	1A2B3C4D" "$(sed -n 4p <<<"$OUTPUT")"
assert_eq "devices: no probe of the device's network" "" "$(grep -E 'ping|/dev/tcp' "$LOG" | grep -v 'kdeconnect_ping\|--ping' || true)"
FAKE_DAEMON_OFF=1 capture haseen kdeconnect devices
assert_status "devices: 69 while the daemon is away" 69 "$STATUS"

capture haseen kdeconnect media status abc123
assert_eq "media: the player as JSON" '{"isPlaying":true,"title":"Song","artist":"Band","album":"","player":"Spotify","albumArt":"https://example.test/cover.jpg","playerList":["Spotify","YT Music"]}' "$OUTPUT"
capture haseen kdeconnect media action abc123 Next
assert_contains "media: an action" "$(tail -1 "$LOG")" "mprisremote.sendAction Next"
capture haseen kdeconnect media action abc123 Explode
assert_status "media: an unknown action is refused" 64 "$STATUS"
capture haseen kdeconnect media status '../x'
assert_status "media: a bad device id is refused" 64 "$STATUS"

: >"$LOG"
capture haseen kdeconnect pair accept def456 --dry-run
assert_contains "pair: dry run prints the call" "$OUTPUT" "DRYRUN: gdbus call --session --dest org.kde.kdeconnect --object-path /modules/kdeconnect/devices/def456 --method org.kde.kdeconnect.device.acceptPairing"
assert_eq "pair: dry run calls nothing" "" "$(cat "$LOG")"
capture haseen kdeconnect pair reject def456
assert_contains "pair: reject cancels" "$(cat "$LOG")" "org.kde.kdeconnect.device.cancelPairing"

capture haseen kdeconnect address add 192.0.2.9
assert_eq "address: added after the saved one" "busctl --user set-property org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon customDevices as 2 192.0.2.7 192.0.2.9" "$(tail -1 "$LOG")"
capture haseen kdeconnect address remove 192.0.2.7
assert_eq "address: removed" "busctl --user set-property org.kde.kdeconnect /modules/kdeconnect org.kde.kdeconnect.daemon customDevices as 0" "$(tail -1 "$LOG")"
for bad in -x 192.0.2.9/24 'a b' host.example; do
    capture haseen kdeconnect address add "$bad"
    assert_status "address: refuses $bad" 64 "$STATUS"
done
capture haseen kdeconnect --help
assert_status "--help" 0 "$STATUS"

# --- haseen setup kdeconnect -----------------------------------------------------
stub ufw ":"
capture haseen setup kdeconnect on --dry-run --yes
assert_contains "setup: ufw opens TCP 1714-1764" "$OUTPUT" "DRYRUN: sudo ufw allow 1714:1764/tcp comment KDE Connect"
assert_contains "setup: and UDP" "$OUTPUT" "DRYRUN: sudo ufw allow 1714:1764/udp comment KDE Connect"
assert_dry_pure "setup on" "$OUTPUT"
capture haseen setup kdeconnect off --dry-run --yes
assert_contains "setup off closes them" "$OUTPUT" "DRYRUN: sudo ufw delete allow 1714:1764/tcp"
assert_dry_pure "setup off" "$OUTPUT"

# --- Model.js under the Qt JS engine -------------------------------------------
if [[ -x $QML_BIN ]]; then
    harness="$SANDBOX/harness"
    mkdir -p "$harness"
    haseen kdeconnect devices | jq -Rs '"var scan = " + tojson + ";"' -r >"$harness/data.js"
    cat >"$harness/Harness.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as M
import "data.js" as D
Item {
    function out(k, v) { console.warn("RESULT " + k + " " + JSON.stringify(v)); }
    Component.onCompleted: {
        const s = M.parseScan(D.scan + "DEVICE\tbad id\tx\n" + D.scan);
        out("scan", [s.devices.map(d => d.id), s.addresses, s.addressesReady]);
        const phone = s.devices[0], tab = s.devices[1];
        out("phone", [M.status(phone), M.details(phone, true, true), M.details(phone, false, true), M.canAct(phone), phone.caps.media, phone.caps.sms, M.batteryGlyph(phone) === "\u{F0084}"]);
        out("tablet", [M.status(tab), M.formatKey(tab.verificationKey), M.canAct(tab), tab.caps.ring]);
        out("pick", [M.pickDevice(s.devices, "def456"), M.pickDevice(s.devices, "gone"), M.pickDevice([], "x")]);
        out("addr", ["192.0.2.1", "256.1.1.1", "fd7a:115c:a1e0::1", "1:2:3:4:5:6:7:8", "1::2::3", "-1.2.3.4", "1.2.3.4/24", ""].map(M.addressError));
        const ts = M.parseTailscale('{"BackendState":"Running","Self":{"TailscaleIPs":["192.0.2.2","fd7a::2"]},"Peer":{"k1":{"HostName":"zed","TailscaleIPs":["192.0.2.5"],"Online":false},"k2":{"DNSName":"alpha.tail.ts.net.","TailscaleIPs":["192.0.2.6"],"Online":true},"k3":{"HostName":"v6only","TailscaleIPs":["fd7a::9"]}}}');
        out("ts", [ts.running, ts.self, ts.peers.map(p => p.name + "@" + p.address), M.filterPeers(ts.peers, "ZED").length, M.parseTailscale("nope")]);
        out("cmds", [M.parseCommands('{"k1":{"name":"Lock","command":"loginctl lock-session"},"k2":{"name":"Mute"}}'), M.parseCommands("- one: First\n2. two\nNo commands defined"), M.parseCommands("")]);
        const m = M.parseMedia('{"isPlaying":true,"title":"Song","artist":"Band","player":"Spotify","albumArt":"https://example.test/a.jpg","playerList":["Spotify",3]}');
        out("media", [m.albumArt, m.playerList, M.mediaLine(m), M.hasMedia(M.parseMedia("x")), M.parseMedia('{"albumArt":"file:///tmp/a.jpg"}').albumArt]);
        out("fail", [M.failure(127, "ring"), M.failure(69, "ring"), M.failure(1, "ring")]);
        Qt.quit();
    }
}
EOF
    qml_out="$(cd "$harness" && QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 "$QML_BIN" Harness.qml 2>&1 | sed -n 's/^.*RESULT //p')"
    r() { sed -n "s/^$1 //p" <<<"$qml_out"; }
    assert_eq "Model: devices once, a bad id dropped" '[["abc123","def456"],["192.0.2.7"],true]' "$(r scan)"
    assert_eq "Model: the phone" '["Connected","64% · Charging · 5G (3/4)","5G (3/4)",true,true,true,true]' "$(r phone)"
    assert_eq "Model: the tablet" '["Wants to pair","1A2B 3C4D",false,false]' "$(r tablet)"
    assert_eq "Model: which device to show" '["def456","abc123",""]' "$(r pick)"
    assert_eq "Model: literal addresses only" '["","Invalid IPv4 address","","","Enter a literal IPv4 or IPv6 address","Enter a literal IPv4 or IPv6 address","Enter a literal IPv4 or IPv6 address","Enter an IP address"]' "$(r addr)"
    assert_eq "Model: Tailscale peers, online first, IPv4 only" '[true,"192.0.2.2",["alpha@192.0.2.6","zed@192.0.2.5"],1,null]' "$(r ts)"
    assert_eq "Model: remote commands, JSON or lines" '[[{"key":"k1","name":"Lock"},{"key":"k2","name":"Mute"}],[{"key":"one","name":"First"},{"key":"two","name":"two"}],[]]' "$(r cmds)"
    assert_eq "Model: remote cover art is never loaded" '["",["Spotify"],"Song — Band",false,"file:///tmp/a.jpg"]' "$(r media)"
    assert_eq "Model: failure messages" '["KDE Connect is not installed","KDE Connect is not answering","The ring failed"]' "$(r fail)"
else
    echo "  skip: $QML_BIN not installed, Model.js not exercised" >&2
fi

# --- service, widget and panel in the real engine -------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null; then
    echo "  skip: qs or dbus-run-session missing; engine scenario not run" >&2
else
    : >"$LOG"
    stub notify-send "echo \"notify-send \$*\" >>'$LOG'"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons plugins; do
        ln -s "$SHELL_DIR/$module" "$harness/$module"
    done
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.omaconnect" as O
ShellRoot {
    id: shell

    property var first: null
    property bool showPanel: false

    O.Service {
        id: svc

        pluginId: "haseen.omaconnect"
        settings: ({ debugIpc: true, defaultPingMessage: "hello" })
    }

    O.Widget {
        id: widget

        pluginId: "haseen.omaconnect"
        service: svc
        settings: ({ showBarBattery: true })
    }

    Loader {
        active: shell.showPanel
        sourceComponent: O.Panel {
            pluginId: "haseen.omaconnect"
            service: svc
        }
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            shell.first = { discovery: svc.discovery, selected: svc.selectedId, incoming: svc.incoming ? svc.incoming.id : "", text: widget.text, addresses: svc.addresses };
            shell.showPanel = true;
            svc.ring();
            shell.first.refused = svc.sendClipboard();
            step2.running = true;
        }
    }

    Timer {
        id: step2

        interval: 1500
        onTriggered: {
            shell.first.ringMessage = svc.message;
            shell.first.panels = svc.panelsOpen;
            svc.ping("");
            step3.running = true;
        }
    }

    Timer {
        id: step3

        interval: 1500
        onTriggered: {
            shell.first.media = svc.media.title;
            svc.select("def456");
            shell.first.offline = svc.shareText("x");
            shell.first.offlineError = svc.error;
            svc.answer("def456", true);
            step4.running = true;
        }
    }

    Timer {
        id: step4

        interval: 1500
        onTriggered: {
            shell.first.badAddress = svc.saveAddress("1.2.3.999", false);
            console.warn("RESULT " + JSON.stringify(shell.first));
            Qt.quit();
        }
    }
}
QML
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "engine: harness completes (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    assert_eq "engine: the daemon answered" '"ready"' "$(jq -c .discovery <<<"$RESULT")"
    assert_eq "engine: the reachable phone is selected" '"abc123"' "$(jq -c .selected <<<"$RESULT")"
    assert_eq "engine: the tablet's request is seen" '"def456"' "$(jq -c .incoming <<<"$RESULT")"
    assert_eq "engine: the bar shows the battery" '"64%"' "$(jq -c .text <<<"$RESULT")"
    assert_eq "engine: one action at a time" false "$(jq .refused <<<"$RESULT")"
    assert_eq "engine: the ring went through" '"Ringing"' "$(jq -c .ringMessage <<<"$RESULT")"
    assert_eq "engine: the open panel counts itself" 1 "$(jq .panels <<<"$RESULT")"
    assert_eq "engine: the panel read the phone's player" '"Song"' "$(jq -c .media <<<"$RESULT")"
    assert_eq "engine: an unpaired device takes no action" false "$(jq .offline <<<"$RESULT")"
    assert_eq "engine: and says why" '"The device must be paired and reachable"' "$(jq -c .offlineError <<<"$RESULT")"
    assert_eq "engine: a bad address is refused before any call" false "$(jq .badAddress <<<"$RESULT")"
    assert_eq "engine: the device calls, in order" "kdeconnect-cli -d abc123 --ring
kdeconnect-cli -d abc123 --ping-msg hello" "$(grep '^kdeconnect-cli' "$LOG")"
    assert_contains "engine: the pairing answer went through haseen kdeconnect" "$(cat "$LOG")" "devices/def456 --method org.kde.kdeconnect.device.acceptPairing"
    assert_contains "engine: a request while no panel was open is one notification" "$(grep -c 'notify-send' "$LOG")" "1"
    assert_contains "engine: naming the device" "$(grep 'notify-send' "$LOG")" "Tab S9 wants to pair"
    assert_eq "engine: dbus-monitor watches only the KDE Connect daemon" "dbus-monitor --session type='signal',sender='org.kde.kdeconnect'" "$(grep '^dbus-monitor' "$LOG" | head -1)"
fi
