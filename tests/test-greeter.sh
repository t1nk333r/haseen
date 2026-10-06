# shellcheck shell=bash
# The login screen: the greetd config haseen writes, who it offers, which
# sessions it finds, and — against a fake greetd socket — the authentication
# handshake and the session it finally launches.
sandbox greeter

sysroot="$SANDBOX/sysroot"
mkdir -p "$sysroot/etc/haseen" "$sysroot/etc/greetd" \
    "$sysroot/usr/share/wayland-sessions" "$sysroot/usr/share/xsessions"
export HASEEN_SYSROOT="$sysroot"

cat >"$sysroot/etc/passwd" <<'EOF'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1::/:/usr/bin/nologin
nobody:x:65534:65534:Nobody:/:/usr/bin/nologin
t1nk33r:x:1000:1000:Owner Name,,,:/home/t1nk33r:/bin/bash
zara:x:1001:1001::/home/zara:/usr/bin/fish
svc:x:1002:1002:A service:/var/empty:/bin/bash
locked:x:1003:1003::/home/locked:/usr/bin/false
sys:x:60001:60001::/home/sys:/bin/bash
EOF
cat >"$sysroot/usr/share/wayland-sessions/hyprland-uwsm.desktop" <<'EOF'
[Desktop Entry]
Name=Hyprland (uwsm-managed)
Exec=uwsm start -- hyprland.desktop
Type=Application
EOF
cat >"$sysroot/usr/share/xsessions/i3.desktop" <<'EOF'
[Desktop Entry]
Name=i3
Exec=i3 %U
Type=Application
EOF

# The graphical greeter checks that it has a compositor and a shell to run.
# The CI container has neither, and this part of the test is about the config.
stub Hyprland 'exit 0'
stub qs 'exit 0'

# --- the greetd config haseen writes ------------------------------------------
capture haseen setup greeter status
assert_contains "tuigreet is the default" "$OUTPUT" "greeter:   tuigreet"
assert_contains "the users are the humans" "$OUTPUT" "t1nk33r zara"
assert_not_contains "a system account is not offered" "$OUTPUT" "nobody"
assert_not_contains "nor one without a login shell" "$OUTPUT" "locked"
assert_not_contains "nor one without a real home" "$OUTPUT" "svc"
assert_contains "the sessions are listed" "$OUTPUT" "hyprland-uwsm"

capture haseen setup greeter haseen --dry-run --yes
assert_dry_pure "greeter switch dry run" "$OUTPUT"
assert_contains "it plans the choice file" "$OUTPUT" "/etc/haseen/greeter"
assert_contains "and the greetd config" "$OUTPUT" "/etc/greetd/config.toml"
assert_contains "pointing greetd at haseen-greeter by absolute path" "$OUTPUT" "command = \"$REPO/bin/haseen-greeter\""
assert_eq "a dry run changes nothing" "" "$(cat "$sysroot/etc/haseen/greeter" 2>/dev/null || true)"

echo haseen >"$sysroot/etc/haseen/greeter"
capture haseen setup greeter status
assert_contains "the choice is read back" "$OUTPUT" "greeter:   haseen"
capture haseen setup greeter tuigreet --dry-run --yes
assert_contains "switching back plans tuigreet" "$OUTPUT" "tuigreet --time --remember"
assert_contains "and orders greetd after the splash" "$OUTPUT" "plymouth-quit-wait.service"

# --- taking over from another display manager ----------------------------------
mkdir -p "$sysroot/etc/systemd/system"
ln -sfn /usr/lib/systemd/system/sddm.service "$sysroot/etc/systemd/system/display-manager.service"
capture haseen setup greeter haseen --dry-run --yes
assert_contains "SDDM is named as what gets replaced" "$OUTPUT" "sddm.service is the display manager now"
assert_contains "greetd and the fallback greeter are installed" "$OUTPUT" "greetd greetd-tuigreet"
assert_contains "SDDM is disabled" "$OUTPUT" "systemctl disable sddm.service"
assert_contains "greetd is enabled" "$OUTPUT" "systemctl enable greetd.service"
assert_not_contains "but nothing is started under the running session" "$OUTPUT" "enable --now"
assert_contains "and the way back is printed" "$OUTPUT" "sudo systemctl enable sddm.service"
DISABLE_AT="$(grep -n 'systemctl disable sddm' <<<"$OUTPUT" | cut -d: -f1)"
ENABLE_AT="$(grep -n 'systemctl enable greetd' <<<"$OUTPUT" | cut -d: -f1)"
assert_eq "SDDM lets go of display-manager.service before greetd takes it" true \
    "$([[ ${DISABLE_AT:-0} -lt ${ENABLE_AT:-0} ]] && echo true || echo false)"

