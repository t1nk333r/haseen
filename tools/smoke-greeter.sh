#!/usr/bin/env bash
# smoke-greeter.sh — run the whole login screen under a headless Hyprland and
# take its picture. tests/test-greeter.sh drives the card's authentication
# without a compositor; this proves the layer surface, the layout and the font
# actually come up, which a login screen has to do before anyone can type.
#
# Needs: Hyprland, quickshell, grim. Writes to ${1:-/tmp/haseen-greeter-smoke}.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
OUT="${1:-/tmp/haseen-greeter-smoke}"
rm -rf "$OUT"
mkdir -p "$OUT/home/.local/state" "$OUT/run"
export HASEEN_PATH="$REPO/share/haseen"

# A fake greetd: the smoke is about the screen, not about PAM. It answers one
# password prompt, so the error path has something to show.
cat >"$OUT/greetd.py" <<'PY'
import json, os, socket, struct, sys, threading
path = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(path); s.listen(1)
def serve():
    conn, _ = s.accept()
    while True:
        head = conn.recv(4)
        if len(head) < 4: return
        (n,) = struct.unpack("=i", head)
        body = b""
        while len(body) < n:
            body += conn.recv(n - len(body))
        req = json.loads(body)
        if req["type"] == "create_session":
            out = {"type": "auth_message", "auth_message_type": "secret", "auth_message": "Password:"}
        elif req["type"] == "post_auth_message_response":
            out = {"type": "error", "error_type": "auth_error", "description": "Login incorrect"}
        else:
            out = {"type": "success"}
        raw = json.dumps(out).encode()
        conn.sendall(struct.pack("=i", len(raw)) + raw)
threading.Thread(target=serve, daemon=True).start()
threading.Event().wait(300)
PY
python3 "$OUT/greetd.py" "$OUT/greetd.sock" >"$OUT/greetd.log" 2>&1 &
greetd=$!

cat >"$OUT/hyprland.conf" <<EOF
monitor = , 1280x800@60, 0x0, 1
animations { enabled = false }
misc { disable_hyprland_logo = true; disable_splash_rendering = true }
exec-once = sh -c "qs -p $HASEEN_PATH/shell/greeter >$OUT/qs.log 2>&1"
EOF

# Hyprland's DRM backend needs a seat this process does not have, so the
# compositor nests in the session that is already running: one window, no
# input taken from it, and the greeter inside it is the real thing.
[[ -n ${WAYLAND_DISPLAY:-} ]] || {
    echo "run this from a Wayland session: Hyprland nests in it" >&2
    exit 1
}
export HOME="$OUT/home" XDG_STATE_HOME="$OUT/home/.local/state"
export GREETD_SOCK="$OUT/greetd.sock" QT_QUICK_BACKEND=software HYPRLAND_NO_SD_NOTIFY=1

before="$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -not -name '*.lock' | sort)"
dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- \
    Hyprland -c "$OUT/hyprland.conf" >"$OUT/hyprland.log" 2>&1 &
hypr=$!
trap 'kill "$hypr" "$greetd" 2>/dev/null || true' EXIT

for _ in $(seq 60); do
    sock="$(comm -13 <(printf '%s\n' "$before") \
        <(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name 'wayland-*' -not -name '*.lock' | sort) | head -1)"
    [[ -n ${sock:-} ]] && break
    sleep 0.5
done
[[ -n ${sock:-} ]] || {
    tail -20 "$OUT/hyprland.log"
    echo "the nested compositor did not come up" >&2
    exit 1
}
export WAYLAND_DISPLAY="${sock##*/}"
sleep 6

pid="$(pgrep -f 'qs -p .*shell/greeter' | head -1 || true)"
[[ -n $pid ]] || {
    tail -20 "$OUT/hyprland.log"
    echo "the greeter shell is not running" >&2
    exit 1
}

echo "state: $(qs ipc --pid "$pid" call greeter state)"
grim "$OUT/greeter.png" && echo "shot: $OUT/greeter.png"

# And the failure path, which is the one a tired human sees at 2am.
qs ipc --pid "$pid" call greeter login wrong >/dev/null || true
sleep 2
echo "after a wrong password: $(qs ipc --pid "$pid" call greeter state)"
grim "$OUT/greeter-wrong.png" && echo "shot: $OUT/greeter-wrong.png"
