# shellcheck shell=bash
# haseen-sidecar: its Go tests, the wire protocol over a real socket, and the
# CLI around it. Everything here needs the built daemon; without a Go toolchain
# the whole file skips, which is the same state a machine without it is in.
sandbox sidecar
GO="${GO:-go}"
if ! command -v "$GO" >/dev/null; then
    echo "  skip: no go toolchain (set GO=...); haseen-sidecar not built or tested" >&2
    return 0 2>/dev/null || exit 0
fi
go_bin="$(dirname "$(command -v "$GO")")"
export PATH="$go_bin:$PATH"
# The module cache is read-only once written, and the sandbox is wiped with
# rm -rf on the next run; keep it out of the sandbox.
export GOPATH="$OUT/gopath" GOFLAGS=-mod=mod

capture env GOFLAGS=-count=1 bash -c 'cd "$1/core" && exec "$2" test ./...' bash "$REPO" "$GO"
assert_status "go tests pass" 0 "$STATUS"
assert_not_contains "no go test failures" "$OUTPUT" "FAIL"

binary="$SANDBOX/haseen-sidecar"
capture "$REPO/tools/build-sidecar.sh" "$binary"
assert_status "the daemon builds" 0 "$STATUS"
assert_contains "the build reports where it landed" "$OUTPUT" "$binary"

assert_eq "the build announces its capabilities" "sysusage" "$("$binary" -capabilities)"

# --- the wire protocol over a real socket -------------------------------------
if ! command -v socat >/dev/null; then
    echo "  skip: socat missing; the socket protocol is not exercised" >&2
else
    export XDG_RUNTIME_DIR="$SANDBOX/run"
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
    socket="$XDG_RUNTIME_DIR/haseen/sidecar.sock"

    "$binary" -idle-timeout 0 >"$SANDBOX/daemon.log" 2>&1 &
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
