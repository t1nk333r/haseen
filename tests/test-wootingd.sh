# shellcheck shell=bash
# haseen:covers core/wootingd/** share/haseen/VERSION tools/build-sidecar.sh
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# wootingd, the Rust daemon vendored with haseen.wooting (plan 099): its own
# 49 unit tests (`cargo test --locked`), the lifecycle the device-gated design
# needs (SIGTERM removes the socket, a second daemon is refused and leaves the
# live owner's socket alone), and tools/build-sidecar.sh building it outside
# the tree. Nothing here opens a hidraw node: the daemon runs against an empty
# fixture /sys. Without cargo the file skips with a notice; under
# HASEEN_REQUIRE_ENGINE=1 (CI, whose ARCH_PACKAGES carry rust) that is a failure.
# A rustup-managed cargo finds its toolchains under RUSTUP_HOME, which follows
# HOME; the sandbox moves HOME, so the caller's toolchain directory is named
# before it does (read for the compiler only; CI's pacman rust needs none).
rustup_home="${RUSTUP_HOME:-$HOME/.rustup}"
sandbox wootingd
[[ ! -d $rustup_home ]] || export RUSTUP_HOME="$rustup_home"
CRATE="$REPO/core/wootingd"

# The build script's refusal needs no cargo at all: a PATH without it.
nocargo="$SANDBOX/nocargo"
mkdir -p "$nocargo"
for tool in bash env cat dirname readlink mkdir; do ln -s "$(command -v "$tool")" "$nocargo/$tool"; done
capture env PATH="$nocargo" HASEEN_BUILD_SIDECAR=0 bash "$REPO/tools/build-sidecar.sh" "$SANDBOX/out/haseen-sidecar"
assert_status "without cargo the build skips wootingd and succeeds" 0 "$STATUS"
assert_contains "without cargo it says what then does not work" "$OUTPUT" "no cargo; wootingd not built, so haseen.wooting and 'haseen setup wooting' cannot work"
capture env PATH="$nocargo" HASEEN_BUILD_SIDECAR=0 HASEEN_REQUIRE_CARGO=1 bash "$REPO/tools/build-sidecar.sh" "$SANDBOX/out/haseen-sidecar"
assert_status "HASEEN_REQUIRE_CARGO=1 makes a missing cargo an error" 1 "$STATUS"
assert_eq "nothing was built" "no" "$([[ -e $SANDBOX/out/wootingd ]] && echo yes || echo no)"
# rustup's proxy without a toolchain: on PATH, but it does not run.
printf '#!/bin/sh\nexit 1\n' >"$nocargo/cargo"
chmod +x "$nocargo/cargo"
capture env PATH="$nocargo" HASEEN_BUILD_SIDECAR=0 bash "$REPO/tools/build-sidecar.sh" "$SANDBOX/out/haseen-sidecar"
assert_status "a cargo that does not run skips wootingd too" 0 "$STATUS"
assert_contains "and says so" "$OUTPUT" "cargo does not run"
rm -f "$nocargo/cargo"

if ! command -v cargo >/dev/null; then
    echo "  skip: cargo not installed; wootingd not built or tested" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "wootingd: required cargo prerequisite" available unavailable
    return 0 2>/dev/null || exit 0
fi

# A private cargo home and target dir under tests/.out (ignored), kept between
# runs: the crate's one dependency, parking_lot, is fetched once.
export CARGO_HOME="$OUT/cargo-home" CARGO_TARGET_DIR="$OUT/wootingd-target"

capture cargo test --locked --quiet --manifest-path "$CRATE/Cargo.toml"
assert_status "cargo test --locked passes" 0 "$STATUS"
assert_contains "the daemon's 49 unit tests ran" "$OUTPUT" "test result: ok. 49 passed; 0 failed"
assert_eq "the vendored crate has one dependency" '["parking_lot"]' \
    "$(sed -n '/^\[dependencies\]/,/^\[/p' "$CRATE/Cargo.toml" | sed -n 's/^\([a-z_-]*\) = .*/"\1"/p' | jq -sc .)"
