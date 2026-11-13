# shellcheck shell=bash
# haseen:covers bin/haseen-sidecar core/sidecar/** tools/sidecar-play.py
# haseen:covers share/haseen/VERSION share/haseen/shell/Haseen/Sidecar.qml
# haseen:covers share/haseen/shell/Haseen/qmldir share/haseen/themes/haseen/colors.toml
# haseen:covers tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen-sidecar (Rust, core/sidecar/, plan 167): its own tests, its answers
# against the Go daemon's it replaced (core/sidecar/tests/golden/, recorded
# from the Go daemon over the same fixtures before it was removed), the wire
# protocol over a real socket, and the CLI around it. Everything here needs
# the built daemon; without cargo the whole file skips, which is the same
# state a machine without it and without the release is in. Under
# HASEEN_REQUIRE_ENGINE=1 (CI) a missing tool fails instead.
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
sandbox sidecar
[[ ! -d $rustup_home ]] || export RUSTUP_HOME="$rustup_home"
CRATE="$REPO/core/sidecar"
GOLDEN="$CRATE/tests/golden"

required() { # TOOL WHAT — a missing prerequisite: a skip, or a failure in CI
    echo "  skip: $1 missing; $2" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "sidecar: required $1 prerequisite" available unavailable
}

# A rustup proxy with no toolchain is on PATH and does not run: no cargo.
if ! command -v cargo >/dev/null || ! cargo --version >/dev/null 2>&1; then
    required cargo "haseen-sidecar not built or tested"
    return 0 2>/dev/null || exit 0
fi

# A private cargo home and target dir under tests/.out (ignored), kept between
# runs: the crate's one dependency, libc, is fetched once. build-sidecar.sh
# reads CARGO_TARGET_DIR too, so it reuses the same build.
export CARGO_HOME="$OUT/cargo-home" CARGO_TARGET_DIR="$OUT/sidecar-target"
VERSION="$(cat "$HASEEN_PATH/VERSION")"

capture env HASEEN_VERSION="$VERSION" cargo test --locked --quiet --manifest-path "$CRATE/Cargo.toml"
assert_status "cargo test --locked passes" 0 "$STATUS"
assert_not_contains "no failed Rust test" "$OUTPUT" "FAILED"
assert_contains "the unit tests ran" "$OUTPUT" "test result: ok. 57 passed; 0 failed"
assert_contains "the protocol tests ran" "$OUTPUT" "test result: ok. 10 passed; 0 failed"
if cargo clippy --version >/dev/null 2>&1; then
    capture cargo clippy --locked --quiet --all-targets --manifest-path "$CRATE/Cargo.toml" -- -D warnings
    assert_status "clippy finds nothing" 0 "$STATUS"
fi
if cargo fmt --version >/dev/null 2>&1; then
    capture cargo fmt --check --manifest-path "$CRATE/Cargo.toml"
    assert_status "the crate is rustfmt-clean" 0 "$STATUS"
fi
assert_eq "the crate has one dependency" '["libc"]' \
    "$(sed -n '/^\[dependencies\]/,/^\[/p' "$CRATE/Cargo.toml" | sed -n 's/^\([a-z_-]*\) = .*/"\1"/p' | jq -sc .)"
assert_eq "and its lock file nothing else" "haseen-sidecar libc" \
    "$(sed -n 's/^name = "\(.*\)"/\1/p' "$CRATE/Cargo.lock" | LC_ALL=C sort | paste -sd' ')"

binary="$SANDBOX/haseen-sidecar"
# wootingd has its own file, tests/test-wootingd.sh, and the palette
# tests/test-wallpaper.sh.
capture env HASEEN_BUILD_WOOTINGD=0 HASEEN_BUILD_PALETTE=0 HASEEN_FETCH_SIDECAR=0 "$REPO/tools/build-sidecar.sh" "$binary"
assert_status "the daemon builds" 0 "$STATUS"
assert_contains "the build reports where it landed" "$OUTPUT" "$binary"

assert_eq "the build announces its capabilities" "sysusage borderwipe" "$("$binary" -capabilities)"

assert_eq "and the tree's version" "$VERSION" "$("$binary" -version)"
crate_files() { (cd "$CRATE" && find . -not -path "./src/*" -not -path "./tests/*" -not -path "./target" -not -path "./target/*" -not -name . | LC_ALL=C sort | paste -sd" "); }
assert_eq "no build output in the tracked crate" "./Cargo.lock ./Cargo.toml ./src ./tests" "$(crate_files)"

