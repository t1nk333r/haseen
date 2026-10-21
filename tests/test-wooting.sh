# shellcheck shell=bash
# haseen:covers bin/haseen-plugin-validate bin/haseen-setup-wooting bin/haseen-wooting
# haseen:covers bin/haseen-wooting-doctor core/wootingd/LICENSE share/haseen/VERSION
# haseen:covers share/haseen/default/shell.json share/haseen/default/systemd/wootingd.service
# haseen:covers share/haseen/default/udev/70-wootingd.rules share/haseen/lib/{terminal,wooting}.sh
# haseen:covers share/haseen/migrations/{1792531693-omarchy-path,1792577102-adopt-wooting}.sh
# haseen:covers share/haseen/shell/Compat/** share/haseen/shell/Haseen/**
# haseen:covers share/haseen/shell/{Common,Commons,Modules,Services,Ui,Widgets}
# haseen:covers share/haseen/shell/lib/plugin.sh share/haseen/shell/plugin.schema.json
# haseen:covers share/haseen/shell/plugins/haseen.wooting/** tools/fake-wootingd.py
# haseen:covers tools/smoke-session.conf CLAUDE.md NOTICE.md
# haseen:covers share/haseen/shell/plugins/*/manifest.json AGENTS.md
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 099: the owner's t1nk33r.wooting adopted as haseen.wooting, off by
# default. The manifest and contracts; the plugin's own Model.js suite; the
# socket library, `haseen wooting` and its doctor against tools/fake-wootingd.py
# (ported from the original's ipc, cli and doctor suites); `haseen setup
# wooting` in fixture sysroots, including the take-over of the plugin's rule
# and unit; the migration of the old id; the widget and panel in the real
# engine. Nothing here opens a hidraw node or runs the real daemon (that is
# tests/test-wootingd.sh).

PLUGIN="$HASEEN_PATH/shell/plugins/haseen.wooting"
FAKE="$REPO/tools/fake-wootingd.py"
QS_BIN=${QS_BIN:-/usr/bin/qs}
MIG=1792577102-adopt-wooting.sh

engine_skip() {
    echo "  skip: $1" >&2
    [[ ${HASEEN_REQUIRE_ENGINE:-0} != 1 ]] || assert_eq "$1: required engine prerequisite" available unavailable
    return 0
}

# --- fake daemon -----------------------------------------------------------------
FAKE_PIDS=()
# fake_start NAME [fake flags...] — a fake wootingd on its own socket, which
# WOOTINGD_SOCKET then names; state set by one scenario never leaks into the next.
fake_start() {
    local sock="$XDG_RUNTIME_DIR/$1.sock" i
    shift
    python3 -I "$FAKE" "$sock" "$@" </dev/null >/dev/null 2>&1 &
    FAKE_PIDS+=("$!")
    for ((i = 0; i < 200; i++)); do
        [[ -S $sock ]] && break
        sleep 0.02
    done
    export WOOTINGD_SOCKET="$sock"
}
fake_stop_all() {
    local p
    for p in ${FAKE_PIDS[@]+"${FAKE_PIDS[@]}"}; do
        kill "$p" 2>/dev/null || true
        wait "$p" 2>/dev/null || true
    done
    FAKE_PIDS=()
}
trap fake_stop_all EXIT
# fake_ask VERB... — the fake's raw reply line, straight off the socket.
fake_ask() { printf '%s\n' "$*" | socat -t2 -T2 - "UNIX-CONNECT:$WOOTINGD_SOCKET" 2>/dev/null | head -n 1; }
# wrun ARGS... — haseen wooting; stdout in WOUT, stderr in WERR, STATUS.
wrun() {
    set +e
    WOUT="$(haseen wooting "$@" 2>"$SANDBOX/err")"
    STATUS=$?
    set -e
    WERR="$(<"$SANDBOX/err")"
}

# --- manifest, contract, off by default ------------------------------------------
sandbox wt-manifest
capture haseen plugin validate haseen.wooting
assert_status "haseen.wooting validates" 0 "$STATUS"
assert_contains "haseen.wooting is ok" "$OUTPUT" "ok: haseen.wooting (builtin:"
assert_not_contains "it asks for no network" "$OUTPUT" "warning:"
DEFAULT="$HASEEN_PATH/default/shell.json"
assert_eq "haseen.wooting is off by default (in no default section or service)" "false" \
    "$(jq '[.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned, .services] | add | index("haseen.wooting") != null' "$DEFAULT")"
assert_eq "the plugin keeps the owner's licence" "MIT License|Copyright (c) 2026 t1nk33r" "$(sed -n '1p;3p' "$PLUGIN/LICENSE" | paste -sd'|')"
assert_eq "the daemon keeps the owner's licence" "$(cat "$PLUGIN/LICENSE")" "$(cat "$REPO/core/wootingd/LICENSE")"
assert_contains "UPSTREAM.md names the source and plan" "$(cat "$PLUGIN/UPSTREAM.md")" "commit \`184f6fabf7f9b54c9bd48870cfd64596f086cfc7\`"
assert_contains "UPSTREAM.md names plan 099" "$(cat "$PLUGIN/UPSTREAM.md")" "plan \`plans/099-adopt-wooting.md\`"
NOTICE="$(cat "$REPO/NOTICE.md")"
assert_contains "NOTICE.md lists the plugin" "$NOTICE" "share/haseen/shell/plugins/haseen.wooting/"
assert_contains "NOTICE.md lists the daemon" "$NOTICE" "core/wootingd/"
for src in WootingKb/wooting-rgb-sdk WootingKb/wooting-analog-sdk ShayBox/Wooting-Profile-Switcher clemenscodes/wootswitch; do
    assert_contains "NOTICE.md names $src as a source of wootingd's protocol facts" "$NOTICE" "$src"
done
ADOPTED=$(tr -s ' \n' ' ' <"$REPO/CLAUDE.md")
assert_contains "CLAUDE.md records the owner's adoption" "$ADOPTED" \
    "plan 099, the owner's plugin (owner, 2026-10-21): haseen.wooting, with its vendored Rust daemon wootingd."
for f in "$PLUGIN"/*.qml; do
    assert_eq "${f#"$PLUGIN"/}: says where it comes from" "1" "$(head -n12 "$f" | grep -cE 'MIT|no upstream code' | sed 's/^[1-9][0-9]*$/1/')"
done
for kind in bar-widget panel; do
    entry="$PLUGIN/$(jq -r --arg k "$kind" '.entry[$k]' "$PLUGIN/manifest.json")"
    assert_contains "$kind entry takes pluginId" "$(cat "$entry")" "property string pluginId"
    assert_contains "$kind entry takes settings" "$(cat "$entry")" "property var settings: ({})"
done
assert_eq "the manifest keeps the original's settings and defaults" '{"hideWhenAbsent":true,"nameMaxChars":12,"showName":true}' \
    "$(jq -cS '.settings | map_values(.default)' "$PLUGIN/manifest.json")"
assert_eq "no compat module" "" "$(grep -rnE '^import qs\.(Commons|Ui|Common|Services|Widgets|Modules)\b' "$PLUGIN" --include='*.qml' || true)"
assert_eq "no Omarchy command or path in code" "" \
    "$(grep -rnE '"omarchy[a-z-]*"|OMARCHY_PATH|omarchy-shell|\.config/omarchy' "$PLUGIN" --include='*.qml' --include='*.js' | grep -vE '^[^:]+:[0-9]+:\s*//' || true)"