# The tracked files and nothing else: cargo wrote its target dir elsewhere.
crate_files() { (cd "$CRATE" && find . -not -path "./src/*" -not -name . | LC_ALL=C sort | paste -sd" "); }
assert_eq "no build output in the tracked crate" "./Cargo.lock ./Cargo.toml ./LICENSE ./src" "$(crate_files)"

# --- the build into the tree, out of tree ----------------------------------------
dest="$SANDBOX/tree/sidecar"
capture env HASEEN_BUILD_SIDECAR=0 "$REPO/tools/build-sidecar.sh" "$dest/haseen-sidecar"
assert_status "build-sidecar builds wootingd" 0 "$STATUS"
assert_contains "it says where" "$OUTPUT" "build-sidecar: $dest/wootingd"
assert_eq "wootingd lands beside haseen-sidecar" yes "$([[ -x $dest/wootingd ]] && echo yes || echo no)"
assert_eq "the crate directory stays clean" "./Cargo.lock ./Cargo.toml ./LICENSE ./src" "$(crate_files)"
DAEMON="$dest/wootingd"

capture "$DAEMON" --help
assert_contains "the built daemon answers --help" "$OUTPUT" "usage: wootingd [doctor]"

# --- lifecycle (ported from the original tests/daemon.test.sh) --------------------
DSOCK="$SANDBOX/run/d.sock"
mkdir -p "$SANDBOX/sys" "$SANDBOX/dev" "$SANDBOX/state"
daemon_env=(WOOTINGD_SOCKET="$DSOCK" WOOTING_SYSFS_HIDRAW="$SANDBOX/sys" WOOTING_DEV_DIR="$SANDBOX/dev" XDG_STATE_HOME="$SANDBOX/state")
wait_for() {
    local i
    for ((i = 0; i < 100; i++)); do
        "$@" && return 0
        sleep 0.05
    done
    return 1
}

env "${daemon_env[@]}" "$DAEMON" 2>"$SANDBOX/daemon.log" </dev/null >/dev/null &
dpid=$!
assert_eq "wootingd binds its socket" yes "$(wait_for test -S "$DSOCK" && echo yes || echo no)"
if command -v socat >/dev/null; then
    reply=$(printf 'status\n' | socat -t2 -T2 - "UNIX-CONNECT:$DSOCK" 2>/dev/null | head -n 1)
    assert_contains "with no keyboard the daemon answers present:false" "$reply" '"present":false'
fi

capture env "${daemon_env[@]}" "$DAEMON"
assert_status "a second wootingd is refused" 1 "$STATUS"
assert_contains "the refusal says why" "$OUTPUT" "already listening"
assert_eq "the refused daemon leaves the live owner's socket" yes "$([[ -S $DSOCK ]] && echo yes || echo no)"

kill -TERM "$dpid" 2>/dev/null || true
set +e
wait "$dpid"
rc=$?
set -e
assert_status "SIGTERM is a clean exit (Restart=on-failure must not fire)" 0 "$rc"
assert_eq "SIGTERM removes the socket" no "$([[ -e $DSOCK ]] && echo yes || echo no)"

env "${daemon_env[@]}" "$DAEMON" 2>>"$SANDBOX/daemon.log" </dev/null >/dev/null &
dpid=$!
wait_for test -S "$DSOCK" || true
kill -INT "$dpid" 2>/dev/null || true
set +e
wait "$dpid"
rc=$?
set -e
assert_status "SIGINT is a clean exit" 0 "$rc"
assert_eq "SIGINT removes the socket" no "$([[ -e $DSOCK ]] && echo yes || echo no)"
assert_not_contains "an absent keyboard is not logged as a failure" "$(cat "$SANDBOX/daemon.log")" "open failed"