# --- the Go daemon's answers ------------------------------------------------------
# Each golden file is what the Go daemon wrote for the script beside it, over
# make_root's fixture, through tools/sidecar-play.py (which masks pids,
# versions, rates and sizes); the sandbox path reads SANDBOX. They were
# recorded by plan 167's phase 1 comparison, where both daemons ran side by
# side and every transcript was identical.
if ! command -v python3 >/dev/null || ! command -v jq >/dev/null; then
    required python3/jq "the daemon is not compared with the Go daemon's answers"
else
    case_dir="$SANDBOX/c"

# make_root — the fixture the daemon reads, written fresh before each case.
make_root() {
    rm -rf "$case_dir"
    local r="$case_dir/root" s="$case_dir/state"
    mkdir -p "$r/proc/net" "$r/proc/self" "$s/current/theme"
    printf 'cpu  100 0 100 700 100 0 0 0 0 0\ncpu0 1 2 3 4\n' >"$r/proc/stat"
    printf 'MemTotal:       32554964 kB\nMemFree:  1 kB\nMemAvailable:   18094064 kB\nSwapTotal:      1000 kB\nSwapFree:       250 kB\n' >"$r/proc/meminfo"
    printf 'Inter-|   Receive\n face |bytes\n  lo: 5 1 0 0 0 0 0 0 5 1 0 0 0 0 0 0\n  wlan0: 1000 10 0 0 0 0 0 0 100 10 0 0 0 0 0 0\n' >"$r/proc/net/dev"
    printf 'processor\t: 0\ncpu MHz\t\t: 1000.500\n' >"$r/proc/cpuinfo"
    # Two processes; one's name holds what Go escapes, and a parenthesis.
    mkdir -p "$r/proc/10" "$r/proc/11"
    printf '10 (quiet) R 1 1 1 0 -1 0 0 0 0 0 100 0 0 0 20 0 1 0 0 0 25\n' >"$r/proc/10/stat"
    printf '11 (a<b>&(c)) R 1 1 1 0 -1 0 0 0 0 0 100 0 0 0 20 0 1 0 0 0 50\n' >"$r/proc/11/stat"
    printf 'Uid:\t0\t0\t0\t0\n' >"$r/proc/10/status"
    printf 'Uid:\t0\t0\t0\t0\n' >"$r/proc/11/status"
    printf 'busy\0--flag\0' >"$r/proc/11/cmdline"
    # Cards: an AMD busy card, the boot VGA Intel freq card, an xe rc6 card,
    # and a connector that is not a card.
    local drm="$r/sys/class/drm"
    mkdir -p "$drm/card0/device" "$drm/card1/device" "$drm/card2/device/tile0/gt0/gtidle" "$drm/card1-eDP-1"
    printf 'DRIVER=amdgpu\nPCI_SLOT_NAME=0000:03:00.0\n' >"$drm/card0/device/uevent"
    printf '0\n' >"$drm/card0/device/boot_vga"
    printf '37\n' >"$drm/card0/device/gpu_busy_percent"
    printf 'DRIVER=i915\nPCI_SLOT_NAME=0000:00:02.0\n' >"$drm/card1/device/uevent"
    printf '1\n' >"$drm/card1/device/boot_vga"
    printf '350\n' >"$drm/card1/gt_act_freq_mhz"
    printf '1400\n' >"$drm/card1/gt_max_freq_mhz"
    printf 'DRIVER=xe\n' >"$drm/card2/device/uevent"
    printf '1000\n' >"$drm/card2/device/tile0/gt0/gtidle/idle_residency_ms"
    # An unlabelled k10temp, which wins over the thermal zone.
    mkdir -p "$r/sys/class/hwmon/hwmon0" "$r/sys/class/thermal/thermal_zone0"
    printf 'k10temp\n' >"$r/sys/class/hwmon/hwmon0/name"
    printf '45250\n' >"$r/sys/class/hwmon/hwmon0/temp1_input"
    printf 'x86_pkg_temp\n' >"$r/sys/class/thermal/thermal_zone0/type"
    printf '51000\n' >"$r/sys/class/thermal/thermal_zone0/temp"
    mkdir -p "$r/sys/devices/system/cpu/cpu0/cpufreq" "$r/sys/devices/system/cpu/cpu1/cpufreq"
    printf '2000000\n' >"$r/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq"
    printf '3000000\n' >"$r/sys/devices/system/cpu/cpu1/cpufreq/scaling_cur_freq"
    # Mounts: one device at two subvolumes, an escaped space, an image and
    # zram that are not disks, a pseudo filesystem, a mount that is gone.
    mkdir -p "$r/home" "$r/media/My Disk"
    printf '%s\n' 'proc /proc proc rw 0 0' \
        '/dev/mapper/root /home btrfs rw,subvol=/@home 0 0' \
        '/dev/mapper/root / btrfs rw,subvol=/@ 0 0' \
        '/dev/sdb1 /media/My\040Disk fuseblk rw 0 0' \
        '/dev/loop0 /snap/core/1 squashfs ro 0 0' \
        '/dev/zram0 /tmp ext4 rw 0 0' \
        '/dev/sdc1 /mnt/gone ext4 rw 0 0' >"$r/proc/self/mounts"
    cp "$HASEEN_PATH/themes/haseen/colors.toml" "$s/current/theme/colors.toml"
}


    # play NAME SCRIPT [rootless] — the daemon on its own socket over a fresh
    # fixture; leaves the masked transcript in $SANDBOX/NAME.
    play() {
        local name="$1" script="$2" root sock="$SANDBOX/play.sock" pid i
        make_root
        root="$case_dir/root"
        [[ ${3:-} != rootless ]] || root="$case_dir/empty"
        mkdir -p "$root"
        env -u HYPRLAND_INSTANCE_SIGNATURE "$binary" -socket "$sock" -idle-timeout 0 -root "$root" \
            -state "$case_dir/state" >"$SANDBOX/$name.log" 2>&1 &
        pid=$!
        for ((i = 0; i < 100; i++)); do
            [[ -S $sock ]] && break
            sleep 0.05
        done
        timeout 60 python3 "$REPO/tools/sidecar-play.py" "$sock" "$case_dir" "$script" 2>&1 |
            sed "s#$SANDBOX#SANDBOX#g" >"$SANDBOX/$name"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
    }

    same() { # LABEL NAME — the transcript is the Go daemon's, and real
        assert_contains "$1: the daemon answered" "$(head -1 "$SANDBOX/$2")" '{"type":"hello","protocol":1,'
        assert_eq "$1" "" "$(diff "$GOLDEN/$2.out" "$SANDBOX/$2" || true)"
        assert_not_contains "$1: nothing timed out" "$(cat "$SANDBOX/$2")" "TIMEOUT"
    }

    play protocol "$GOLDEN/protocol.script" rootless
    same "the protocol answers as the Go daemon's" protocol

    play sysusage "$GOLDEN/sysusage.script"
    same "every sample matches the Go daemon's" sysusage
    assert_contains "the comparison saw the escaped process name" "$(cat "$SANDBOX/sysusage")" '"command":"busy --flag"'
    assert_contains "and the btrfs root once, at its shortest mount" "$(cat "$SANDBOX/sysusage")" '"mount":"/","device":"/dev/mapper/root"'
    assert_contains "and an Intel card at half its clock" "$(cat "$SANDBOX/sysusage")" '"gpu":50,'

    play empty "$GOLDEN/sysusage.script" rootless
    same "an empty root is unknown, as in the Go daemon" empty

    play wipe "$GOLDEN/wipe.script"
    same "the border wipe's states match the Go daemon's" wipe
    assert_contains "the comparison saw the theme's pace" "$(cat "$SANDBOX/wipe")" '"state":"waiting","reason":"Hyprland is not answering","secondsPerTurn":36'
    assert_contains "and a colour refused" "$(cat "$SANDBOX/wipe")" '"reason":"colors.toml: border_wipe: a colour is not rgba(RRGGBBAA), rgb(RRGGBB) or 0xAARRGGBB"'