assert_eq "no colour literal in the plugin's QML" "" "$(grep -rnE '"#[0-9a-fA-F]{3,8}"|Qt\.rgba\(' "$PLUGIN" --include='*.qml' || true)"
assert_eq "no privilege escalation" "" "$(grep -rnE '"(sudo|pkexec|run0|doas)"' "$PLUGIN" --include='*.qml' --include='*.js' || true)"
assert_eq "outside text is never rich text" "" "$(grep -rn 'Text.RichText\|Text.StyledText' "$PLUGIN" --include='*.qml' || true)"
assert_eq "one Timer, a marked bounded retry" "1|// haseen:ui-timeout" \
    "$(grep -rc 'Timer {' "$PLUGIN" --include='*.qml' | awk -F: '{s += $2} END {print s}')|$(grep -B1 'Timer {' "$PLUGIN/WootingLink.qml" | head -n1 | sed 's/^ *//')"
assert_eq "no HID path in the shell side" "" "$(grep -rnE '/dev/hidraw|HIDIOC' "$PLUGIN" --include='*.qml' --include=Model.js || true)"
for f in bin/haseen-wooting bin/haseen-wooting-doctor bin/haseen-setup-wooting; do
    capture "$REPO/$f" --help
    assert_status "$f --help" 0 "$STATUS"
    assert_contains "$f has a summary" "$(cat "$REPO/$f")" "# haseen:summary"
    assert_contains "$f has its args" "$(cat "$REPO/$f")" "# haseen:args"
    assert_contains "$f keeps the MIT notice" "$(head -n12 "$REPO/$f")" "MIT"
done

# --- the plugin's own Model.js suite ---------------------------------------------
if command -v node >/dev/null; then
    capture node "$PLUGIN/tests/model.test.js"
    assert_status "Model.js suite (the original's)" 0 "$STATUS"
    assert_contains "Model.js suite count" "$OUTPUT" "269 passed, 0 failed"
else
    engine_skip "node not installed; the Model.js suite"
fi

if ! command -v socat >/dev/null || ! command -v python3 >/dev/null; then
    engine_skip "socat or python3 missing; the socket, CLI and doctor scenarios"
