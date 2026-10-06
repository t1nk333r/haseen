# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.network panel (port of Omarchy's): the manifest declares the panel,
# the pure helpers in Model.js (icons, details, ping and traffic, band, row
# order, sections and status, credentials, failure reasons, DNS names) run
# headless under the real Qt JS engine (/usr/lib/qt6/bin/qml, offscreen), and
# the two commands the panel samples read stubbed ip/iw/ping/nmcli and a
# fixture /sys. Nothing here touches the machine's network.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.network"

sandbox network-panel
capture haseen plugin validate haseen.network
assert_status "network validates" 0 "$STATUS"
assert_contains "network ok" "$OUTPUT" "ok: haseen.network (builtin:"
assert_eq "network is a bar widget with a panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "panel entry" "Panel.qml" "$(jq -r '.entry.panel' "$PLUGIN/manifest.json")"
assert_eq "settings kept" "debugIpc maxNetworks showName" "$(jq -r '.settings | keys | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "debug hook off by default" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGIN/manifest.json")"
# The panel runs commands and pings 1.1.1.1 while open.
assert_eq "declares exec and network" "exec network" "$(jq -r '.permissions | join(" ")' "$PLUGIN/manifest.json")"

QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as N

Window {
    property int failures: 0

    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }

    function net(name, signal, flags) {
        return Object.assign({ name: name, signalStrength: signal, connected: false, known: false, security: 2 }, flags);
    }

    Component.onCompleted: {
        try {
            run();
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }

    function run() {
        eq("weak wifi", "\u{F092F}", N.wifiIconFor(5));
        eq("full wifi", "\u{F0928}", N.wifiIconFor(100));
        eq("wired wins over wifi", "ethernet", N.connectionKind(true, true));
        eq("wifi only", "wifi", N.connectionKind(false, true));
        eq("ethernet glyph", "\u{F0200}", N.connectionIcon("ethernet", -1));
        eq("disconnected glyph", "\u{F092E}", N.connectionIcon("disconnected", -1));

        eq("ethernet detail is link speed", "2.5gbit", N.headerDetail({ type: "ethernet", speed: "2500" }));
        eq("wifi has no header detail", "", N.headerDetail({ type: "wifi", speed: "1000" }));
        eq("unknown speed", "", N.formatHeaderSpeed("-1"));
        eq("hero title wifi", "Cafe", N.heroTitle({ type: "wifi", ssid: "Cafe" }, "wifi"));
        eq("hero title without route", "Disconnected", N.heroTitle({}, "disconnected"));
        eq("hero meta connected", "BENDING LIGHT", N.heroMeta({ type: "ethernet" }, "ethernet", false, "Bending light"));
        eq("hero meta offline", "NOT CONNECTED", N.heroMeta({}, "disconnected", false, "x"));

        const kv = N.parseKeyValue("iface\twlan0\nssid\tCaf\\\\xc3\\\\xa9 \\\\x01\nnoise\n\tlead\nrx_bytes\t 42 \n");
        eq("key/value lines", { iface: "wlan0", ssid: "Café \\\\x01", rx_bytes: "42" }, kv);
        eq("band status", { band: "5", selected: "auto", available: ["2.4", "5"] }, N.parseBandStatus("band\t5\navailable\t2.4 5\nselected\tauto\n"));
        eq("band status empty", { band: "", selected: "auto", available: [] }, N.parseBandStatus(""));
        eq("band title under auto names the live band", "WI-FI BAND: 5GHZ", N.bandSectionTitle("auto", "5"));
        eq("band title when pinned", "WI-FI BAND", N.bandSectionTitle("2.4", "2.4"));
        eq("band hint", "Stay on 6ghz", N.bandTooltip("6"));

        const first = N.throughputState({}, { iface: "wlan0", rx_bytes: "1000", tx_bytes: "500" }, 10);
        eq("first sample primes, no spike", [0, 0], [first.downloadRate, first.uploadRate]);
        const second = N.throughputState(first, { iface: "wlan0", rx_bytes: "5000", tx_bytes: "900" }, 12);
        eq("rates from deltas", [2000, 200], [second.downloadRate, second.uploadRate]);
        eq("interface switch resets", 0, N.throughputState(second, { iface: "eth0", rx_bytes: "9e9" }, 14).downloadRate);

        let ping = N.pingLatencyState({}, { iface: "wlan0", internet_ping_ms: "20" }, 24, 5);
        ping = N.pingLatencyState(ping, { iface: "wlan0", internet_ping_ms: "" }, 24, 5);
        ping = N.pingLatencyState(ping, { iface: "wlan0", internet_ping_ms: "30" }, 24, 5);
        eq("ping averages answered probes", 25, ping.internetPingLatency);
        eq("timeouts count as loss", 33, ping.internetPingPacketLoss);
        eq("new interface drops old samples", 1, N.pingLatencyState(ping, { iface: "eth0", internet_ping_ms: "5" }, 24, 5).internetPingSamples.length);
        eq("ping before any sample", "--", N.formatPingLatency(-1, false));
        eq("ping timeout", "Timeout", N.formatPingLatency(-1, true));
        eq("ping small", "4.2 ms", N.formatPingLatency(4.2, true));
        eq("loss", "33%", N.formatPacketLoss(33, true));
        eq("bytes", ["512 B", "1.5 KB", "2.0 MB/s"], [N.formatBytes(512), N.formatBytes(1536), N.formatRate(2 * 1024 * 1024)]);

        const all = [net("Weak", 0.2), net("", 0.9), net("Home", 0.4, { known: true }), net("Strong", 0.8), net("Now", 0.3, { connected: true, known: true }), null];
        const rows = N.wifiRows(all, 8);
        eq("rows: connected, saved, then signal; hidden dropped", ["Now", "Home", "Strong", "Weak"], rows.map(r => r.ssid));
        eq("rows are primitives", { connected: false, known: false, ssid: "Strong", signal: 80, security: 2 }, rows[2]);
        eq("rows capped", ["Now", "Home"], N.wifiRows(all, 2).map(r => r.ssid));
        eq("rows from a QML sequence (array-like)", ["Now", "Home"], N.wifiRows({ length: 2, 0: all[2], 1: all[4] }, 8).map(r => r.ssid));
        eq("section titles", ["KNOWN NETWORKS", "", "OTHER NETWORKS", ""], rows.map((r, i) => N.wifiSectionTitle(rows, i)));
        eq("no saved networks", "OTHER NETWORKS", N.wifiSectionTitle([rows[2]], 0));

        eq("open needs no credentials", false, N.requiresCredentials(0, 0, 9));
        eq("owe needs no credentials", false, N.requiresCredentials(9, 0, 9));
        eq("unknown security asks", true, N.requiresCredentials(undefined, 0, 9));
        eq("forget only saved, not connected", [false, true, false], [N.canForgetNetwork(rows[0]), N.canForgetNetwork(rows[1]), N.canForgetNetwork(rows[2])]);
        eq("row actions", ["disconnect", "connect", "prompt", "connect"], [N.rowAction(rows[0], true), N.rowAction(rows[1], true), N.rowAction(rows[2], true), N.rowAction(rows[3], false)]);

        const idle = { kind: "", ssid: "" }, ok = { reason: "", ssid: "" };
        eq("status connected", "Connected", N.rowStatus(rows[0], idle, ok, false));
        eq("status connecting", "Connecting…", N.rowStatus(rows[2], { kind: "connect", ssid: "Strong" }, ok, false));
        eq("status forgetting", "Forgetting…", N.rowStatus(rows[1], { kind: "forget", ssid: "Home" }, ok, false));
        eq("status failure", "Wrong password", N.rowStatus(rows[2], idle, { reason: "Wrong password", ssid: "Strong" }, false));
        eq("status hidden under the prompt", "", N.rowStatus(rows[2], { kind: "connect", ssid: "Strong" }, ok, true));
        eq("other rows unaffected", "", N.rowStatus(rows[3], { kind: "connect", ssid: "Strong" }, ok, false));

        const R = { NoSecrets: 1, WifiAuthTimeout: 2, WifiNetworkLost: 3, WifiClientDisconnected: 4, WifiClientFailed: 5 };
        eq("failure reasons", ["Passphrase required", "Wrong password", "Network lost", "Failed to connect"], [N.networkFailureReason(1, true, R), N.networkFailureReason(2, true, R), N.networkFailureReason(3, true, R), N.networkFailureReason(2, false, R)]);
        eq("reprompt on wrong password only when secured", [true, true, false, false], [N.shouldRepromptPassphrase(1, true, R), N.shouldRepromptPassphrase(2, true, R), N.shouldRepromptPassphrase(2, false, R), N.shouldRepromptPassphrase(3, true, R)]);
        eq("enterprise secret never in argv", true, N.enterpriseConnectScript.indexOf("read -r pw") >= 0 && N.enterpriseConnectScript.indexOf("802-1x.password \"") < 0);

        eq("dns names", ["dhcp", "cloudflare", "google", "custom"], N.dnsProviders.map(p => p.id));
        eq("dns choice", ["google", "dhcp", "dhcp"], [N.dnsChoice("google\n"), N.dnsChoice(""), N.dnsChoice("quad9")]);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "qml unit runner exits 0" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" "52" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- haseen network status: the active route's details ------------------------
sandbox network-status
root="$SANDBOX/root"
mkdir -p "$root/sys/class/net/wlan0/statistics" "$root/sys/class/net/wlan0/wireless" "$root/sys/class/net/eth0/statistics"
echo 1000 >"$root/sys/class/net/wlan0/statistics/rx_bytes"
echo 2000 >"$root/sys/class/net/wlan0/statistics/tx_bytes"
echo 7 >"$root/sys/class/net/eth0/statistics/rx_bytes"
echo 2500 >"$root/sys/class/net/eth0/speed"
echo full >"$root/sys/class/net/eth0/duplex"
stub ip 'case "$*" in
"-j route get 1.1.1.1") [ -n "$ROUTE_DEV" ] && echo "[{\"dst\":\"1.1.1.1\",\"gateway\":\"192.0.2.1\",\"dev\":\"$ROUTE_DEV\",\"prefsrc\":\"192.0.2.10\"}]" ;;
"-j addr show "*) echo "[{\"addr_info\":[{\"family\":\"inet6\",\"prefixlen\":64},{\"family\":\"inet\",\"prefixlen\":24}]}]" ;;
esac'
stub iw 'printf "Connected to 02:00:00:00:00:01 (on wlan0)\n\tSSID: Cafe: Net\n\tfreq: 5180.0\n\tsignal: -48 dBm\n\ttx bitrate: 866.7 MBit/s VHT-MCS 9\n"'
stub ping '[ -n "$PING_DOWN" ] && exit 1; echo "64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms"'