ln -sfn /usr/lib/systemd/system/greetd.service "$sysroot/etc/systemd/system/display-manager.service"
capture haseen setup greeter haseen --dry-run --yes
assert_not_contains "with greetd already in place nothing is disabled" "$OUTPUT" "systemctl disable"
assert_not_contains "or re-enabled" "$OUTPUT" "systemctl enable greetd"
rm -f "$sysroot/etc/systemd/system/display-manager.service"

# --- autologin: the disk password at the splash is the authentication ----------
capture haseen setup greeter autologin t1nk33r --dry-run --yes
assert_dry_pure "autologin dry run" "$OUTPUT"
assert_contains "it records the user" "$OUTPUT" "/etc/haseen/autologin"
assert_contains "and greetd starts a session at boot" "$OUTPUT" "[initial_session]"
assert_contains "as that user" "$OUTPUT" 'user = "t1nk33r"'
assert_contains "running the desktop" "$OUTPUT" 'command = "uwsm start hyprland.desktop"'
assert_contains "while later logins still reach the greeter" "$OUTPUT" "[default_session]"

capture haseen setup greeter autologin nobody --dry-run --yes
assert_status "a system account cannot be autologged in" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "no such user"
capture haseen setup greeter autologin ghost --dry-run --yes
assert_status "nor can one that does not exist" 1 "$STATUS"

echo t1nk33r >"$sysroot/etc/haseen/autologin"
capture haseen setup greeter status
assert_contains "status shows who is logged in at boot" "$OUTPUT" "autologin: t1nk33r"
capture haseen setup greeter autologin off --dry-run --yes
assert_contains "turning it off removes the record" "$OUTPUT" "/etc/haseen/autologin"
assert_not_contains "and the config loses its initial session" "$OUTPUT" "[initial_session]"
rm -f "$sysroot/etc/haseen/autologin"

# --- the compositor config the launcher generates ------------------------------
capture haseen greeter --print-config
assert_status "the launcher can show its config" 0 "$STATUS"
assert_contains "it runs the greeter shell" "$OUTPUT" "shell/greeter"
assert_contains "and quits the compositor when it exits, in Lua dispatcher form" "$OUTPUT" "hyprctl dispatch 'hl.dsp.exit()'"
assert_contains "animations are off on a login screen" "$OUTPUT" "animations = { enabled = false }"
assert_contains "the config is Lua, not the hyprlang format 0.57 drops" "$OUTPUT" "hl.config({"
assert_contains "and the greeter starts once, at compositor start" "$OUTPUT" 'hl.on("hyprland.start"' 
capture haseen greeter
assert_status "without greetd in the environment it refuses" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "GREETD_SOCK"

# --- the parsers, under the Qt JS engine ---------------------------------------
QML=/usr/lib/qt6/bin/qml
H="$SANDBOX/js"
mkdir -p "$H"
cat >"$H/Units.qml" <<EOF
import QtQuick
import "file://$HASEEN_PATH/shell/greeter/Greeter.js" as G