else
    # --- the socket library (ported from tests/ipc.test.sh) -----------------------
    sandbox wt-ipc
    # ipc SNIPPET [env args...] — a snippet with lib/wooting.sh sourced, in a
    # clean child shell so environment changes cannot leak between cases.
    ipc() {
        local snippet=$1
        shift
        set +e
        WOUT=$(env "$@" bash -c 'set -uo pipefail; source "$HASEEN_PATH/lib/wooting.sh"; '"$snippet" 2>"$SANDBOX/err")
        STATUS=$?
        set -e
        WERR=$(<"$SANDBOX/err")
    }
    ipc 'wooting_socket' WOOTINGD_SOCKET=/run/explicit.sock XDG_RUNTIME_DIR=/run/user/9
    assert_eq "WOOTINGD_SOCKET wins" "/run/explicit.sock" "$WOUT"
    ipc 'wooting_socket' -u WOOTINGD_SOCKET XDG_RUNTIME_DIR=/run/user/9
    assert_eq "XDG_RUNTIME_DIR is the fallback" "/run/user/9/wootingd.sock" "$WOUT"
    ipc 'wooting_socket' -u WOOTINGD_SOCKET -u XDG_RUNTIME_DIR
    assert_eq "the last resort is /tmp/wootingd-UID.sock" "/tmp/wootingd-$(id -u).sock" "$WOUT"
    ipc 'wooting_socket_present && echo yes || echo no' WOOTINGD_SOCKET="$SANDBOX/none.sock"
    assert_eq "no socket, not present" "no" "$WOUT"
    before=$(find "$SANDBOX" -maxdepth 1 | sort)
    ipc 'printf sourced'
    assert_eq "sourcing prints nothing of its own" "sourced|" "$WOUT|$WERR"
    assert_eq "sourcing creates no files" "$before" "$(find "$SANDBOX" -maxdepth 1 | sort)"

    fake_start ipc
    ipc 'wooting_send ping' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_eq "ping is passed through verbatim" '0|{"ok":true,"pong":true}|' "$STATUS|$WOUT|$WERR"
    ipc 'wooting_send status | jq -r .serial' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_eq "status carries the serial" "A00B0000W00T00000S00H00000" "$WOUT"
    ipc 'wooting_send bogus verb | jq -r .error' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_eq "a daemon-level error is a transport success" "0|unknown verb: bogus verb" "$STATUS|$WOUT"
    ipc 'wooting_send profile set 1 | jq -r .error' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_eq "the empty-slot error surfaces intact, em dash included" \
        "slot 1 holds no stored profile — create it in Wootility first (selectable: 0)" "$WOUT"
    ipc 'wooting_send status | wc -l' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_eq "exactly one reply line" "1" "$WOUT"
    start=$(date +%s%N)
    ipc 'wooting_send ping >/dev/null' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    elapsed=$((($(date +%s%N) - start) / 1000000))
    assert_eq "a round trip returns on the reply, not the timeout" yes "$( ((elapsed < 1500)) && echo yes || echo no)"
    ipc 'wooting_send ping' WOOTINGD_SOCKET="$SANDBOX/absent.sock"
    assert_status "a missing socket is exit 3" 3 "$STATUS"
    assert_contains "it names the path" "$WERR" "no daemon socket at $SANDBOX/absent.sock"
    fake_start ipcg --garbage
    ipc 'wooting_send status' WOOTINGD_SOCKET="$WOOTINGD_SOCKET"
    assert_status "a non-JSON reply is exit 1" 1 "$STATUS"
    assert_contains "the offending reply is quoted" "$WERR" "not a JSON object: this is not JSON"
    fake_start ipcs --silent
    start=$(date +%s%N)
    ipc 'wooting_send status' WOOTINGD_SOCKET="$WOOTINGD_SOCKET" WOOTING_IPC_TIMEOUT=0.5
    elapsed=$((($(date +%s%N) - start) / 1000000))
    assert_status "a daemon that never answers is exit 3" 3 "$STATUS"
    assert_contains "silence names the verb" "$WERR" "did not answer status"
    assert_eq "it was the timeout that ended it" yes "$( ((elapsed >= 400)) && echo yes || echo no)"
    fake_stop_all

    # --- haseen wooting (ported from tests/cli.test.sh) ----------------------------
    sandbox wt-cli
    wrun --help
    assert_status "--help exits 0" 0 "$STATUS"
    assert_contains "--help lists status" "$WOUT" "status [--json]"
    assert_contains "--help lists set" "$WOUT" "set SLOT|NAME"
    assert_contains "--help carries the exit-code registry" "$WOUT" "3  daemon not reachable"
    assert_contains "--help carries the whole registry" "$WOUT" "5  dependency missing"
    wrun
    assert_eq "no subcommand is a usage error, on stderr" "2|" "$STATUS|$WOUT"
    assert_contains "no subcommand prints the usage" "$WERR" "Usage: haseen wooting"
    wrun nonsense
    assert_status "an unknown subcommand is exit 2" 2 "$STATUS"
    assert_contains "the unknown subcommand is named" "$WERR" "unknown command: nonsense"

    fake_start cli
    wrun status
    assert_status "status exits 0" 0 "$STATUS"
    assert_contains "status reports the keyboard" "$WOUT" "keyboard:       present"
    assert_contains "status reports the firmware" "$WOUT" "firmware:       v2.14.0"
    assert_contains "status names the node and framing" "$WOUT" "/dev/hidraw5 (arm framing)"
    assert_contains "status counts the selectable profiles" "$WOUT" "active slot:    0 of 1"
    assert_contains "status marks the active profile" "$WOUT" "* 0  1 Typing Profile"
    assert_eq "a healthy status says nothing on stderr" "" "$WERR"
    raw=$(fake_ask status)
    wrun status --json
    assert_eq "status --json is a byte-for-byte passthrough" "$raw" "$WOUT"
    wrun get
    assert_eq "get prints just the active slot" "0|0" "$STATUS|$WOUT"
    wrun list
    assert_eq "list is slot, name, active" "$(printf '0\t1 Typing Profile\tactive')" "$WOUT"
    raw=$(fake_ask profile list)
    wrun list --json
    assert_eq "list --json is a passthrough" "$raw" "$WOUT"
    wrun analog
    assert_eq "analog prints nothing with no key pressed" "0|" "$STATUS|$WOUT"
    raw=$(fake_ask analog get)
    wrun analog --json
    assert_eq "analog --json is a passthrough" "$raw" "$WOUT"

    wrun set 0
    assert_eq "set SLOT prints the new slot" "0|0" "$STATUS|$WOUT"
    wrun set 1
    assert_status "an addressable but empty slot is exit 2" 2 "$STATUS"
    assert_contains "the daemon's empty-slot error is surfaced" "$WERR" "slot 1 holds no stored profile — create it in Wootility first (selectable: 0)"
    wrun set 9
    assert_status "an out-of-range slot is exit 2" 2 "$STATUS"
    assert_contains "the daemon's range error is surfaced" "$WERR" "slot 9 out of range (device has 4 addressable slots; selectable: 0)"
    wrun set 999
    assert_contains "the daemon's parse error is surfaced" "$WERR" "profile set: 999 is not a slot number"
    wrun set
    assert_eq "set with no argument is exit 2" "2" "$STATUS"
    assert_contains "set shows its usage" "$WERR" "usage: haseen wooting set SLOT|NAME"
    wrun set 1 2
    assert_contains "set explains the argument count" "$WERR" "exactly one slot or name"
    wrun status --xml
    assert_contains "an unknown flag is named" "$STATUS|$WERR" "2|wooting: unknown option for status: --xml"
    wrun status --json extra
    assert_contains "trailing junk is explained" "$STATUS|$WERR" "2|wooting: status takes no further arguments"
    wrun get --json
    assert_contains "get takes no flags" "$STATUS|$WERR" "2|wooting: get takes no arguments"

    fake_start cli4 --profiles 4
    wrun status
    assert_contains "status counts every stored profile" "$WOUT" "active slot:    0 of 4"
    assert_contains "status flags nameless stored slots" "$WOUT" "  1  Profile 2  (unnamed slot)"
    wrun set 2 --dry-run
    assert_eq "set --dry-run asks for nothing" "0|DRYRUN: wootingd profile set 2" "$STATUS|$WOUT"
    wrun get
    assert_eq "the dry run changed nothing" "0" "$WOUT"
    wrun set 'pROFILE 4' --dry-run
    assert_eq "a name resolves in a dry run too" "DRYRUN: wootingd profile set 3" "$WOUT"
    wrun set 2
    assert_eq "set switches" "0|2" "$STATUS|$WOUT"
    wrun get
    assert_eq "the switch stuck" "2" "$WOUT"
    wrun set '1 Typing Profile'
    assert_eq "set NAME resolves to its slot" "0" "$WOUT"
    wrun set 'pROFILE 4'
    assert_eq "set NAME is case-insensitive" "3" "$WOUT"
    wrun set 'Profile'
    assert_status "a partial name is not a match" 2 "$STATUS"
    assert_contains "the miss points at list" "$WERR" 'no profile named "Profile" (see: haseen wooting list)'
    wrun set 1
    assert_eq "a bare number is a slot index" "1" "$WOUT"

    fake_start cli5 --analog-keys '[{"row":2,"col":2,"code":26,"value":0.62,"actuated":true},{"row":5,"col":6,"code":44,"value":0.1,"actuated":false}]'
    wrun analog
    assert_eq "analog is row/col/code/travel/actuated" "$(printf '2\t2\t26\t0.62\tactuated\n5\t6\t44\t0.1\t-')" "$WOUT"
    set +e
    WOUT=$(timeout 1 haseen wooting analog --follow 2>"$SANDBOX/follow.err")
    STATUS=$?
    set -e
    assert_status "analog --follow is still connected when killed" 124 "$STATUS"
    assert_contains "analog --follow starts with the analog event" "$WOUT" '"event":"analog"'
    assert_contains "analog --follow carries the keys" "$WOUT" '"code":26'
    assert_not_contains "no socat signal chatter" "$(cat "$SANDBOX/follow.err")" "exiting on signal"
    python3 -I -c "import socket,sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])" "$SANDBOX/dead.sock"
    set +e
    WOUT=$(WOOTINGD_SOCKET="$SANDBOX/dead.sock" haseen wooting analog --follow 2>&1)
    STATUS=$?
    set -e
    assert_status "a dead socket is exit 3" 3 "$STATUS"
    assert_contains "a dead socket is named" "$WOUT" "wooting: wootingd is not answering on $SANDBOX/dead.sock"

    fake_start cli6 --fn-map '{"3,3":73,"4,2":77,"2,4":1024}'
    wrun fn
    assert_eq "fn prints row/col/code" "$(printf '3\t3\t73\n4\t2\t77\n2\t4\t1024')" "$WOUT"
    wrun fn --json
    assert_contains "fn --json carries the map" "$WOUT" '"count":3'

    WOOTINGD_SOCKET="$SANDBOX/gone.sock" wrun status
    assert_status "status without a daemon is exit 3" 3 "$STATUS"
    assert_contains "no socket reads as no keyboard first" "$WERR" "runs only while a Wooting keyboard is plugged in"
    assert_contains "the fix is haseen's" "$WERR" "haseen setup wooting on"
    WOOTINGD_SOCKET="$SANDBOX/gone.sock" wrun set 'Profile 2'
    assert_status "set NAME without a daemon is exit 3" 3 "$STATUS"

    fake_start cli7 --absent
    wrun status
    assert_status "status without a keyboard is exit 4" 4 "$STATUS"
    assert_contains "status still reports the live daemon" "$WOUT" "running on $WOOTINGD_SOCKET"
    wrun status --json
    assert_contains "status --json answers present:false with exit 0" "$STATUS|$WOUT" '0|{"ok":true,"present":false'
    wrun set '1 Typing Profile'
    assert_eq "set NAME without a keyboard blames the keyboard" "4|wooting: no keyboard present" "$STATUS|$WERR"
    wrun analog
    assert_contains "analog with no keyboard is exit 4" "$STATUS|$WERR" "4|wooting: no analog interface present"

    fake_start cli8 --error 'device did not answer'
    wrun status
    assert_eq "an unrecognised daemon error is exit 1" "1|wooting: device did not answer" "$STATUS|$WERR"
    fake_start cli9 --silent
    start=$(date +%s%N)
    WOOTING_IPC_TIMEOUT=0.5 wrun get
    elapsed=$((($(date +%s%N) - start) / 1000000))
    assert_contains "a daemon that never answers is exit 3" "$STATUS|$WERR" "3|wooting: daemon at"
    assert_eq "the timeout ended it" yes "$( ((elapsed >= 400)) && echo yes || echo no)"

    nodeps="$SANDBOX/nodeps"
    mkdir -p "$nodeps"
    for tool in env bash readlink dirname sed cat; do ln -s "$(command -v "$tool")" "$nodeps/$tool"; done
    set +e
    WERR=$(PATH="$nodeps" "$REPO/bin/haseen-wooting" status 2>&1 >/dev/null)
    STATUS=$?
    set -e
    assert_eq "a missing dependency is exit 5 and named" "5|wooting: missing dependency: socat jq (pacman -S socat jq)" "$STATUS|$WERR"
    set +e
    WOUT=$(PATH="$nodeps" "$REPO/bin/haseen-wooting" --help 2>&1)
    STATUS=$?
    set -e
    assert_contains "--help still works without socat and jq" "$STATUS|$WOUT" "0|Usage: haseen wooting"
    fake_stop_all

    # --- haseen wooting doctor (ported from tests/doctor.test.sh) ---------------------
    sandbox wt-doctor
    FIX="$SANDBOX/fix"
    mk_node() { # SYSFS NODE VENDOR DESCRIPTOR-BYTES
        mkdir -p "$1/$2/device"
        printf 'HID_ID=0003:0000%s:00001322\nHID_NAME=Wooting 60HE+\n' "$3" >"$1/$2/device/uevent"
        # shellcheck disable=SC2059  # the byte string is the format
        printf "$4" >"$1/$2/device/report_descriptor"
    }
    SYSFS_OK="$FIX/sys-ok"
    mk_node "$SYSFS_OK" hidraw3 31E3 '\x06\x00\xff\x09\x01'
    mk_node "$SYSFS_OK" hidraw5 31E3 '\x06\x55\xff\x09\x01'
    mk_node "$SYSFS_OK" hidraw7 31E3 '\x06\x53\xff\x09\x01'
    mk_node "$SYSFS_OK" hidraw9 046D '\x06\x55\xff\x09\x01'
    SYSFS_ANALOG="$FIX/sys-analog"
    mk_node "$SYSFS_ANALOG" hidraw7 31E3 '\x06\x53\xff\x09\x01'
    SYSFS_STD="$FIX/sys-std"
    mk_node "$SYSFS_STD" hidraw2 31E3 '\x06\x37\x13\x09\x01'
    SYSFS_NONE="$FIX/sys-none"
    mk_node "$SYSFS_NONE" hidraw0 046D '\x05\x01\x09\x02'
    DEV_OK="$FIX/dev-ok"
    mkdir -p "$DEV_OK" "$FIX/dev-std" "$FIX/dev-locked" "$FIX/dev-empty"
    : >"$DEV_OK/hidraw5"
    : >"$FIX/dev-std/hidraw2"
    : >"$FIX/dev-locked/hidraw5"
    chmod 600 "$DEV_OK/hidraw5" "$FIX/dev-std/hidraw2"
    chmod 000 "$FIX/dev-locked/hidraw5"
    UDEV_ACCESS="$FIX/udev-access"
    UDEV_HASEEN="$FIX/udev-haseen"
    UDEV_DECOYS="$FIX/udev-decoys"
    mkdir -p "$UDEV_ACCESS" "$UDEV_HASEEN" "$UDEV_DECOYS" "$FIX/udev-empty"
    printf '%s\n' 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess"' >"$UDEV_ACCESS/70-wooting.rules"
    cp "$HASEEN_PATH/default/udev/70-wootingd.rules" "$UDEV_HASEEN/"
    printf '%s\n' '# SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess"' >"$UDEV_DECOYS/70-wooting.rules"
    printf '%s\n' 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess"' >"$UDEV_DECOYS/70-wooting.rules.bak"
    printf '%s\n' 'Wooting keyboards use vendor id 31e3.' >"$UDEV_DECOYS/README"
    # pgrep as procps without -f: PATTERN against the 15-character comm, from
    # $FAKE_PROCS ("pid name" lines); -x wants the whole comm.
    PG="$FIX/pg"
    mkdir -p "$PG"
    cat >"$PG/pgrep" <<'FAKEPG'