capture env HASEEN_SYSROOT="$root" ROUTE_DEV=wlan0 haseen-network-status
assert_status "status on wifi" 0 "$STATUS"
assert_eq "wifi details" "iface	wlan0
ip	192.0.2.10
prefix	24
gateway	192.0.2.1
rx_bytes	1000
tx_bytes	2000
type	wifi
ssid	Cafe: Net
signal_dbm	-48
freq	5180.0
bitrate	866.7 MBit/s
internet_ping_ms	12.3" "$OUTPUT"
capture env HASEEN_SYSROOT="$root" ROUTE_DEV=eth0 PING_DOWN=1 haseen-network-status
assert_contains "ethernet type" "$OUTPUT" $'type\tethernet\nspeed\t2500\nduplex\tfull'
assert_contains "ping timeout reads empty" "$OUTPUT" $'internet_ping_ms\t'
assert_not_contains "no ssid on ethernet" "$OUTPUT" "ssid"
capture env HASEEN_SYSROOT="$root" ROUTE_DEV= haseen-network-status
assert_status "no route is not an error" 0 "$STATUS"
assert_eq "no route prints nothing" "" "$OUTPUT"
capture haseen-network-status extra
assert_status "status takes no arguments" 2 "$STATUS"

# --- haseen network band: status, pin, refusal ---------------------------------
sandbox network-band
stub iw 'printf "Connected to 02:00:00:00:00:01 (on wlan0)\n\tSSID: Cafe: Net\n\tfreq: 2437.0\n"'
stub nmcli 'case "$*" in
"-e no -g DEVICE,TYPE,STATE device status") printf "lo:loopback:connected (externally)\nwlan0:wifi:connected\n" ;;
"-e no -g GENERAL.CONNECTION device show wlan0") echo "Cafe profile" ;;
"-e no -g FREQ,SSID dev wifi list ifname wlan0 --rescan no") printf "5180 MHz:Cafe: Net\n2437 MHz:Cafe: Net\n5955 MHz:Cafe: Nett\n5745 MHz:Other\n" ;;
"-e no -g 802-11-wireless.band connection show Cafe profile") echo "${PINNED:-}" ;;
*) echo "STUB-CALLED: nmcli $*" >&2; exit 97 ;;
esac'