Item {
    function eq(name, want, got) {
        const w = JSON.stringify(want), g = JSON.stringify(got);
        console.log((w === g ? "UNIT-PASS " : "UNIT-FAIL ") + name + (w === g ? "" : " want " + w + " got " + g));
        if (w !== g) failures++;
    }
    property int failures: 0
    Component.onCompleted: {
        const users = G.parseUsers("$(sed 's/"/\\"/g; s/$/\\n/' "$sysroot/etc/passwd" | tr -d '\n')");
        eq("users: only humans", ["t1nk33r", "zara"], users.map(u => u.name));
        eq("users: GECOS is the display name", "Owner Name", users[0].display);
        eq("users: no GECOS falls back to the name", "zara", users[1].display);

        const session = G.parseSession("hyprland-uwsm", "[Desktop Entry]\nName=Hyprland\nExec=uwsm start -- hyprland.desktop\n");
        eq("session: name and exec", ["hyprland-uwsm", "Hyprland"], [session.id, session.name]);
        eq("session: hidden is skipped", null, G.parseSession("x", "[Desktop Entry]\nName=x\nExec=x\nHidden=true\n"));
        eq("session: no Exec is not a session", null, G.parseSession("x", "[Desktop Entry]\nName=x\n"));
        eq("session: another group is ignored", null, G.parseSession("x", "[Desktop Action y]\nExec=x\n"));

        eq("sessions: an id appears once", ["a"], G.parseSessions([{id: "a", name: "A", exec: "a"}, {id: "a", name: "B", exec: "b"}]).map(s => s.id));

        eq("default session: haseen's, not the first alphabetically", 2, G.preferredSessionIndex([{id: "awesome"}, {id: "omarchy"}, {id: "hyprland-uwsm"}, {id: "hyprland"}]));
        eq("default session: plain Hyprland without uwsm's entry", 1, G.preferredSessionIndex([{id: "omarchy"}, {id: "hyprland"}]));
        eq("default session: the first one when neither exists", 0, G.preferredSessionIndex([{id: "i3"}]));

        eq("command: field codes are dropped", ["i3"], G.commandFor("i3 %U"));
        eq("command: quotes hold a word together", ["sh", "-c", "a b"], G.commandFor("sh -c 'a b'"));
        eq("command: argv, not a shell string", ["uwsm", "start", "--", "hyprland.desktop"], G.commandFor("uwsm start -- hyprland.desktop"));

        eq("memory: garbage reads as empty", ["", {}], [G.readMemory("nonsense").lastUser, G.readMemory("nonsense").sessions]);
        const memory = G.withMemory(G.readMemory("{}"), "zara", "i3");
        eq("memory: the user and their session are kept", ["zara", "i3"], [memory.lastUser, memory.sessions.zara]);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 60 "$QML" "$H/Units.qml" 2>&1)"
    set -e
    assert_contains "the greeter parsers run" "$units" "UNIT-PASS users: only humans"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "greeter js unit count" 16 "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the real handshake, against a fake greetd ---------------------------------
# greetd's protocol is one JSON object per message, each prefixed with its
# length as a native-endian int32. The fake server answers the way greetd does
# and records what the greeter sent.
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: quickshell not installed; the greetd handshake is not exercised" >&2
else
    cat >"$SANDBOX/fake-greetd.py" <<'PY'
import json, os, socket, struct, sys, threading

path, log = sys.argv[1], sys.argv[2]
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(path)
server.listen(1)

def read(conn):
    head = conn.recv(4)
    if len(head) < 4:
        return None
    (length,) = struct.unpack("=i", head)
    body = b""
    while len(body) < length:
        chunk = conn.recv(length - len(body))
        if not chunk:
            return None
        body += chunk
    return json.loads(body)

def write(conn, message):
    body = json.dumps(message).encode()
    conn.sendall(struct.pack("=i", len(body)) + body)

def serve():
    conn, _ = server.accept()
    with open(log, "a") as record:
        while True:
            request = read(conn)
            if request is None:
                return
            record.write(json.dumps(request) + "\n")
            record.flush()
            kind = request.get("type")
            if kind == "create_session":
                # greetd asks PAM's questions; this one asks for a password.
                write(conn, {"type": "auth_message", "auth_message_type": "secret",
                             "auth_message": "Password:"})
            elif kind == "post_auth_message_response":
                if request.get("response") == "correct horse":
                    write(conn, {"type": "success"})
                else:
                    write(conn, {"type": "error", "error_type": "auth_error",
                                 "description": "Login incorrect"})
            elif kind == "start_session":
                write(conn, {"type": "success"})
                return
            else:
                write(conn, {"type": "success"})

threading.Thread(target=serve, daemon=True).start()
print("ready", flush=True)
threading.Event().wait(60)
PY
    # Unix socket paths stop at ~108 bytes, and $SANDBOX is already long.
    run_dir="$(mktemp -d /tmp/haseen-greeter.XXXXXX)"
    sock="$run_dir/greetd.sock"
    record="$SANDBOX/greetd.log"
    : >"$record"
    python3 "$SANDBOX/fake-greetd.py" "$sock" "$record" >"$SANDBOX/fake.log" 2>&1 &
    fake=$!
    trap 'kill "$fake" 2>/dev/null || true' EXIT
    for ((i = 0; i < 100; i++)); do
        [[ -S $sock ]] && break
        sleep 0.05
    done

    # A greeter home with the sessions and users of the fixture: the shell runs
    # getent and reads the session directories through the stub PATH.
    greeter_home="$SANDBOX/greeter-home"
    mkdir -p "$greeter_home/.local/state" "$SANDBOX/stubs"
    stub getent "cat '$sysroot/etc/passwd'"
    cat >"$SANDBOX/stubs/sh" <<EOF
#!/bin/sh
# The session scan runs through sh -c; answer with the fixture's sessions.
for f in "$sysroot"/usr/share/wayland-sessions/*.desktop "$sysroot"/usr/share/xsessions/*.desktop; do
    [ -r "\$f" ] && printf '=== %s\n' "\$f" && cat "\$f"
done
EOF
    chmod +x "$SANDBOX/stubs/sh"

    # The card, not shell.qml: a layer surface needs a running compositor, and
    # the authentication is in the card. tools/smoke-greeter.sh runs the whole
    # shell.qml under a headless Hyprland.
    mkdir -p "$SANDBOX/driver"
    ln -sfn "$HASEEN_PATH/shell/greeter" "$SANDBOX/driver/greetersrc"
    cat >"$SANDBOX/driver/shell.qml" <<EOF
import QtQuick
import Quickshell
import "greetersrc" as Greeter

ShellRoot {
    // The login, with no window: a layer surface needs a compositor, and the
    // authentication does not. tools/smoke-greeter.sh draws the real screen.
    Greeter.GreeterSession {}
}
EOF

    env -u WAYLAND_DISPLAY -u DISPLAY GREETD_SOCK="$sock" \
        HOME="$greeter_home" XDG_STATE_HOME="$greeter_home/.local/state" \
        XDG_RUNTIME_DIR="$run_dir" QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        QT_QPA_PLATFORMTHEME='' QT_NO_XDG_DESKTOP_PORTAL=1 PATH="$SANDBOX/stubs:$PATH" \
        timeout 45 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- \
        "$QS_BIN" -p "$SANDBOX/driver" >"$SANDBOX/greeter.log" 2>&1 &
    shell_pid=$!
    sleep 6

    # pgrep -f would match the `timeout`/`dbus-run-session` wrappers too; the
    # shell is the one whose argv starts with the quickshell binary.
    pid="$(pgrep -f "^$QS_BIN -p $SANDBOX/driver" | head -1 || true)"
    if [[ -z $pid ]]; then
        _fail "the greeter did not start" "$(tail -5 "$SANDBOX/greeter.log")"
    else
        capture env XDG_RUNTIME_DIR="$run_dir" "$QS_BIN" ipc --pid "$pid" call greeter state
        state="$OUTPUT"
        assert_contains "the greeter lists the machine's users" "$state" "t1nk33r"
        assert_not_contains "and not the system accounts" "$state" "nobody"
        assert_contains "it found a session" "$state" "hyprland-uwsm"

        # A wrong answer must come back as a failure, not a login.
        env XDG_RUNTIME_DIR="$run_dir" "$QS_BIN" ipc --pid "$pid" call greeter login "wrong" >/dev/null 2>&1 || true
        sleep 2
        capture env XDG_RUNTIME_DIR="$run_dir" "$QS_BIN" ipc --pid "$pid" call greeter state
        assert_contains "a wrong password is reported" "$OUTPUT" "Login incorrect"

        env XDG_RUNTIME_DIR="$run_dir" "$QS_BIN" ipc --pid "$pid" call greeter login "correct horse" >/dev/null 2>&1 || true
        sleep 3
        sent="$(cat "$record")"
        assert_contains "the greeter created a session for the user" "$sent" '"type": "create_session"'
        assert_contains "with the user it shows" "$sent" '"username": "t1nk33r"'
        assert_contains "it answered the password prompt" "$sent" '"type": "post_auth_message_response"'
        assert_contains "and started the session it offered" "$sent" '"type": "start_session"'
        assert_contains "with an argv, not a shell string" "$sent" '"uwsm", "start", "--", "hyprland.desktop"'
        assert_eq "the session it picked is remembered" "hyprland-uwsm" \
            "$(jq -r '.sessions.t1nk33r' "$greeter_home/.local/state/haseen-greeter.json" 2>/dev/null || echo missing)"
    fi
    kill "$shell_pid" "$fake" 2>/dev/null || true
    rm -rf "$run_dir"
    trap - EXIT
fi