#!/usr/bin/env bash
exact=0
if [[ ${1:-} == -x ]]; then exact=1; shift; fi
pat=${1:?pattern}
found=1
while read -r pid comm; do
  comm=${comm:0:15}
  if ((exact)); then [[ $comm =~ ^($pat)$ ]] || continue; else [[ $comm =~ $pat ]] || continue; fi
  printf '%s\n' "$pid"
  found=0
done < "${FAKE_PROCS:-/dev/null}"
exit "$found"
FAKEPG
    chmod +x "$PG/pgrep"
    printf '%s\n' '4343 wooting-bg-service' >"$FIX/procs-bg"
    printf '%s\n' '777 wootingd' >"$FIX/procs-daemon"
    cat >"$FIX/wootingd" <<'FAKED'
#!/usr/bin/env bash
[[ $1 == doctor ]] || { printf 'unexpected args: %s\n' "$*" >&2; exit 64; }
printf 'device        : /dev/hidraw5 usage_page=0xFF55\n'
exit "${FAKE_WOOTINGD_RC:-0}"
FAKED
    chmod +x "$FIX/wootingd"
    mk_proc() { # DIR [pid:comm:target]...
        local dir=$1 spec pid comm target
        shift
        mkdir -p "$dir"
        for spec in "$@"; do
            IFS=: read -r pid comm target <<<"$spec"
            mkdir -p "$dir/$pid/fd"
            printf '%s\n' "$comm" >"$dir/$pid/comm"
            ln -sf 'pipe:[12345]' "$dir/$pid/fd/0"
            ln -sf "$target" "$dir/$pid/fd/9"
        done
    }
    mk_proc "$FIX/proc-free"
    mk_proc "$FIX/proc-daemon" "777:wootingd:$DEV_OK/hidraw5"
    mk_proc "$FIX/proc-browser" "6060:helium:$DEV_OK/hidraw5"
    # The doctor's own defaults read through the sysroot: an empty one.
    mkdir -p "$FIX/root"
    doctor() { # NAME=VALUE... — the healthy fixture set, overridden
        local raw
        set +e
        raw=$(env HASEEN_SYSROOT="$FIX/root" WOOTING_PROC="$FIX/proc-free" WOOTING_UDEV_DIRS="$UDEV_HASEEN" \
            WOOTING_SYSFS_HIDRAW="$SYSFS_OK" WOOTING_DEV_DIR="$DEV_OK" WOOTINGD_BIN="$FIX/wootingd" \
            PATH="$PG:$PATH" "$@" "$REPO/bin/haseen-wooting-doctor" 2>&1)
        STATUS=$?
        set -e
        # shellcheck disable=SC2001  # a glob cannot express the escape ranges
        WOUT=$(sed 's/\x1b\[[0-9;]*m//g' <<<"$raw")
    }
    fake_start doc
    mkdir -p "$XDG_CONFIG_HOME/systemd/user"
    printf '%s\n' "# haseen: setup wooting (plan 099)" '[Unit]' >"$XDG_CONFIG_HOME/systemd/user/wootingd.service"

    doctor
    assert_status "a healthy setup exits 0" 0 "$STATUS"
    healthy=$WOUT
    assert_contains "the tools pass" "$healthy" "socat and jq are installed"
    assert_contains "haseen's rule is found" "$healthy" "PASS  installed: $UDEV_HASEEN/70-wootingd.rules"
    assert_not_contains "haseen's rule starts the daemon" "$healthy" "no rule pulls in wootingd.service"
    assert_contains "haseen's unit is the one that runs" "$healthy" "PASS  haseen's: ~/.config/systemd/user/wootingd.service"
    assert_contains "the command interface is found by its descriptor" "$healthy" "PASS  $DEV_OK/hidraw5 (report descriptor starts 06 55 ff)"
    assert_contains "the analog stream is set aside" "$healthy" "$DEV_OK/hidraw7 is the read-only analog stream (0xFF53)"
    assert_not_contains "another vendor's node is ignored" "$healthy" "hidraw9"
    assert_contains "a usable node passes" "$healthy" "PASS  $DEV_OK/hidraw5 is readable and writable"
    assert_contains "an unheld node passes" "$healthy" "nothing has $DEV_OK/hidraw5 open"
    assert_contains "a live daemon passes" "$healthy" "answers ping on $WOOTINGD_SOCKET"
    assert_contains "the daemon's own view is shown" "$healthy" "sees the keyboard: firmware v2.14.0, 1 selectable profile(s), active slot 0"
    capture "$REPO/bin/haseen-wooting-doctor" --wat
    assert_status "an unknown doctor argument is exit 2" 2 "$STATUS"
    capture haseen wooting doctor --help
    assert_status "haseen wooting doctor --help" 0 "$STATUS"
    assert_eq "haseen wooting doctor reaches the doctor's own help" "Plan 099. Adapted from the owner's t1nk333r/haseen-wooting bin/wooting-doctor" "$(head -n1 <<<"$OUTPUT")"
    assert_not_contains "the help stops before the code" "$OUTPUT" "source "

    doctor WOOTING_UDEV_DIRS="$FIX/udev-empty"
    assert_status "a missing rule is exit 5" 5 "$STATUS"
    assert_contains "the fix is haseen's" "$WOUT" "haseen setup wooting on — installs /etc/udev/rules.d/70-wootingd.rules"
    doctor WOOTING_UDEV_DIRS="$UDEV_ACCESS"
    assert_contains "an access-only rule draws the start warning" "$STATUS|$WOUT" "0|"
    assert_contains "it says nothing starts the daemon" "$WOUT" "no rule pulls in wootingd.service"
    doctor WOOTING_UDEV_DIRS="$UDEV_DECOYS"
    assert_status "comments, .bak files and READMEs are not rules" 5 "$STATUS"
    doctor WOOTING_UDEV_DIRS="$FIX/udev-empty $UDEV_ACCESS"
    assert_status "a rule in the second directory counts" 0 "$STATUS"
    doctor WOOTING_SYSFS_HIDRAW="$SYSFS_ANALOG" WOOTING_DEV_DIR="$FIX/dev-empty"
    assert_contains "a Wooting with no command interface is exit 4" "$STATUS|$WOUT" "4|"
    assert_contains "the analog-only case is precise" "$WOUT" "found 1 Wooting hidraw node(s) but none with usage page 0xFF55 or 0x1337"
    doctor WOOTING_SYSFS_HIDRAW="$SYSFS_STD" WOOTING_DEV_DIR="$FIX/dev-std"
    assert_contains "standard firmware's 0x1337 passes" "$STATUS|$WOUT" "0|"
    assert_contains "the 0x1337 node is found by its prefix" "$WOUT" "PASS  $FIX/dev-std/hidraw2 (report descriptor starts 06 37 13)"
    doctor WOOTING_SYSFS_HIDRAW="$SYSFS_NONE" WOOTING_DEV_DIR="$FIX/dev-empty"
    assert_contains "no Wooting is exit 4 and names the tree" "$STATUS|$WOUT" "4|"
    assert_contains "it names the tree it scanned" "$WOUT" "no Wooting device (vendor 31e3) under $SYSFS_NONE"
    doctor WOOTING_DEV_DIR="$FIX/dev-locked"
    assert_status "an unreadable node is exit 4" 4 "$STATUS"
    assert_contains "the fix is haseen's" "$WOUT" "haseen setup wooting on installs it"
    doctor WOOTING_PROC="$FIX/proc-daemon"
    assert_contains "wootingd owning the node is the design" "$WOUT" "held by wootingd alone"
    doctor WOOTING_PROC="$FIX/proc-browser"
    assert_contains "a browser holding the node is caught" "$WOUT" "WARN  $DEV_OK/hidraw5 is open by: 6060 (helium)"
    assert_status "a foreign holder is a warning, not a failure" 0 "$STATUS"
    doctor FAKE_PROCS="$FIX/procs-bg"
    assert_contains "wooting-bg-service is caught through its truncated comm" "$WOUT" "pid(s) 4343"
    printf '%s\n' "Documentation=https://github.com/t1nk333r/haseen-wooting" 'ExecStart=/x/wootingd' >"$XDG_CONFIG_HOME/systemd/user/wootingd.service"
    doctor
    assert_contains "the plugin's unit is named" "$WOUT" "WARN  ~/.config/systemd/user/wootingd.service is the t1nk33r.wooting plugin's"
    assert_contains "and the take-over offered" "$WOUT" "haseen setup wooting on — takes the rule and the unit over"
    rm -f "$XDG_CONFIG_HOME/systemd/user/wootingd.service"
    doctor
    assert_contains "no unit is a warning" "$WOUT" "WARN  no ~/.config/systemd/user/wootingd.service"

    fake_start doca --absent
    doctor
    assert_contains "a daemon that sees no keyboard is exit 4" "$STATUS|$WOUT" "4|"
    fake_start docs --silent
    doctor WOOTING_IPC_TIMEOUT=0.5
    assert_contains "a wedged daemon is exit 3" "$STATUS|$WOUT" "3|"
    assert_contains "and named" "$WOUT" "nothing answered ping"
    fake_stop_all
    export WOOTINGD_SOCKET="$SANDBOX/gone.sock"
    doctor
    assert_status "no socket is exit 3" 3 "$STATUS"
    assert_contains "the direct probe runs only now" "$WOUT" "direct device probe (wootingd doctor)"
    assert_contains "a healthy probe is reported" "$WOUT" "the device answers — only the daemon is missing"
    doctor FAKE_WOOTINGD_RC=4
    assert_contains "probe exit 4 is no answer" "$WOUT" "another owner is probably holding it"
    doctor FAKE_PROCS="$FIX/procs-daemon"
    assert_contains "a running daemon without a socket vetoes the probe" "$WOUT" "skipped: wootingd is running (pid 777"
    assert_not_contains "nothing is probed then" "$WOUT" "device        : /dev/hidraw5"
    doctor WOOTINGD_BIN="$FIX/none"
    assert_contains "a missing binary names the build" "$WOUT" "tools/build-sidecar.sh builds it (needs cargo)"
    doctor WOOTING_UDEV_DIRS="$FIX/udev-empty" WOOTING_SYSFS_HIDRAW="$SYSFS_NONE" WOOTING_DEV_DIR="$FIX/dev-empty" WOOTINGD_BIN="$FIX/none"
    assert_eq "the first failure in check order wins; every failure is reported" "5|3" "$STATUS|$(grep -c '^   FAIL' <<<"$WOUT")"
    chmod 600 "$FIX/dev-locked/hidraw5"
fi

# --- haseen setup wooting -------------------------------------------------------------
sandbox wt-setup
export HASEEN_INLINE=1
DAEMON="$SANDBOX/bin/wootingd"
mkdir -p "$SANDBOX/bin"
printf '#!/bin/sh\nexit 0\n' >"$DAEMON"
chmod +x "$DAEMON"
export HASEEN_WOOTINGD="$DAEMON"
UNIT="$XDG_CONFIG_HOME/systemd/user/wootingd.service"
WANTS="$XDG_CONFIG_HOME/systemd/user/default.target.wants/wootingd.service"
RULE_SRC="$HASEEN_PATH/default/udev/70-wootingd.rules"
# sysroot NAME [attached] — an empty machine, a Wooting plugged in or not.
sysroot() {
    local root="$SANDBOX/$1"
    mkdir -p "$root/etc/udev/rules.d" "$root/sys/bus/usb/devices"
    if [[ ${2:-} == attached ]]; then
        mkdir -p "$root/sys/bus/usb/devices/1-2"
        printf '31e3\n' >"$root/sys/bus/usb/devices/1-2/idVendor"
    fi
    printf '%s\n' "$root"
}
# recorder — sudo and systemctl that log their argv and run nothing.
recorder() {
    : >"$SANDBOX/sudo.log"
    : >"$SANDBOX/systemctl.log"
    stub sudo "printf '%s\n' \"\$*\" >>'$SANDBOX/sudo.log'; exit 0"
    stub systemctl "printf '%s\n' \"\$*\" >>'$SANDBOX/systemctl.log'; exit 0"
}
# The plugin's copies, as its install.sh leaves them (its marker lines; the
# unit's ExecStart into its own directory).
plugin_rule() { printf '%s\n' '# udev rule for the Wooting Profiles plugin (t1nk33r.wooting).' 'SUBSYSTEM=="hidraw", ATTRS{idVendor}=="31e3", TAG+="uaccess"' >"$1/etc/udev/rules.d/70-wootingd.rules"; }
plugin_unit() {
    mkdir -p "$(dirname "$UNIT")"
    printf '%s\n' '[Unit]' 'Description=Wooting profile daemon (wootingd)' 'Documentation=https://github.com/t1nk333r/haseen-wooting' '[Service]' \
        "ExecStart=\"$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.wooting/daemon/target/release/wootingd\"" >"$UNIT"
}

