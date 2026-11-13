# shellcheck shell=bash
# haseen:covers core/sidecar/** tools/sidecar-play.py core/{go.mod,go.sum}
# haseen:covers core/cmd/haseen-sidecar/** core/internal/{proto,server,sysusage,borderwipe}/**
# haseen:covers tools/build-sidecar.sh share/haseen/VERSION bin/haseen-sidecar
# haseen:covers share/haseen/themes/haseen/colors.toml
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen-sidecar in Rust (plan 167), beside the Go daemon it replaces: its own
# tests (`cargo test --locked`, clippy), then both daemons over the same
# fixture roots and the same request lines, compared frame by frame
# (tools/sidecar-play.py), then tests/test-sidecar.sh's protocol checks against
# the Rust binary. Nothing here installs it: phase 1 ships nothing.
# Without cargo the file skips; without go, socat or python3 only the
# comparison skips. Under HASEEN_REQUIRE_ENGINE=1 (CI) a missing tool fails.
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
sandbox sidecar-rs
[[ ! -d $rustup_home ]] || export RUSTUP_HOME="$rustup_home"
CRATE="$REPO/core/sidecar"

required() { # TOOL — a missing prerequisite: a skip, or a failure in CI
    echo "  skip: $1 missing; $2" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "sidecar-rs: required $1 prerequisite" available unavailable
}

if ! command -v cargo >/dev/null; then
    required cargo "the Rust sidecar is not built or tested"
    return 0 2>/dev/null || exit 0
fi

# A private cargo home and target dir under tests/.out (ignored), kept between
# runs: the crate's one dependency, libc, is fetched once.
export CARGO_HOME="$OUT/cargo-home" CARGO_TARGET_DIR="$OUT/sidecar-target"
VERSION="$(cat "$HASEEN_PATH/VERSION")"

capture env HASEEN_VERSION="$VERSION" cargo test --locked --quiet --manifest-path "$CRATE/Cargo.toml"
assert_status "cargo test --locked passes" 0 "$STATUS"
assert_not_contains "no failed Rust test" "$OUTPUT" "FAILED"
assert_contains "the unit tests ran" "$OUTPUT" "test result: ok. 56 passed; 0 failed"
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

capture env HASEEN_VERSION="$VERSION" cargo build --release --locked --quiet --manifest-path "$CRATE/Cargo.toml"
assert_status "the release build succeeds" 0 "$STATUS"
RS="$CARGO_TARGET_DIR/release/haseen-sidecar"
assert_eq "it announces the Go daemon's capabilities" "sysusage borderwipe" "$("$RS" -capabilities)"
assert_eq "and the tree's version" "$VERSION" "$("$RS" -version)"
crate_files() { (cd "$CRATE" && find . -not -path "./src/*" -not -path "./tests/*" -not -name . | LC_ALL=C sort | paste -sd" "); }
assert_eq "no build output in the tracked crate" "./Cargo.lock ./Cargo.toml ./src ./tests" "$(crate_files)"

# --- the Go daemon beside it ------------------------------------------------------
GO="${GO:-go}"
compare=1
for tool in "$GO" socat python3 jq; do
    if ! command -v "$tool" >/dev/null; then
        required "$tool" "the two daemons are not compared"
        compare=0
    fi
done
if ((compare)); then
    go_bin="$(dirname "$(command -v "$GO")")"
    export PATH="$go_bin:$PATH" GOPATH="$OUT/gopath" GOFLAGS="-mod=mod -modcacherw"
    [[ ! -d $GOPATH/pkg/mod ]] || chmod -R u+w -- "$GOPATH/pkg/mod"
    GOD="$SANDBOX/go/haseen-sidecar"
    capture env HASEEN_BUILD_WOOTINGD=0 HASEEN_FETCH_SIDECAR=0 "$REPO/tools/build-sidecar.sh" "$GOD"
    assert_status "the Go daemon builds" 0 "$STATUS"
    [[ -x $GOD ]] || compare=0
fi