fi

# --- flags, stdout and exits, as the Go daemon's ----------------------------------
flags_of() { # BIN — what each invocation prints, the binary's path masked
    local bin="$1" args
    for args in "-capabilities" "--capabilities" "-capabilities=false -version" "-nonsense" \
        "-idle-timeout soon" "-socket" "-h" "---x" "-version=maybe"; do
        # shellcheck disable=SC2086 # the arguments are split on purpose
        capture "$bin" $args
        printf '== %s: %s\n%s\n' "$args" "$STATUS" "${OUTPUT//$bin/BIN}"
    done
    blocked="$SANDBOX/blocked"
    : >"$blocked"
    capture "$bin" -socket "$blocked/s.sock"
    printf '== blocked: %s\n%s\n' "$STATUS" "$(head -1 <<<"$OUTPUT")"
    local long
    long="$SANDBOX/$(printf 'x%.0s' {1..120})/s.sock"
    capture "$bin" -socket "$long"
    printf '== long: %s\n%s\n' "$STATUS" "$(head -1 <<<"$OUTPUT")"
    rm -rf "${long%/s.sock}"
}
flags_of "$binary" | sed -e "s#$SANDBOX#SANDBOX#g" -e "s/^$VERSION\$/VERSION/" >"$SANDBOX/flags"
assert_eq "flags, usage and exit codes match the Go daemon's" "" "$(diff "$GOLDEN/flags.out" "$SANDBOX/flags" || true)"