root="$(sysroot empty)"
export HASEEN_SYSROOT="$root"
capture haseen setup wooting status
assert_contains "status: built daemon" "$OUTPUT" "daemon:    built ($DAEMON)"
assert_contains "status: no rule" "$OUTPUT" "rule:      missing (/etc/udev/rules.d/70-wootingd.rules)"
assert_contains "status: no unit" "$OUTPUT" "unit:      missing (~/.config/systemd/user/wootingd.service)"
assert_contains "status: no keyboard" "$OUTPUT" "keyboard:  not attached"
assert_contains "status: a sysroot cannot say what runs" "$OUTPUT" "running:   unknown"

capture haseen setup wooting on --dry-run
assert_status "on --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "setup wooting on" "$OUTPUT"
assert_contains "it installs the rule as root" "$OUTPUT" "DRYRUN: sudo install -Dm0644 $RULE_SRC /etc/udev/rules.d/70-wootingd.rules"
assert_contains "it reloads udev" "$OUTPUT" "DRYRUN: sudo udevadm control --reload"
assert_contains "it writes the user unit" "$OUTPUT" "DRYRUN: write $UNIT:"
assert_contains "the unit runs the installed daemon" "$OUTPUT" "| ExecStart=\"$DAEMON\""
assert_contains "the unit binds to the keyboard" "$OUTPUT" "| BindsTo=sys-subsystem-usb-devices-wooting.device"
assert_not_contains "the unit is never enabled" "$OUTPUT" "[Install]"
assert_contains "the user manager reloads" "$OUTPUT" "DRYRUN: systemctl --user daemon-reload"
assert_not_contains "no keyboard, no trigger" "$OUTPUT" "udevadm trigger"
assert_eq "the dry run wrote nothing" no "$([[ -e $UNIT ]] && echo yes || echo no)"

capture haseen setup wooting on </dev/null
assert_status "without --yes and no answer it declines" 1 "$STATUS"
assert_eq "a declined run writes nothing" no "$([[ -e $UNIT ]] && echo yes || echo no)"

root="$(sysroot attached attached)"
export HASEEN_SYSROOT="$root"
recorder
capture haseen setup wooting on --yes
assert_status "on succeeds" 0 "$STATUS"
log="$(cat "$SANDBOX/sudo.log")"
assert_eq "root does exactly: install, reload, trigger the attached keyboard" \
    "install -Dm0644 $RULE_SRC /etc/udev/rules.d/70-wootingd.rules
udevadm control --reload
udevadm trigger --action=change --parent-match=/sys/bus/usb/devices/1-2" "$log"
assert_eq "the user manager reloads, then the one unit restarts" "--user daemon-reload
--user restart wootingd.service" "$(cat "$SANDBOX/systemctl.log")"
assert_eq "the unit is haseen's, from the template" "$(sed "s|^ExecStart=@WOOTINGD@\$|ExecStart=\"$DAEMON\"|" "$HASEEN_PATH/default/systemd/wootingd.service")" "$(cat "$UNIT")"
cp "$RULE_SRC" "$root/etc/udev/rules.d/70-wootingd.rules"
recorder
capture haseen setup wooting on --yes
assert_contains "a second on has nothing to do" "$STATUS|$OUTPUT" "0|[*] Wooting is already on"
assert_eq "and runs nothing" "|" "$(cat "$SANDBOX/sudo.log")|$(cat "$SANDBOX/systemctl.log")"
capture haseen setup wooting status
assert_contains "status: haseen's rule" "$OUTPUT" "rule:      haseen's (/etc/udev/rules.d/70-wootingd.rules)"
assert_contains "status: haseen's unit" "$OUTPUT" "unit:      haseen's (~/.config/systemd/user/wootingd.service)"
assert_contains "status: keyboard attached" "$OUTPUT" "keyboard:  attached"

capture haseen setup wooting off --dry-run
assert_dry_pure "setup wooting off" "$OUTPUT"
assert_contains "off --dry-run stops the daemon" "$OUTPUT" "DRYRUN: systemctl --user stop wootingd.service"
assert_contains "off --dry-run removes the unit" "$OUTPUT" "DRYRUN: rm -f -- $UNIT"
assert_contains "off --dry-run removes the rule as root" "$OUTPUT" "DRYRUN: sudo rm -f -- /etc/udev/rules.d/70-wootingd.rules"
assert_eq "the dry run kept the unit" yes "$([[ -e $UNIT ]] && echo yes || echo no)"
recorder
capture haseen setup wooting off --yes
assert_status "off succeeds" 0 "$STATUS"
assert_eq "off removes exactly the rule, as root" "rm -f -- /etc/udev/rules.d/70-wootingd.rules
udevadm control --reload" "$(cat "$SANDBOX/sudo.log")"
assert_eq "and the unit" no "$([[ -e $UNIT ]] && echo yes || echo no)"
assert_not_contains "with nothing taken over, off names no saved copies" "$OUTPUT" "copies that 'on' replaced"
rm -f "$root/etc/udev/rules.d/70-wootingd.rules"
capture haseen setup wooting off --yes
assert_contains "a second off is already off" "$STATUS|$OUTPUT" "0|[*] Wooting is already off"

# --- coexistence: the t1nk33r.wooting plugin's rule and unit are taken over ---------
root="$(sysroot takeover attached)"
export HASEEN_SYSROOT="$root"
plugin_rule "$root"
plugin_unit
mkdir -p "$(dirname "$WANTS")" "$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.wooting"
ln -s "$UNIT" "$WANTS"
printf 'fixture\n' >"$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.wooting/marker"
plugin_dir="$(find "$XDG_CONFIG_HOME/omarchy" -exec stat -c '%n %s %Y' {} + | sort)"
rule_before="$(cat "$root/etc/udev/rules.d/70-wootingd.rules")"
unit_before="$(cat "$UNIT")"
capture haseen setup wooting status
assert_contains "status names the plugin's rule" "$OUTPUT" "rule:      the t1nk33r.wooting plugin's"
assert_contains "status names the plugin's unit" "$OUTPUT" "unit:      the t1nk33r.wooting plugin's"
assert_contains "status names the always-on start" "$OUTPUT" "always-on: ~/.config/systemd/user/default.target.wants/wootingd.service"
capture haseen setup wooting on --dry-run
assert_dry_pure "take-over dry run" "$OUTPUT"
assert_contains "the plan saves the plugin's rule first" "$OUTPUT" "DRYRUN: write $HOME/.local/state/haseen/wooting/replaced-"
assert_eq "the dry run left the plugin's unit" "$unit_before" "$(cat "$UNIT")"
recorder
capture haseen setup wooting on --yes
assert_status "take-over succeeds" 0 "$STATUS"
saved="$(find "$HOME/.local/state/haseen/wooting" -mindepth 1 -maxdepth 1 -name 'replaced-*' | head -n1)"
assert_eq "the plugin's rule is saved as it was" "$rule_before" "$(cat "$saved/70-wootingd.rules")"
assert_eq "the plugin's unit is saved as it was" "$unit_before" "$(cat "$saved/wootingd.service")"
assert_contains "the unit is now haseen's" "$(cat "$UNIT")" "ExecStart=\"$DAEMON\""
assert_not_contains "the plugin's build is no longer what runs" "$(cat "$UNIT")" "t1nk33r.wooting"
assert_eq "the always-on start is gone" no "$([[ -L $WANTS ]] && echo yes || echo no)"
assert_contains "haseen's rule replaces the plugin's" "$(cat "$SANDBOX/sudo.log")" "install -Dm0644 $RULE_SRC /etc/udev/rules.d/70-wootingd.rules"
assert_contains "one unit restarts, so the old daemon stops before haseen's starts" "$(cat "$SANDBOX/systemctl.log")" "--user restart wootingd.service"
assert_eq "the plugin's directory is untouched" "$plugin_dir" "$(find "$XDG_CONFIG_HOME/omarchy" -exec stat -c '%n %s %Y' {} + | sort)"
# off after the take-over says exactly where the plugin's copies are and how
# its own daemon comes back; it copies nothing back.
recorder
capture haseen setup wooting off --yes
assert_status "off after the take-over succeeds" 0 "$STATUS"
assert_contains "off names the exact saved directory and its files" "$OUTPUT" \
    "the t1nk33r.wooting plugin's copies that 'on' replaced are in ${saved/#$HOME/\~}/: 70-wootingd.rules wootingd.service"
