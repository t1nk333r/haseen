# shellcheck shell=bash
# haseen.audio panel: the manifest declares the panel, and the pure list
# shaping and labels in Model.js (outputs, inputs, per-app streams) run
# headless under the real Qt JS engine (/usr/lib/qt6/bin/qml, offscreen).

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.audio"

sandbox audio-panel
capture haseen plugin validate haseen.audio
assert_status "audio validates" 0 "$STATUS"
assert_contains "audio ok" "$OUTPUT" "ok: haseen.audio (builtin:"
assert_eq "audio is a bar widget with a panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "panel entry" "Panel.qml" "$(jq -r '.entry.panel' "$PLUGIN/manifest.json")"
assert_eq "debug hook off by default" "false" "$(jq -r '.settings.debugIpc.default' "$PLUGIN/manifest.json")"

QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Model.js" as A

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

    function node(name, flags, props) {
        return Object.assign({ name: name, description: "", nickname: "", isSink: false, isStream: false, audio: null, type: "", ready: true, properties: props || {} }, flags);
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
        const vol = { volume: 0.5, muted: false };
        const speaker = node("alsa_output.speaker", { isSink: true, audio: vol, description: "Built-in Audio Speaker Output" });
        const hdmi = node("alsa_output.hdmi", { isSink: true, audio: vol, description: "HDMI / DisplayPort 1 Output" });
        const buds = node("bluez_output.buds", { isSink: true, audio: vol, nickname: "Pixel Buds" }, { "device.icon-name": "audio-headphones-bluetooth" });
        const mic = node("alsa_input.mic", { audio: vol, description: "sof-soundwire Microphones Input" });
        const monitor = node("alsa_output.speaker.monitor", { audio: vol, description: "Monitor of Speaker" });
        const firefox = node("firefox", { isStream: true, isSink: true, audio: vol }, { "application.name": "Firefox", "media.name": "A video" });
        const spotify = node("spotify", { isStream: true, isSink: true, audio: vol }, { "application.name": "spotify", "media.name": "Spotify" });
        const record = node("pw-record", { isStream: true, audio: vol, type: "Stream/Input/Audio" }, { "application.name": "pw-record" });
        const silent = node("no-audio", { isStream: true, isSink: true, audio: null });
        const all = [firefox, mic, speaker, record, hdmi, monitor, buds, spotify, silent, null];

        eq("outputs: hardware sinks only, by label", ["HDMI / DisplayPort 1", "Pixel Buds", "Speaker"], A.sinks(all).map(A.nodeLabel));
        eq("inputs: no streams, sinks or monitors", ["Microphone"], A.sources(all).map(A.nodeLabel));
        eq("apps: playback streams with audio, by label", ["Firefox", "Spotify"], A.streams(all).map(A.streamLabel));
        eq("capture streams are not apps", false, A.isPlaybackStream(record));
        eq("empty graph", [[], [], []], [A.sinks(null), A.sources(undefined), A.streams([])]);

        eq("label strips soundwire and Input", "Microphone", A.nodeLabel(mic));
        eq("nickname wins", "Pixel Buds", A.nodeLabel(buds));
        eq("unknown node", "Unknown", A.nodeLabel(null));
        eq("stream detail is the media", "A video", A.streamDetail(firefox));
        eq("stream detail hides a repeat of the label", "", A.streamDetail(spotify));

        eq("headphones glyph", "\u{F02CB}", A.sinkGlyph(buds));
        eq("hdmi glyph", "\u{F0379}", A.sinkGlyph(hdmi));
        eq("speaker glyph", "\u{F04C3}", A.sinkGlyph(speaker));
        eq("mic glyph", "\u{F036C}", A.sourceGlyph(mic));

        eq("muted name", "Muted", A.outputVolumeName(0.8, true));
        eq("zero", "Silenced", A.outputVolumeName(0, false));
        eq("half", "Steady groove", A.outputVolumeName(0.5, false));
        eq("full", "Concert hall", A.outputVolumeName(1, false));
        eq("clamp high", 1, A.clampVolume(1.4));
        eq("clamp junk", 0, A.clampVolume("x"));
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
    assert_eq "js unit count" "20" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi
