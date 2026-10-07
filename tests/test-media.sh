# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen.media panel (plan 078): the manifest (a panel kind, remote cover art
# off by default), the panel model in Media.js under the real Qt JS engine
# (player selection, time formatting, the art policy, which controls a
# player's capabilities show), and the panel itself in the real Quickshell
# engine against tools/fake-mpris.py players on a private session bus: the
# pick, the seek clock, every control reaching the player, the switcher,
# and a limited player's controls hidden.

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.media"
DEFAULT="$HASEEN_PATH/default/shell.json"

# --- manifest and defaults ---------------------------------------------------
sandbox media
capture haseen plugin validate haseen.media
assert_status "media validates" 0 "$STATUS"
assert_contains "media ok" "$OUTPUT" "ok: haseen.media (builtin:"
assert_eq "kinds: widget, panel" "bar-widget panel" "$(jq -r '.kinds | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "entries" "Widget.qml Panel.qml" "$(jq -r '[.entry["bar-widget"], .entry.panel] | join(" ")' "$PLUGIN/manifest.json")"
assert_eq "remote cover art is off by default" "false" "$(jq -r '.settings.remoteArt.default' "$PLUGIN/manifest.json")"
assert_eq "the manifest declares the optional fetch" "true" "$(jq '.permissions | index("network") != null' "$PLUGIN/manifest.json")"
assert_eq "default shell.json keeps the media label in the bar" "true" "$(jq '.bar.center | index("haseen.media") != null' "$DEFAULT")"
assert_eq "default shell.json does not turn remote art on" "null" "$(jq '.plugins["haseen.media"].settings.remoteArt' "$DEFAULT")"

# --- the panel model under the real Qt JS engine ------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$PLUGIN/Media.js" as M

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
        // player selection
        const ps = [
            { dbusName: "org.mpris.MediaPlayer2.a", isPlaying: false, stopped: true },
            { dbusName: "org.mpris.MediaPlayer2.b", isPlaying: false, stopped: false },
            { dbusName: "org.mpris.MediaPlayer2.c", isPlaying: true, stopped: false }
        ];
        eq("select: the playing player by default", 2, M.selectIndex(ps, ""));
        eq("select: a paused one before a stopped one", 1, M.selectIndex(ps.slice(0, 2), ""));
        eq("select: the switcher's pick wins", 0, M.selectIndex(ps, "org.mpris.MediaPlayer2.a"));
        eq("select: a pick that left falls back", 2, M.selectIndex(ps, "org.mpris.MediaPlayer2.gone"));
        eq("select: no players", -1, M.selectIndex([], "org.mpris.MediaPlayer2.a"));
        eq("select: null list", -1, M.selectIndex(null, ""));

        // time formatting
        eq("time: m:ss", ["0:00", "0:09", "1:01", "59:59"], [0, 9.9, 61, 3599].map(M.formatTime));
        eq("time: h:mm:ss from an hour", ["1:00:00", "2:03:04"], [3600, 7384].map(M.formatTime));
        eq("time: junk is 0:00", ["0:00", "0:00", "0:00", "0:00"], [NaN, -5, undefined, "x"].map(M.formatTime));
        eq("fraction", [0.25, 1, 0, 0, 0], [M.fraction(50, 200), M.fraction(300, 200), M.fraction(10, 0), M.fraction(-1, 10), M.fraction(NaN, 10)]);

        // cover art (plan 010's remote-image rule)
        eq("art: file URL", "file:///tmp/a.png", M.artSource("file:///tmp/a.png", false));
        eq("art: bare path", "file:///tmp/a.png", M.artSource("/tmp/a.png", false));
        eq("art: inline data image", "data:image/png;base64,AA==", M.artSource("data:image/png;base64,AA==", false));
        eq("art: https is off by default", "", M.artSource("https://i.example/a.jpg", undefined));
        eq("art: https with remoteArt", "https://i.example/a.jpg", M.artSource("https://i.example/a.jpg", true));
        eq("art: remoteArt needs a real true", "", M.artSource("https://i.example/a.jpg", "true"));
        eq("art: plain http never", "", M.artSource("http://i.example/a.jpg", true));
        eq("art: other schemes never", ["", "", "", ""],
           ["ftp://x/a.jpg", "javascript:alert(1)", "data:text/html,x", ""].map(u => M.artSource(u, true)));

        // capabilities -> controls
        const full = { canControl: true, canGoPrevious: true, canGoNext: true, canTogglePlaying: true, canSeek: true,
                       lengthSupported: true, positionSupported: true, length: 200, shuffleSupported: true,
                       loopSupported: true, volumeSupported: true };
        eq("controls: a full player shows everything",
           { previous: true, playPause: true, next: true, seek: true, time: true, shuffle: true, loop: true, volume: true },
           M.controls(full));
        eq("controls: no player hides everything",
           { previous: false, playPause: false, next: false, seek: false, time: false, shuffle: false, loop: false, volume: false },
           M.controls(null));
        eq("controls: no shuffle, repeat or volume property hides them",
           [false, false, false], (c => [c.shuffle, c.loop, c.volume])(M.controls(Object.assign({}, full, { shuffleSupported: false, loopSupported: false, volumeSupported: false }))));
        eq("controls: CanControl false hides the writes",
           [false, false, false], (c => [c.shuffle, c.loop, c.volume])(M.controls(Object.assign({}, full, { canControl: false }))));
        eq("controls: CanSeek false keeps the time, not the drag",
           [true, false], (c => [c.time, c.seek])(M.controls(Object.assign({}, full, { canSeek: false }))));
        eq("controls: no length hides the bar",
           [false, false], (c => [c.time, c.seek])(M.controls(Object.assign({}, full, { length: 0 }))));
        eq("controls: no position hides the bar",
           [false, false], (c => [c.time, c.seek])(M.controls(Object.assign({}, full, { positionSupported: false }))));
        eq("controls: transport follows its own flags",
           [false, true, false], (c => [c.previous, c.playPause, c.next])(M.controls(Object.assign({}, full, { canGoPrevious: false, canGoNext: false }))));

        // repeat, volume, switcher
        eq("loop cycle: none, playlist, track, none", [2, 1, 0], [0, 2, 1].map(M.nextLoop));
        eq("loop glyphs", ["\u{F0457}", "\u{F0458}", "\u{F0456}"], [0, 1, 2].map(M.loopGlyph));
        eq("volume glyphs", ["\ueee8", "\uf026", "\uf027", "\uf028"], [0, 0.2, 0.5, 0.9].map(M.volumeGlyph));
        eq("switcher labels", ["Spotify", "mpv", "mpv 2", "Player"],
           M.playerLabels([{ identity: "Spotify", dbusName: "org.mpris.MediaPlayer2.spotify" },
                           { identity: "", dbusName: "org.mpris.MediaPlayer2.mpv" },
                           { identity: "mpv", dbusName: "org.mpris.MediaPlayer2.mpv.instance2" },
                           { identity: "", dbusName: "" }]));
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
    assert_eq "js unit count" "30" "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the fakes' private-bus guard (tools/fakebus.py) -------------------------------
# A sandbox socket stands in for the real bus: escaped, symlinked and listed
# spellings of it are refused before any connection (before: raw-string checks).
sandbox media-fakebus
real="$SANDBOX/run/bus"
python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$real"
ln -s "$real" "$SANDBOX/alias"
guard() { PYTHONPATH="$REPO/tools" python3 -c 'import fakebus, sys; print(fakebus.refusal(sys.argv[1], [sys.argv[2]]) is None)' "$1" "$real"; }
for bad in "unix:path=${real%bus}%62us" "unix:path=$SANDBOX/alias" "unix:path=$SANDBOX/run/../run/bus" \
    "unix:path=$SANDBOX/private;unix:path=$real" "unix:abstract=x" "tcp:host=localhost,port=1" "unix:runtime=yes" "unix:path=rel/bus" ""; do
    assert_eq "fakebus refuses '$bad'" "False" "$(guard "$bad")"
done
assert_eq "fakebus accepts a private socket" "True" "$(guard "unix:path=$SANDBOX/private,guid=0123")"
if python3 -c 'import dbus, gi' 2>/dev/null; then
    capture env DBUS_SESSION_BUS_ADDRESS="unix:path=$SANDBOX/run/%62us" timeout 10 python3 "$REPO/tools/fake-mpris.py" probe
    assert_status "fake-mpris refuses an escaped login-bus address" 1 "$STATUS"
    assert_contains "and says why" "$OUTPUT" "is a real bus"
fi

# --- the panel in the real engine against fake players --------------------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]] || ! command -v dbus-daemon >/dev/null || ! python3 -c 'import dbus, gi' 2>/dev/null; then
    echo "  skip: qs, dbus-daemon or python3-dbus missing; engine scenarios not run" >&2