assert_contains "and the restore step, the plugin's own installer" "$OUTPUT" \
    "to run the plugin's own wootingd again, run its installer: ~/.config/omarchy/plugins/t1nk33r.wooting/install.sh"
assert_eq "off removed haseen's unit and wrote nothing back" no "$([[ -e $UNIT ]] && echo yes || echo no)"
assert_eq "the saved copies stay as they were" "$rule_before|$unit_before" "$(cat "$saved/70-wootingd.rules")|$(cat "$saved/wootingd.service")"
assert_eq "the plugin's directory is still untouched" "$plugin_dir" "$(find "$XDG_CONFIG_HOME/omarchy" -exec stat -c '%n %s %Y' {} + | sort)"

# off leaves what is not haseen's alone.
root="$(sysroot leave)"
export HASEEN_SYSROOT="$root"
plugin_rule "$root"
plugin_unit
before="$(cat "$UNIT")|$(cat "$root/etc/udev/rules.d/70-wootingd.rules")"
recorder
capture haseen setup wooting off --yes
assert_contains "off with only the plugin's copies is already off" "$OUTPUT" "Wooting is already off"
assert_contains "and says it left them" "$OUTPUT" "is the t1nk33r.wooting plugin's: left alone"
assert_eq "both are unchanged" "$before" "$(cat "$UNIT")|$(cat "$root/etc/udev/rules.d/70-wootingd.rules")"
assert_eq "nothing ran" "" "$(cat "$SANDBOX/sudo.log")"

# Someone else's file of either name is refused, not replaced.
root="$(sysroot other)"
export HASEEN_SYSROOT="$root"
printf '%s\n' 'SUBSYSTEM=="usb", ATTR{idVendor}=="31e3", MODE="0666"' >"$root/etc/udev/rules.d/70-wootingd.rules"
rm -f "$UNIT"
recorder
capture haseen setup wooting on --yes
assert_contains "a foreign rule is refused" "$STATUS|$OUTPUT" "1|Error: /etc/udev/rules.d/70-wootingd.rules is not haseen's or the t1nk33r.wooting plugin's"
assert_eq "and nothing is written" "|no" "$(cat "$SANDBOX/sudo.log")|$([[ -e $UNIT ]] && echo yes || echo no)"
rm -f "$root/etc/udev/rules.d/70-wootingd.rules"
mkdir -p "$(dirname "$UNIT")"
printf '[Service]\nExecStart=/usr/bin/true\n' >"$UNIT"
capture haseen setup wooting on --yes
assert_contains "a foreign unit is refused" "$STATUS|$OUTPUT" "1|Error: ~/.config/systemd/user/wootingd.service is not haseen's"
assert_eq "and kept" "$(printf '[Service]\nExecStart=/usr/bin/true')" "$(cat "$UNIT")"
rm -f "$UNIT"

# No daemon built: a plan with a warning, a real run refused.
export HASEEN_WOOTINGD="$SANDBOX/none/wootingd"
capture haseen setup wooting on --dry-run
assert_contains "a dry run warns that the daemon is missing" "$STATUS|$OUTPUT" "0|"
assert_contains "the warning says a real run stops" "$OUTPUT" "a real run stops here"
capture haseen setup wooting on --yes
assert_contains "a real run without the daemon is refused" "$STATUS|$OUTPUT" "1|Error: wootingd is not built"
assert_contains "and says how to build it" "$OUTPUT" "tools/build-sidecar.sh"
unset HASEEN_WOOTINGD HASEEN_SYSROOT

# --- the migration ----------------------------------------------------------------------
sandbox wt-migrate
UNIT="$XDG_CONFIG_HOME/systemd/user/wootingd.service"
run_migration() { capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIG" "$@" bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIG"; }
CFG="$XDG_CONFIG_HOME/haseen/shell.json"
put() { mkdir -p "$XDG_CONFIG_HOME/haseen" && printf '%s\n' "$1" >"$CFG"; }
q() { jq -c "$1" "$CFG"; }
assert_eq "the migration is shipped" yes "$([[ -r $HASEEN_PATH/migrations/$MIG ]] && echo yes || echo no)"
# The plan 093 migration was the newest when this was written; this one must
# run after it. Later plans' migrations may sort after this one.
assert_eq "the migration sorts after 1792531693-omarchy-path.sh" "1792531693-omarchy-path.sh $MIG" \
    "$(cd "$HASEEN_PATH/migrations" && ls 1792531693-omarchy-path.sh 17925[0-9][0-9][0-9][0-9][0-9]-adopt-wooting.sh | LC_ALL=C sort | paste -sd' ')"
put '{"bar":{"right":["haseen.tray","t1nk33r.wooting",{"id":"x.inline"},"haseen.clock"],"overflow":["t1nk33r.wooting"]},
 "services":["haseen.pager","t1nk33r.wooting"],
 "plugins":{"t1nk33r.wooting":{"enabled":true,"settings":{"id":"t1nk33r.wooting","showName":"false","nameMaxChars":8}},"me.x":{"enabled":false}}}'
