#!/usr/bin/env bash
# Start a nested Hyprland for UI tests, the only allowed way next to a live
# session: through the owner's Hyprland exec rule, so its window maps on
# workspace 5 silently and never takes the owner's focus. Concurrent agents
# wrap it in `flock ~/.cache/haseen-wt/nest.lock`.
#
# usage: nest-launch.sh DIR [MODE]
#   DIR   scratch dir for this session (created; must be yours alone)
#   MODE  headless output mode, default 1536x864@60
# Writes into DIR:
#   pid     the compositor's PID = its process group: stop with  kill -- -$(cat DIR/pid)
#   socket  the nested WAYLAND_DISPLAY (e.g. wayland-3)
#   sig     the nested HYPRLAND_INSTANCE_SIGNATURE
# A headless output "IO" is added and the window output disabled, so
# `WAYLAND_DISPLAY=$(cat DIR/socket) grim -o IO shot.png` works (a hidden
# window gets no frames). After stopping, remove only $XDG_RUNTIME_DIR/hypr/$(cat DIR/sig)
# and the socket if they remain.
set -Eeuo pipefail
dir=$1 mode=${2:-1536x864@60}
owner_sig=${HYPRLAND_INSTANCE_SIGNATURE:?run from the owner session environment}
mkdir -p "$dir"
rm -f "$dir/pid" "$dir/socket" "$dir/sig"
printf 'hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })\n' >"$dir/hyprland.lua"
cat >"$dir/run.sh" <<EOF
#!/usr/bin/env bash
echo \$\$ > "$dir/pid"
exec dbus-run-session --config-file=/usr/share/dbus-1/session.conf -- start-hyprland -- -c "$dir/hyprland.lua" > "$dir/hyprland.log" 2>&1
EOF
chmod +x "$dir/run.sh"
# Names of the Wayland display sockets in the runtime dir, sorted.
wayland_sockets() {
    local f
    for f in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [[ ${f##*/} =~ ^wayland-[0-9]+$ ]]; then printf '%s\n' "${f##*/}"; fi
    done | sort
}
before=$(wayland_sockets)
sigs_before=$(ls "$XDG_RUNTIME_DIR/hypr" | sort)
HYPRLAND_INSTANCE_SIGNATURE=$owner_sig hyprctl dispatch \
    "hl.dsp.exec_cmd(\"setsid -w $dir/run.sh\", { workspace = \"5 silent\", no_initial_focus = true })" >/dev/null
for _ in $(seq 60); do
    [[ -s $dir/pid ]] && break
    sleep 0.25
done
[[ -s $dir/pid ]] || { echo "nested compositor did not start" >&2; exit 1; }
for _ in $(seq 40); do
    sock=$(comm -13 <(echo "$before") <(wayland_sockets) | head -1)
    sig=$(comm -13 <(echo "$sigs_before") <(ls "$XDG_RUNTIME_DIR/hypr" | sort) | head -1)
    [[ -n $sock && -n $sig && -S $XDG_RUNTIME_DIR/hypr/$sig/.socket.sock ]] && break
    sleep 0.25
done
[[ -n ${sock:-} && -n ${sig:-} ]] || { echo "nested socket not found" >&2; exit 1; }
echo "$sock" >"$dir/socket"
echo "$sig" >"$dir/sig"
ws=$(HYPRLAND_INSTANCE_SIGNATURE=$owner_sig hyprctl -j clients | jq -r '.[] | select(.class=="aquamarine") | .workspace.name' | sort -u | tr '\n' ' ')
case " $ws " in *" 5 "*) ;; *) echo "WARNING: nested window not on workspace 5 (found: $ws)" >&2 ;; esac
export HYPRLAND_INSTANCE_SIGNATURE=$sig
sleep 1
hyprctl output create headless IO >/dev/null
hyprctl eval "hl.monitor({ output = \"IO\", mode = \"$mode\", position = \"0x0\", scale = 1 })" >/dev/null
hyprctl keyword monitor "WAYLAND-1,disable" >/dev/null 2>&1 || true
echo "nested pid=$(cat "$dir/pid") socket=$sock sig=$sig"