else
    sandbox media-engine
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    # A 1x1 PNG as the player's local cover art.
    base64 -d >"$SANDBOX/art.png" <<<'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=='
    # The panel in a window, as the host shows it. Steps: read the first
    # state, press every control, read again, switch to the limited player,
    # read a third time.
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.media" as Media
ShellRoot {
    id: shellRoot

    property var states: []

    function snap(): var {
        const p = panel.player;
        return {
            players: panel.players.length,
            labels: panel.labels,
            player: p ? p.identity : null,
            title: panel.title,
            art: panel.art,
            controls: panel.controls,
            position: Math.round(panel.position),
            shuffle: p ? p.shuffle : null,
            loop: p ? p.loopState : null,
            volume: p ? Math.round(p.volume * 100) : null,
            playing: p ? p.isPlaying : null
        };
    }

    FloatingWindow {
        implicitWidth: 400
        implicitHeight: 500
        visible: true

        Media.Panel {
            id: panel
            pluginId: "haseen.media"
            settings: JSON.parse(Quickshell.env("MEDIA_SETTINGS"))
        }
    }

    Timer {
        interval: 2500
        running: true
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            panel.toggleShuffle();
            panel.cycleLoop();
            panel.setVolume(0.3);
            panel.seek(0.5);
            panel.player.next();
            panel.player.togglePlaying();
            later.start();
        }
    }

    Timer {
        id: later
        interval: 1500
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            panel.choose(panel.labels.indexOf("Radio"));
            last.start();
        }
    }

    Timer {
        id: last
        interval: 800
        onTriggered: {
            shellRoot.states.push(shellRoot.snap());
            // A limited player ignores what it does not offer.
            panel.toggleShuffle();
            panel.setVolume(0.1);
            panel.seek(0.9);
            console.warn("RESULT " + JSON.stringify(shellRoot.states));
            quitter.start();
        }
    }

    Timer {
        id: quitter
        interval: 500
        onTriggered: Qt.quit()
    }
}
QML
    bus="$(mktemp -d "${TMPDIR:-/tmp}/haseen-media.XXXXXX")"
    dbus-daemon --config-file="$REPO/tools/smoke-session.conf" --fork \
        --address="unix:path=$bus/session" --print-pid=3 3>"$bus/pid"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$bus/session"
    timeout 60 python3 "$REPO/tools/fake-mpris.py" spotify Identity=Spotify title="Song One" artist=Someone \
        album=Somewhere art="file://$SANDBOX/art.png" length=200 Position=61 PlaybackStatus=Playing \
        Volume=0.8 </dev/null >"$SANDBOX/full.log" 2>&1 &
    full=$!
    timeout 60 python3 "$REPO/tools/fake-mpris.py" radio Identity=Radio title="Live" PlaybackStatus=Paused \
        CanSeek=false length=0 art=https://art.example/cover.jpg omit=Shuffle,LoopStatus,Volume \
        </dev/null >"$SANDBOX/radio.log" 2>&1 &
    radio=$!
    for _ in $(seq 50); do grep -q ready "$SANDBOX/full.log" && grep -q ready "$SANDBOX/radio.log" && break; sleep 0.1; done
    capture env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        MEDIA_SETTINGS='{}' timeout 60 "$QS_BIN" -p "$harness"
    kill "$full" "$radio" 2>/dev/null || true
    wait "$full" "$radio" 2>/dev/null || true
    kill "$(cat "$bus/pid")" 2>/dev/null || true
    rm -rf "$bus"
    export DBUS_SESSION_BUS_ADDRESS=unix:path=/nonexistent
    assert_status "the panel harness completes in the real engine" 0 "$STATUS"
    RESULT="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT" | head -1)"
    FULL="$(cat "$SANDBOX/full.log")"
    RADIO="$(cat "$SANDBOX/radio.log")"
    s() { jq -c ".[$1]$2" <<<"$RESULT"; }

    # First look: the playing player, its local art, everything it offers.
    assert_eq "two players, two pills" '["Spotify","Radio"]' "$(jq -c '.[0].labels | sort_by(. != "Spotify")' <<<"$RESULT")"
    assert_eq "the playing player is shown" '"Spotify"' "$(s 0 .player)"
    assert_eq "its title" '"Song One"' "$(s 0 .title)"
    assert_eq "its local art shows" "\"file://$SANDBOX/art.png\"" "$(s 0 .art)"
    assert_eq "a full player shows every control" \
        '{"previous":true,"playPause":true,"next":true,"seek":true,"time":true,"shuffle":true,"loop":true,"volume":true}' \
        "$(s 0 .controls)"
    pos="$(s 0 .position)"
    if ((pos >= 62 && pos <= 66)); then _pass; else _fail "the seek clock ticks while playing (61 s at start, 2.5 s later: $pos)"; fi

    # Every control reaches the player.
    assert_contains "shuffle writes Shuffle" "$FULL" "set Shuffle=true"
    assert_contains "repeat writes LoopStatus None -> Playlist" "$FULL" "set LoopStatus=Playlist"
    assert_contains "the volume bar writes Volume" "$FULL" "set Volume=0.3"
    assert_contains "seeking to half way sets the position" "$FULL" "call SetPosition /org/haseen/fake/track/1 100000000"
    assert_contains "next" "$FULL" "call Next"
    assert_contains "play/pause pauses the playing player" "$FULL" "call Pause"
    assert_eq "the panel follows the player back" '[true,2,30,false]' "$(jq -c '.[1] | [.shuffle, .loop, .volume, .playing]' <<<"$RESULT")"
    assert_eq "the seek landed (paused at 100 s)" "100" "$(s 1 .position)"

    # The switcher: the limited player hides what it lacks.
    assert_eq "the switcher shows the picked player" '"Radio"' "$(s 2 .player)"
    assert_eq "remote art stays off by default" '""' "$(s 2 .art)"
    assert_eq "a limited player hides shuffle, repeat, volume and the seek bar" \
        '{"previous":true,"playPause":true,"next":true,"seek":false,"time":false,"shuffle":false,"loop":false,"volume":false}' \
        "$(s 2 .controls)"
    assert_not_contains "nothing hidden reaches the limited player" "$RADIO" "fake-mpris: set"
    assert_not_contains "no seek reaches the limited player" "$RADIO" "SetPosition"
fi