capture haseen-network-band
assert_status "band status" 0 "$STATUS"
assert_eq "bands of this SSID only, low to high" $'band\t2.4\navailable\t2.4 5\nselected\tauto' "$OUTPUT"
capture env PINNED=a haseen-network-band
assert_contains "pinned band read back" "$OUTPUT" $'selected\t5'

capture haseen-network-band 5 --dry-run
assert_status "pin dry-run" 0 "$STATUS"
assert_contains "pin modifies the active profile" "$OUTPUT" "DRYRUN: nmcli connection modify Cafe profile 802-11-wireless.band a"
assert_contains "pin reconnects" "$OUTPUT" "DRYRUN: nmcli connection up Cafe profile"
assert_dry_pure "band pin" "$OUTPUT"
capture env PINNED=a haseen-network-band auto --dry-run
assert_contains "auto clears the pin" "$OUTPUT" "DRYRUN: nmcli connection modify Cafe profile 802-11-wireless.band "
capture haseen-network-band auto --dry-run
assert_contains "auto when already automatic is a no-op" "$OUTPUT" "already auto"
assert_dry_pure "band no-op" "$OUTPUT"
capture haseen-network-band 6 --dry-run
assert_status "unavailable band refused" 1 "$STATUS"
assert_contains "refusal names the band" "$OUTPUT" "6 GHz is not available"
capture haseen-network-band 7
assert_status "unknown band is a usage error" 2 "$STATUS"
stub nmcli 'exit 0'
capture haseen-network-band
assert_eq "no Wi-Fi connected prints nothing" "" "$OUTPUT"
capture haseen-network-band 5 --dry-run
assert_status "pin without Wi-Fi fails" 1 "$STATUS"
