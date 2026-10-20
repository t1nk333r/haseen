#!/usr/bin/env bash
# A fake gdbus for tests/test-omaconnect.sh: answers KDE Connect's D-Bus calls
# the way gdbus prints them, for two devices: abc123 (a paired, reachable
# phone with every plugin) and def456 (an unpaired tablet asking to pair).
# Every call is logged to $FAKE_LOG; $FAKE_DAEMON_OFF makes the daemon absent.
echo "gdbus $*" >>"${FAKE_LOG:-/dev/null}"
args="$*"
if [[ -n ${FAKE_DAEMON_OFF:-} ]]; then
    [[ $args == *NameHasOwner* ]] && { echo '(false,)'; exit 0; }
    exit 1
fi
case "$args" in
*NameHasOwner*) echo '(true,)' ;;
*daemon.devices*) echo "(['abc123', 'def456'],)" ;;
*customDevices*) echo "(<['192.0.2.7']>,)" ;;
*"devices/abc123 "*"device name"*) echo "(<'Pixel 9'>,)" ;;
*"devices/abc123 "*"device type"*) echo "(<'phone'>,)" ;;
*"devices/abc123 "*isPaired*) echo "(<true>,)" ;;
*"devices/abc123 "*isReachable*) echo "(<true>,)" ;;
*"devices/abc123 "*isPairRequestedByPeer*) echo "(<false>,)" ;;
*"devices/abc123 "*isPairRequested*) echo "(<false>,)" ;;
*"devices/abc123 "*verificationKey*) echo "(<''>,)" ;;
*"devices/abc123 "*supportedPlugins*) echo "(<['kdeconnect_battery', 'kdeconnect_ping', 'kdeconnect_share', 'kdeconnect_findmyphone', 'kdeconnect_clipboard', 'kdeconnect_mprisremote', 'kdeconnect_runcommand', 'kdeconnect_connectivity_report', 'kdeconnect_sms']>,)" ;;
*"abc123/battery "*charge*) echo "(<64>,)" ;;
*"abc123/battery "*isCharging*) echo "(<true>,)" ;;
*cellularNetworkType*) echo "(<'5G'>,)" ;;
*cellularNetworkStrength*) echo "(<3>,)" ;;
*"mprisremote "*isPlaying*) echo "(<true>,)" ;;
*"mprisremote "*" title"*) echo "(<'Song'>,)" ;;
*"mprisremote "*artist*) echo "(<'Band'>,)" ;;
*"mprisremote "*playerList*) echo "(<['Spotify', 'YT Music']>,)" ;;
*"mprisremote "*" player"*) echo "(<'Spotify'>,)" ;;
*"mprisremote "*localAlbumArtUrl*) echo "(<'https://example.test/cover.jpg'>,)" ;;
*"mprisremote "*) echo "(<''>,)" ;;
*"devices/def456 "*"device name"*) echo "(<'Tab S9'>,)" ;;
*"devices/def456 "*"device type"*) echo "(<'tablet'>,)" ;;
*"devices/def456 "*isPaired*) echo "(<false>,)" ;;
*"devices/def456 "*isReachable*) echo "(<true>,)" ;;
*"devices/def456 "*isPairRequestedByPeer*) echo "(<true>,)" ;;
*"devices/def456 "*isPairRequested*) echo "(<false>,)" ;;
*"devices/def456 "*verificationKey*) echo "(<'1A2B3C4D'>,)" ;;
*"devices/def456 "*supportedPlugins*) echo "(<['kdeconnect_ping']>,)" ;;
*acceptPairing* | *cancelPairing* | *sendAction* | *requestPlayerList* | *Properties.Set*) echo '()' ;;
*) echo "unhandled: $args" >&2; exit 1 ;;
esac