# --- the wire protocol over a real socket -------------------------------------
if ! command -v socat >/dev/null; then
    echo "  skip: socat missing; the socket protocol is not exercised" >&2
else
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    socket="$XDG_RUNTIME_DIR/haseen/sidecar.sock"

    # The border wipe reads its theme from -state. No Hyprland signature: the
    # daemon must never reach the Hyprland the tests run under.
    state="$SANDBOX/state"
    mkdir -p "$state/current/theme"
    cp "$HASEEN_PATH/themes/haseen/colors.toml" "$state/current/theme/colors.toml"
    env -u HYPRLAND_INSTANCE_SIGNATURE "$binary" -idle-timeout 0 -state "$state" >"$SANDBOX/daemon.log" 2>&1 &
    daemon=$!
    trap 'kill "$daemon" 2>/dev/null || true' EXIT
    for ((i = 0; i < 100; i++)); do
        [[ -S $socket ]] && break
        sleep 0.05
    done

    assert_eq "the daemon says it is ready on stdout" 1 "$(grep -c "^ready $socket" "$SANDBOX/daemon.log")"
    assert_eq "the socket belongs to this user only" "srw-------" "$(stat -c %A "$socket")"

    talk() { # REQUEST... — write the lines, read for a moment, print the frames
        {
            printf '%s\n' "$@"
            sleep 2
        } | timeout 5 socat - UNIX-CONNECT:"$socket" 2>/dev/null
    }

    frames="$(talk '{"id":1,"method":"capabilities"}')"
    hello="$(head -1 <<<"$frames")"
    assert_eq "a client is greeted with hello" hello "$(jq -r .type <<<"$hello")"
    assert_eq "the greeting carries the capability" sysusage "$(jq -r '.capabilities[0]' <<<"$hello")"
    assert_eq "and the protocol version" 1 "$(jq -r .protocol <<<"$hello")"
    assert_eq "capabilities can be asked for again" sysusage "$(jq -r 'select(.type == "reply") | .capabilities[0]' <<<"$frames")"

    frames="$(talk '{"id":2,"method":"subscribe","stream":"sysusage","params":{"intervalMs":500,"gpu":"off","processes":true}}')"
    assert_eq "subscribing is accepted" true "$(jq -r 'select(.type == "reply" and .id == 2) | .ok' <<<"$frames")"
    events="$(jq -c 'select(.type == "event")' <<<"$frames")"
    assert_eq "the stream is the one asked for" sysusage "$(head -1 <<<"$events" | jq -r .stream)"
    assert_eq "the first sample does not wait for the interval" 1 "$([[ -n $events ]] && echo 1 || echo 0)"
    assert_eq "memory is read from this machine" true "$(head -1 <<<"$events" | jq '.data.mem.totalKiB > 0')"
    assert_eq "the process list is included when asked for" true "$(tail -1 <<<"$events" | jq '.data.processes | length > 0')"
    assert_eq "several samples arrive on one subscription" true \
        "$([[ $(wc -l <<<"$events") -ge 2 ]] && echo true || echo false)"

    frames="$(talk '{"id":3,"method":"subscribe","stream":"nonsense"}')"
    assert_eq "an unknown stream is refused" false "$(jq -r 'select(.type == "reply" and .id == 3) | .ok' <<<"$frames")"
    frames="$(talk '{"id":4,"method":"nonsense"}')"
    assert_contains "an unknown method says so" "$(jq -r 'select(.id == 4) | .error' <<<"$frames")" "unknown method"
    frames="$(talk 'not json at all')"
    assert_contains "garbage does not kill the daemon" "$(jq -r 'select(.type == "reply") | .error' <<<"$frames")" "bad json"
    assert_eq "the daemon is still alive after garbage" 0 "$(kill -0 "$daemon" 2>/dev/null && echo 0 || echo 1)"

    # A client that goes away stops the sampling: with nobody subscribed the
    # daemon reads nothing at all.
    before="$(awk -F': ' '/^syscr/{print $2}' "/proc/$daemon/io")"
    sleep 2
    after="$(awk -F': ' '/^syscr/{print $2}' "/proc/$daemon/io")"
    assert_eq "no subscriber, no sampling" true \
        "$([[ $((after - before)) -lt 20 ]] && echo true || echo false)"

    # A second daemon does not fight for the socket: it reports it as ready and
    # steps aside, which is what makes "start it on demand" safe from any shell.
    capture "$binary" -idle-timeout 0
    assert_status "a second daemon exits cleanly" 0 "$STATUS"
    assert_contains "and reports the socket as ready" "$OUTPUT" "ready $socket"
    assert_eq "the first daemon still owns it" 0 "$(kill -0 "$daemon" 2>/dev/null && echo 0 || echo 1)"

    capture env HASEEN_PATH="$HASEEN_PATH" haseen sidecar status
    assert_contains "the CLI finds the socket" "$OUTPUT" "$socket"

    # --- the border wipe (plan 069) ---------------------------------------------
    assert_contains "the border wipe is off until someone subscribes" "$OUTPUT" "border wipe:  off (nobody subscribed)"

    # The shell holds this subscription while the theme asks for a wipe. The
    # haseen theme asks for 36 s a turn, slower than borderangle goes, so the
    # loop would be the daemon's; with no Hyprland to reach, it waits.
    { printf '{"id":1,"method":"subscribe","stream":"borderwipe"}\n'; sleep 2; } |
        timeout 5 socat - UNIX-CONNECT:"$socket" >"$SANDBOX/wipe.log" 2>/dev/null &
    holder=$!
    for ((i = 0; i < 40; i++)); do
        grep -q '"stream":"borderwipe"' "$SANDBOX/wipe.log" 2>/dev/null && break
        sleep 0.05
    done
    capture env HASEEN_PATH="$HASEEN_PATH" haseen sidecar status
    assert_contains "status: waiting for Hyprland, at the theme's pace" "$OUTPUT" \
        "border wipe:  waiting (Hyprland is not answering), 36 s a turn"
    wait "$holder" || true
    event="$(jq -c 'select(.type == "event" and .stream == "borderwipe") | .data' "$SANDBOX/wipe.log" | tail -1)"
    assert_eq "the subscriber hears the state" waiting "$(jq -r .state <<<"$event")"
    assert_eq "with the theme's seconds per turn" 36 "$(jq -r .secondsPerTurn <<<"$event")"
    assert_eq "and no frame sent" 0 "$(jq -r .frames <<<"$event")"
    # The daemon sees the client go asynchronously: give it a moment.
    for ((i = 0; i < 40; i++)); do
        capture env HASEEN_PATH="$HASEEN_PATH" haseen sidecar status
        [[ $OUTPUT == *"border wipe:  off"* ]] && break
        sleep 0.05
    done
    assert_contains "the subscriber gone, the loop is off" "$OUTPUT" "border wipe:  off (nobody subscribed)"

    grep -v '^border_wipe' "$HASEEN_PATH/themes/haseen/colors.toml" >"$state/current/theme/colors.toml"
    frames="$(talk '{"id":2,"method":"subscribe","stream":"borderwipe"}')"
    assert_eq "a theme without border_wipe asks for nothing" "off|the theme asks for no wipe" \
        "$(jq -r 'select(.type == "event" and .stream == "borderwipe") | .data | "\(.state)|\(.reason)"' <<<"$frames" | tail -1)"

    frames="$(talk '{"id":3,"method":"status"}')"
    assert_eq "status answers over the protocol too" off "$(jq -r 'select(.type == "reply") | .data.borderwipe.state' <<<"$frames")"

    printf '{"id":9,"method":"shutdown"}\n' | timeout 3 socat - UNIX-CONNECT:"$socket" >/dev/null 2>&1 || true
    for ((i = 0; i < 50; i++)); do
        kill -0 "$daemon" 2>/dev/null || break
        sleep 0.1
    done
    assert_eq "shutdown ends the daemon" 1 "$(kill -0 "$daemon" 2>/dev/null && echo 0 || echo 1)"
    assert_eq "and takes its socket with it" "" "$(ls "$socket" 2>/dev/null || true)"
    trap - EXIT
fi

# --- the shell side gates on the capability ------------------------------------
sidecar="$HASEEN_PATH/shell/Haseen/Sidecar.qml"
assert_contains "the client exposes a capability check" "$(cat "$sidecar")" "function has(capability"
assert_contains "losing the connection clears the capabilities" "$(cat "$sidecar")" "root.capabilities = []"
assert_contains "the sidecar singleton is registered" "$(cat "$HASEEN_PATH/shell/Haseen/qmldir")" "singleton Sidecar"