mkdir -p "$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.wooting"
printf 'fixture\n' >"$XDG_CONFIG_HOME/omarchy/plugins/t1nk33r.wooting/marker"
olds="$(find "$XDG_CONFIG_HOME/omarchy" -type f -exec sha256sum {} + | sort)"
before="$(cat "$CFG")"
run_migration DRY_RUN=true
assert_status "dry run exits 0" 0 "$STATUS"
assert_dry_pure "migration" "$OUTPUT"
assert_contains "dry run shows the write" "$OUTPUT" "DRYRUN: write"
assert_eq "dry run changes nothing" "$before" "$(cat "$CFG")"
run_migration
assert_status "migration exits 0" 0 "$STATUS"
assert_contains "it says what it did" "$OUTPUT" "t1nk33r.wooting is now haseen.wooting"
assert_eq "bar.right: the new id in place, a non-string entry kept" '["haseen.tray","haseen.wooting",{"id":"x.inline"},"haseen.clock"]' "$(q .bar.right)"
assert_eq "bar.overflow: re-pointed" '["haseen.wooting"]' "$(q .bar.overflow)"
assert_eq "services: dropped (no service kind)" '["haseen.pager"]' "$(q .services)"
assert_eq "plugins: the declared settings move, Omarchy's id does not" '{"enabled":true,"settings":{"showName":"false","nameMaxChars":8}}' "$(q '.plugins["haseen.wooting"]')"
assert_eq "plugins: the old entry is gone" 'false' "$(q '.plugins | has("t1nk33r.wooting")')"
assert_eq "the rest survives" 'false' "$(q '.plugins["me.x"].enabled')"
assert_eq "the plugin's directory is untouched" "$olds" "$(find "$XDG_CONFIG_HOME/omarchy" -type f -exec sha256sum {} + | sort)"
assert_eq "no staging file left behind" "" "$(find "$XDG_CONFIG_HOME/haseen" -maxdepth 1 -name 'shell.json.new*')"
after="$(cat "$CFG")"
run_migration
assert_eq "re-run is a silent no-op" "0|$after|" "$STATUS|$(cat "$CFG")|$OUTPUT"
put '{"bar":{"left":["haseen.wooting","t1nk33r.wooting"]},"plugins":{"t1nk33r.wooting":{"enabled":false,"settings":{"showName":true,"hideWhenAbsent":false}},"haseen.wooting":{"settings":{"showName":false}}}}'
run_migration
assert_eq "an id once, at its first place" '["haseen.wooting"]' "$(q .bar.left)"
assert_eq "the existing new entry wins key by key" '{"enabled":false,"settings":{"showName":false,"hideWhenAbsent":false}}' "$(q '.plugins["haseen.wooting"]')"
# Only haseen.wooting is de-duplicated: the user's own repeats, strings and
# identical objects alike, stay exactly where they were.
put '{"bar":{"right":["haseen.clock","t1nk33r.wooting",{"id":"x.inline"},"haseen.clock",{"id":"x.inline"},"haseen.wooting","t1nk33r.wooting"]},
 "services":["haseen.pager","haseen.pager",{"id":"s"},{"id":"s"},"t1nk33r.wooting"]}'
run_migration
assert_status "a section with the user's own duplicates migrates" 0 "$STATUS"
assert_eq "bar: the new id once, every other entry and its repeats kept in order" \
    '["haseen.clock","haseen.wooting",{"id":"x.inline"},"haseen.clock",{"id":"x.inline"}]' "$(q .bar.right)"
assert_eq "services: only the old id goes, the user's repeats stay" \
    '["haseen.pager","haseen.pager",{"id":"s"},{"id":"s"}]' "$(q .services)"
plugin_unit
unit_before="$(stat -c '%s %Y' "$UNIT") $(sha256sum <"$UNIT")"
put '{"bar":{"right":["t1nk33r.wooting"]}}'
run_migration
assert_contains "the plugin's unit still running its build is pointed out" "$OUTPUT" "haseen setup wooting on takes it over"
assert_eq "the unit itself is not touched" "$unit_before" "$(stat -c '%s %Y' "$UNIT") $(sha256sum <"$UNIT")"
put '{"bar":{"right":["haseen.clock"]}}'
before="$(cat "$CFG")"
run_migration
assert_eq "no old id: the file is untouched" "$before|" "$(cat "$CFG")|$OUTPUT"
printf '{"bar":' >"$CFG"
run_migration
assert_eq "an invalid shell.json fails and is left" '1|{"bar":' "$STATUS|$(cat "$CFG")"
rm -f "$CFG"
run_migration
assert_eq "no shell.json: nothing written" "0|no" "$STATUS|$([[ -e $CFG ]] && echo yes || echo no)"

# --- the widget and panel in the real engine ---------------------------------------------
if [[ ! -x $QS_BIN ]] || ! command -v dbus-run-session >/dev/null || ! command -v python3 >/dev/null; then
    engine_skip "qs, dbus-run-session or python3 missing; engine scenarios"
else
    sandbox wt-engine
    h="$SANDBOX/shell"
    mkdir -p "$h"
    for module in Haseen Compat Ui Commons; do ln -s "$HASEEN_PATH/shell/$module" "$h/$module"; done
    ln -s "$HASEEN_PATH/shell/plugins" "$h/plugins"
    sock="$XDG_RUNTIME_DIR/e.sock"
    cat >"$h/shell.qml" <<'QML'
import QtQuick
import Quickshell
import "plugins/haseen.wooting" as W
ShellRoot {
    FloatingWindow {
        visible: true; implicitWidth: 1100; implicitHeight: 700
        W.Widget { id: w; height: 28; pluginId: "haseen.wooting"; settings: ({}) }
        W.Panel { id: p; y: 40; pluginId: "haseen.wooting"; settings: ({}) }
    }
    function line(tag, o) { console.warn("RESULT " + tag + " " + JSON.stringify(o)); }
    Timer {
        interval: 600; running: true
        onTriggered: { line("before", { shown: w.visible, width: w.implicitWidth }); t2.running = true; }
    }
    Timer {
        id: t2; interval: 3000
        onTriggered: {
            line("after", { shown: w.visible, text: w.text, profiles: p.keyboard.profiles.map(x => x.name), active: p.keyboard.active });
            p.choose(2);
            t3.running = true;
        }
    }
    Timer {
        id: t3; interval: 1200
        onTriggered: {
            line("switched", { text: w.text, widget: w.keyboard.active, panel: p.keyboard.active });
            p.showLayout = true;
            t4.running = true;
        }
    }
    Timer {
        id: t4; interval: 1500
        onTriggered: {
            const b = p.layoutView;
            line("layout", { keys: b ? b.keys.length : -1, model: b ? b.device.model : null, pressed: b ? b.pressedCount : -1 });
            Quickshell.execDetached(["kill", Quickshell.env("FAKE_PID")]);
            t5.running = true;
        }
    }
    Timer {
        id: t5; interval: 1500
        onTriggered: { line("gone", { shown: w.visible, width: w.implicitWidth, panelPresent: p.keyboard.present }); Qt.quit(); }
    }
}
QML
    # The daemon appears a second after the shell starts, as wootingd does on
    # plug-in: the widget must notice through its socket watch, not a poll.
    (
        sleep 1.5
        exec python3 -I "$FAKE" "$sock" --profiles 4 --analog-keys '[{"row":2,"col":2,"code":26,"value":0.5,"actuated":false}]'
    ) </dev/null >/dev/null 2>&1 &
    fake_pid=$!
    FAKE_PIDS+=("$fake_pid")
    capture timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- \
        env QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software QT_NO_XDG_DESKTOP_PORTAL=1 \
        WOOTINGD_SOCKET="$sock" FAKE_PID="$fake_pid" "$QS_BIN" -p "$h"
    if [[ $STATUS == 0 ]]; then _pass; else _fail "the harness completes in the real engine (exit $STATUS)" "$(tail -n 20 <<<"$OUTPUT")"; fi
    result() { sed -n "s/^.*RESULT $1 //p" <<<"$OUTPUT" | head -n1; }
    assert_eq "no keyboard: the widget takes no room" '{"shown":false,"width":0}' "$(result before)"
    assert_eq "the daemon appears: the widget shows the short name, the panel lists the stored profiles" \
        '{"shown":true,"text":"Typing","profiles":["1 Typing Profile","Profile 2","Profile 3","Profile 4"],"active":0}' "$(result after)"
    assert_eq "a switch from the panel reaches the bar through the daemon" '{"text":"Profile 3","widget":2,"panel":2}' "$(result switched)"
    assert_eq "the layout view draws the 60HE+ and its key travel" '{"keys":61,"model":"Wooting 60HE+","pressed":1}' "$(result layout)"
    assert_eq "the daemon goes: the widget hides again" '{"shown":false,"width":0,"panelPresent":false}' "$(result gone)"
    assert_not_contains "no QML errors" "$OUTPUT" "plugins/haseen.wooting/"
    fake_stop_all
fi