if ((compare)); then
    case_dir="$SANDBOX/c"

    # make_root — the fixture both daemons read, written fresh before each.
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

    # run_both NAME SCRIPT [ROOTLESS] — each daemon on its own socket over a
    # fresh fixture; prints nothing, leaves NAME.go and NAME.rs in $SANDBOX.
    run_both() {
        local name="$1" script="$2" impl bin root
        for impl in go rs; do
            make_root
            [[ $impl == go ]] && bin="$GOD" || bin="$RS"
            root="$case_dir/root"
            [[ ${3:-} != rootless ]] || root="$case_dir/empty"
            mkdir -p "$root"
            local sock="$SANDBOX/$impl.sock"
            env -u HYPRLAND_INSTANCE_SIGNATURE "$bin" -socket "$sock" -idle-timeout 0 -root "$root" \
                -state "$case_dir/state" >"$SANDBOX/$name.$impl.log" 2>&1 &
            local pid=$! i
            for ((i = 0; i < 100; i++)); do
                [[ -S $sock ]] && break
                sleep 0.05
            done
            timeout 60 python3 "$REPO/tools/sidecar-play.py" "$sock" "$case_dir" "$script" >"$SANDBOX/$name.$impl" 2>&1 || true
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        done
    }

    same() { # LABEL NAME — the two transcripts are identical, and real
        local d
        assert_contains "$1: the Rust daemon answered" "$(head -1 "$SANDBOX/$2.rs")" '{"type":"hello","protocol":1,'
        assert_contains "$1: the Go daemon answered" "$(head -1 "$SANDBOX/$2.go")" '{"type":"hello","protocol":1,'
        d="$(diff "$SANDBOX/$2.go" "$SANDBOX/$2.rs" || true)"
        assert_eq "$1" "" "$d"
        assert_not_contains "$1: nothing timed out" "$(cat "$SANDBOX/$2.rs")" "TIMEOUT"
    }

    # --- the protocol, line by line ---
    cat >"$SANDBOX/protocol.script" <<'EOF'
{"send": "{\"id\":1,\"method\":\"capabilities\"}"}
{"wait": "reply"}
{"send": "not json at all"}
{"wait": "reply"}
{"send": "{\"id\":\"1\",\"method\":\"capabilities\"}"}
{"wait": "reply"}
{"send": "{\"id\":1.5,\"method\":\"capabilities\"}"}
{"wait": "reply"}
{"send": "null"}
{"wait": "reply"}
{"send": "[1,2]"}
{"wait": "reply"}
{"send": "{\"ID\":2,\"Method\":\"capabilities\"}"}
{"wait": "reply"}
{"send": "{\"id\":3,\"method\":\"nonsense\"}"}
{"wait": "reply"}
{"send": "{\"id\":4,\"method\":\"subscribe\",\"stream\":\"nonsense\"}"}
{"wait": "reply"}
{"send": "{\"id\":0,\"method\":\"subscribe\",\"stream\":\"nope\"}"}
{"wait": "reply"}
{"send": "{\"id\":5,\"method\":\"unsubscribe\",\"stream\":\"sysusage\"}"}
{"wait": "reply"}
{"send": "{\"id\":6,\"method\":\"unsubscribe\"}"}
{"wait": "reply"}
{"send": "{\"id\":0,\"method\":\"unsubscribe\"}"}
{"send": "{\"id\":7,\"method\":\"status\"}"}
{"wait": "reply"}
{"send": ""}
{"send": "{\"id\":11,\"method\":\"capabilities\"}\r"}
{"wait": "reply"}
{"send": "{\"id\":12,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":0,\"gpu\":\"off\"}}"}
{"wait": "event"}
{"send": "{\"id\":13,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":-5,\"gpu\":\"off\"}}"}
{"wait": "event"}
{"send": "{\"id\":14,\"method\":\"unsubscribe\",\"stream\":\"sysusage\"}"}
{"wait": "reply"}
{"send": "{\"id\":-8,\"method\":\"capabilities\",\"params\":{\"a\":[1e400]}}"}
{"wait": "reply"}
{"send": "{\"id\":9,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":\"soon\",\"processes\":\"yes\",\"gpu\":\"off\"}}"}
{"wait": "event"}
{"send": "{\"id\":10,\"method\":\"unsubscribe\",\"stream\":\"sysusage\"}"}
{"wait": "reply"}
EOF
    run_both protocol "$SANDBOX/protocol.script" rootless
    same "the protocol answers as the Go daemon's" protocol

    # --- the samples: every reader, twice, the fixture moving between ---
    cat >"$SANDBOX/sysusage.script" <<'EOF'
{"send": "{\"id\":1,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"processes\":true,\"system\":true}}"}
{"wait": "event"}
{"write": ["root/proc/stat", "cpu  150 0 150 800 100 0 0 0 0 0\n"]}
{"write": ["root/proc/10/stat", "10 (quiet) R 1 1 1 0 -1 0 0 0 0 0 110 0 0 0 20 0 1 0 0 0 25\n"]}
{"write": ["root/proc/11/stat", "11 (a<b>&(c)) R 1 1 1 0 -1 0 0 0 0 0 400 0 0 0 20 0 1 0 0 0 50\n"]}
{"write": ["root/proc/net/dev", "Inter-|\n face |\n  wlan0: 5000 10 0 0 0 0 0 0 1100 10 0 0 0 0 0 0\n  tun0: 7 1 0 0 0 0 0 0 7 1 0 0 0 0 0 0\n"]}
{"write": ["root/sys/class/drm/card1/gt_act_freq_mhz", "700\n"]}
{"sleep": 50}
{"send": "{\"id\":2,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"processes\":true,\"system\":true}}"}
{"wait": "event"}
{"send": "{\"id\":3,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"gpu\":\"card0\"}}"}
{"wait": "event"}
{"send": "{\"id\":4,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"gpu\":\"card2\",\"system\":true}}"}
{"wait": "event"}
{"send": "{\"id\":5,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"gpu\":\"card9\"}}"}
{"wait": "event"}
{"write": ["root/proc/stat", "garbage\n"]}
{"write": ["root/proc/meminfo", "MemTotal: 100 kB\nMemFree: 50 kB\nBuffers: 10 kB\nCached: 10 kB\n"]}
{"send": "{\"id\":6,\"method\":\"subscribe\",\"stream\":\"sysusage\",\"params\":{\"intervalMs\":3600000,\"gpu\":\"off\"}}"}
{"wait": "event"}
EOF
    run_both sysusage "$SANDBOX/sysusage.script"
    same "every sample matches the Go daemon's" sysusage
    assert_contains "the comparison saw the escaped process name" "$(cat "$SANDBOX/sysusage.rs")" '"command":"busy --flag"'
    assert_contains "and the btrfs root once, at its shortest mount" "$(cat "$SANDBOX/sysusage.rs")" '"mount":"/","device":"/dev/mapper/root"'
    assert_contains "and an Intel card at half its clock" "$(cat "$SANDBOX/sysusage.rs")" '"gpu":50,'

    run_both empty "$SANDBOX/sysusage.script" rootless
    same "an empty root is unknown in both" empty

    # --- the border wipe, without a Hyprland ---
    cat >"$SANDBOX/wipe.script" <<'EOF'
{"send": "{\"id\":1,\"method\":\"subscribe\",\"stream\":\"borderwipe\"}"}
{"wait": "event", "n": 2}
{"send": "{\"id\":2,\"method\":\"status\"}"}
{"wait": "reply"}
{"write": ["state/current/theme/colors.toml", "accent = \"#7aa2f7\"\n"]}
{"send": "{\"id\":0,\"method\":\"unsubscribe\",\"stream\":\"borderwipe\"}"}
{"sleep": 100}
{"send": "{\"id\":3,\"method\":\"subscribe\",\"stream\":\"borderwipe\",\"params\":{\"signature\":\"nobody\"}}"}
{"wait": "event", "n": 2}
{"write": ["state/current/theme/colors.toml", "border_wipe = \"rgba(F25623ff) os.execute('x')\"\nborder_wipe_seconds = 36\n"]}
{"send": "{\"id\":0,\"method\":\"unsubscribe\"}"}
{"sleep": 100}
{"send": "{\"id\":4,\"method\":\"subscribe\",\"stream\":\"borderwipe\"}"}
{"wait": "event", "n": 2}
{"send": "{\"id\":5,\"method\":\"status\"}"}
{"wait": "reply"}
EOF
    run_both wipe "$SANDBOX/wipe.script"
    same "the border wipe's states match the Go daemon's" wipe
    assert_contains "the comparison saw the theme's pace" "$(cat "$SANDBOX/wipe.rs")" '"state":"waiting","reason":"Hyprland is not answering","secondsPerTurn":36'
    assert_contains "and a colour refused" "$(cat "$SANDBOX/wipe.rs")" '"reason":"colors.toml: border_wipe: a colour is not rgba(RRGGBBAA), rgb(RRGGBB) or 0xAARRGGBB"'

    # --- flags, stdout and exits ---
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
    flags_of "$GOD" >"$SANDBOX/flags.go"
    flags_of "$RS" >"$SANDBOX/flags.rs"
    assert_eq "flags, usage and exit codes match the Go daemon's" "" "$(diff "$SANDBOX/flags.go" "$SANDBOX/flags.rs" || true)"

    # A second daemon on a live socket steps aside the same way.
    "$GOD" -socket "$SANDBOX/live.sock" -idle-timeout 0 >/dev/null 2>&1 &
    live=$!
    for ((i = 0; i < 100; i++)); do
        [[ -S $SANDBOX/live.sock ]] && break
        sleep 0.05
    done
    capture "$RS" -socket "$SANDBOX/live.sock"
    assert_status "beside a live Go daemon the Rust one exits cleanly" 0 "$STATUS"
    assert_eq "and says the socket is ready" "ready $SANDBOX/live.sock" "$OUTPUT"
    kill "$live" 2>/dev/null || true
    wait "$live" 2>/dev/null || true
fi

# --- tests/test-sidecar.sh's protocol checks, against the Rust binary ------------
if ! command -v socat >/dev/null; then
    required socat "the socket protocol is not exercised"
else
    socket="$XDG_RUNTIME_DIR/haseen/sidecar.sock"
    state="$SANDBOX/state"
    mkdir -p "$state/current/theme"
    cp "$HASEEN_PATH/themes/haseen/colors.toml" "$state/current/theme/colors.toml"
    env -u HYPRLAND_INSTANCE_SIGNATURE "$RS" -idle-timeout 0 -state "$state" >"$SANDBOX/daemon.log" 2>&1 &
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

    frames="$(talk '{"id":2,"method":"subscribe","stream":"sysusage","params":{"intervalMs":500,"gpu":"off","processes":true}}')"
    assert_eq "subscribing is accepted" true "$(jq -r 'select(.type == "reply" and .id == 2) | .ok' <<<"$frames")"
    events="$(jq -c 'select(.type == "event")' <<<"$frames")"
    assert_eq "memory is read from this machine" true "$(head -1 <<<"$events" | jq '.data.mem.totalKiB > 0')"
    assert_eq "the process list is included when asked for" true "$(tail -1 <<<"$events" | jq '.data.processes | length > 0')"
    assert_eq "several samples arrive on one subscription" true \
        "$([[ $(wc -l <<<"$events") -ge 3 ]] && echo true || echo false)"

    before="$(awk -F': ' '/^syscr/{print $2}' "/proc/$daemon/io")"
    sleep 2
    after="$(awk -F': ' '/^syscr/{print $2}' "/proc/$daemon/io")"
    assert_eq "no subscriber, no sampling" true "$([[ $((after - before)) -lt 20 ]] && echo true || echo false)"

    capture env HASEEN_PATH="$HASEEN_PATH" haseen sidecar status
    assert_contains "the CLI reads the Rust daemon's border wipe" "$OUTPUT" "border wipe:  off (nobody subscribed)"
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
    for ((i = 0; i < 40; i++)); do
        capture env HASEEN_PATH="$HASEEN_PATH" haseen sidecar status
        [[ $OUTPUT == *"border wipe:  off"* ]] && break
        sleep 0.05
    done
    assert_contains "the subscriber gone, the loop is off" "$OUTPUT" "border wipe:  off (nobody subscribed)"

    printf '{"id":9,"method":"shutdown"}\n' | timeout 3 socat - UNIX-CONNECT:"$socket" >/dev/null 2>&1 || true
    for ((i = 0; i < 50; i++)); do
        kill -0 "$daemon" 2>/dev/null || break
        sleep 0.1
    done
    assert_eq "shutdown ends the daemon" 1 "$(kill -0 "$daemon" 2>/dev/null && echo 0 || echo 1)"
    assert_eq "and takes its socket with it" "" "$(ls "$socket" 2>/dev/null || true)"
    trap - EXIT
fi
