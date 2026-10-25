# shellcheck shell=bash
# haseen:covers bin/haseen-layer-{apply,status} share/haseen/VERSION share/haseen/default/foot/**
# haseen:covers share/haseen/default/hypr/**
# haseen:covers share/haseen/layers/{base,chaotic,desktop,gaming,omarchy-repo}/**
# haseen:covers share/haseen/lib/{greeter,layers,packages,preflight}.sh
# haseen:covers tests/fixtures/{desk-arch-hybrid,desk-arch-intel,desk-cachyos-amd}/**
# haseen:covers tests/fixtures/desk-cachyos-nvidia-dm/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# base, desktop and gaming layers (plan 003): per-fixture dry-run plans,
# seed-once user files, greetd convergence, GPU env, gaming package choice,
# and the Hyprland Lua entry point loaded under a stub `hl`.

LAYER_LIB='source "$HASEEN_PATH/lib/layers.sh"; preflight_all; LAYER_DIR="$HASEEN_PATH/layers/desktop"; source "$LAYER_DIR/layer.sh"'

# desktop_dry FIXTURE_DIR [LAYER] [-- ARGS] — dry-run apply; OUTPUT/STATUS.
desktop_dry() {
    local fx="$1" layer="${2:-desktop}"
    shift 2 || shift $#
    capture env HASEEN_SYSROOT="$fx" haseen layer apply "$layer" --dry-run "$@"
}

# --- desktop: DM present, NVIDIA (Ada) --------------------------------------
sandbox desk-nvidia
desktop_dry "$FIXTURES/desk-cachyos-nvidia-dm"
assert_status "nvidia: dry-run exit" 0 "$STATUS"
assert_dry_pure "nvidia: desktop" "$OUTPUT"
assert_contains "nvidia: base and chaotic applied first" "$OUTPUT" "apply order: base chaotic desktop"
assert_contains "nvidia: sddm kept" "$OUTPUT" "login: sddm.service is enabled; keeping it"
assert_not_contains "nvidia: no greetd package with a DM" "$OUTPUT" "greetd-tuigreet"
assert_not_contains "nvidia: no greetd config with a DM" "$OUTPUT" "/etc/greetd"
assert_not_contains "nvidia: no greetd unit with a DM" "$OUTPUT" "greetd.service"
assert_contains "nvidia: env LIBVA" "$OUTPUT" "    | export LIBVA_DRIVER_NAME=nvidia"
assert_contains "nvidia: env GBM" "$OUTPUT" "    | export GBM_BACKEND=nvidia-drm"
assert_contains "nvidia: env direct backend (Turing+)" "$OUTPUT" "    | export NVD_BACKEND=direct"
assert_contains "nvidia: env file path" "$OUTPUT" "write $HOME/.config/uwsm/env.d/50-haseen-gpu:"
assert_contains "nvidia: vaapi driver" "$OUTPUT" "DRYRUN: sudo pacman -S --needed libva-nvidia-driver"
assert_contains "nvidia: driver kept" "$OUTPUT" "keeping the installed NVIDIA driver (linux-cachyos-nvidia-open nvidia-utils)"
assert_not_contains "nvidia: chwd not run with a driver" "$OUTPUT" "chwd"
assert_contains "nvidia: modeset drop-in" "$OUTPUT" "write /etc/modprobe.d/haseen-nvidia.conf"
assert_contains "nvidia: HASEEN_PATH env" "$OUTPUT" "    | export HASEEN_PATH=$HASEEN_PATH"
assert_contains "nvidia: TERMINAL env" "$OUTPUT" "    | export TERMINAL=foot"
assert_contains "cursor theme env (owner's luna default)" "$OUTPUT" "    | export XCURSOR_THEME=Bibata-Modern-Ice"
assert_contains "cursor size env" "$OUTPUT" "    | export XCURSOR_SIZE=20"
assert_contains "cursor package (Chaotic-AUR first)" "$OUTPUT" "bibata-cursor-theme"
assert_contains "base: ufw planned" "$OUTPUT" "DRYRUN: sudo ufw default deny incoming"
assert_contains "base: ufw enabled at boot" "$OUTPUT" "DRYRUN: sudo systemctl enable --now ufw.service"
assert_contains "base: snapper warning on btrfs" "$OUTPUT" "snapper has no 'root' config"
assert_not_contains "base: NetworkManager kept" "$OUTPUT" "pacman -S --needed networkmanager"
assert_not_contains "base: pacman.conf untouched" "$(sed -n '/layer base:/,/layer base applied/p' <<<"$OUTPUT")" "pacman.conf"
assert_contains "chaotic: stanza appended (the one pacman.conf write)" "$OUTPUT" "append to /etc/pacman.conf:"
assert_contains "seed hyprland.lua planned" "$OUTPUT" "DRYRUN: seed $HOME/.config/hypr/hyprland.lua from $HASEEN_PATH/default/hypr/user/hyprland.lua"
assert_contains "seed foot.ini planned" "$OUTPUT" "DRYRUN: seed $HOME/.config/foot/foot.ini"
assert_eq "dry-run wrote nothing under HOME" "" "$(find "$HOME" -mindepth 1 -print -quit)"

# --- desktop: no DM, AMD, everything in base already configured ------------
sandbox desk-amd
desktop_dry "$FIXTURES/desk-cachyos-amd"
assert_status "amd: dry-run exit" 0 "$STATUS"
assert_dry_pure "amd: desktop" "$OUTPUT"
assert_contains "amd: greetd installed" "$OUTPUT" "DRYRUN: sudo pacman -S --needed greetd greetd-tuigreet"
assert_contains "amd: greetd config written" "$OUTPUT" "DRYRUN: write /etc/greetd/config.toml"
assert_contains "amd: greetd starts uwsm" "$OUTPUT" "--cmd 'systemd-cat -t uwsm uwsm start hyprland.desktop'"
assert_contains "amd: greetd enabled, not started" "$OUTPUT" "DRYRUN: sudo systemctl enable greetd.service"
assert_not_contains "amd: no backup of a missing config" "$OUTPUT" "haseen-orig"
assert_contains "amd: env radeonsi" "$OUTPUT" "    | export LIBVA_DRIVER_NAME=radeonsi"
assert_not_contains "amd: no nvidia env" "$OUTPUT" "nvidia"
assert_not_contains "base: configured ufw left alone" "$OUTPUT" "ufw default"
assert_not_contains "base: enabled timer left alone" "$OUTPUT" "paccache.timer"
assert_contains "base: snapper present" "$OUTPUT" "snapper: root config present"

# --- desktop: no DM, Intel, firewalld + networkd on Arch -------------------
sandbox desk-intel
desktop_dry "$FIXTURES/desk-arch-intel"
assert_status "intel: dry-run exit" 0 "$STATUS"
assert_dry_pure "intel: desktop" "$OUTPUT"
assert_contains "intel: greetd" "$OUTPUT" "DRYRUN: write /etc/greetd/config.toml"
assert_contains "intel: media driver" "$OUTPUT" "DRYRUN: sudo pacman -S --needed intel-media-driver"
assert_contains "intel: env comment" "$OUTPUT" "    | # Intel: libva picks iHD"
assert_not_contains "intel: no LIBVA override" "$OUTPUT" "LIBVA_DRIVER_NAME="
assert_contains "base: firewalld respected" "$OUTPUT" "firewalld is enabled"
assert_not_contains "base: no ufw over firewalld" "$OUTPUT" "sudo ufw"
assert_contains "base: networkd respected" "$OUTPUT" "systemd-networkd.service is enabled"
assert_not_contains "base: no snapper check on ext4" "$OUTPUT" "Warning: root is btrfs"

# --- desktop: hybrid Intel + NVIDIA Pascal, greetd with a foreign config ----
sandbox desk-hybrid
desktop_dry "$FIXTURES/desk-arch-hybrid"
assert_status "hybrid: dry-run exit" 0 "$STATUS"
assert_dry_pure "hybrid: desktop" "$OUTPUT"
assert_contains "hybrid: foreign greetd config kept" "$OUTPUT" "greetd is enabled with a config haseen did not write"
assert_not_contains "hybrid: greetd config untouched" "$OUTPUT" "write /etc/greetd"
assert_not_contains "hybrid: greetd not re-enabled" "$OUTPUT" "enable greetd"
assert_contains "hybrid: env explains offload" "$OUTPUT" "    | #   prime-run <app>"
assert_not_contains "hybrid: no global GBM_BACKEND" "$OUTPUT" "export GBM_BACKEND"
assert_not_contains "hybrid: no global LIBVA" "$OUTPUT" "export LIBVA_DRIVER_NAME"
assert_contains "hybrid: prime-run" "$OUTPUT" "DRYRUN: sudo pacman -S --needed nvidia-prime"
assert_contains "hybrid: open module on Pascal warned" "$OUTPUT" "predates Turing"
assert_contains "hybrid: existing modeset respected" "$OUTPUT" "modeset already configured under /etc/modprobe.d"
assert_not_contains "hybrid: no modeset drop-in" "$OUTPUT" "haseen-nvidia.conf"
assert_not_contains "hybrid: no vaapi nvidia on hybrid" "$OUTPUT" "libva-nvidia-driver"
assert_contains "base: NetworkManager when nothing manages the network" "$OUTPUT" "DRYRUN: sudo systemctl enable --now NetworkManager.service"

# --- greetd: a haseen-written config converges ------------------------------
sandbox desk-greetd-converge
root="$SANDBOX/sysroot"
cp -a "$FIXTURES/desk-cachyos-amd" "$root"
mkdir -p "$root/etc/systemd/system" "$root/etc/greetd"
ln -s /usr/lib/systemd/system/greetd.service "$root/etc/systemd/system/display-manager.service"
capture env HASEEN_SYSROOT="$root" bash -c "$LAYER_LIB; greetd_config"
printf '%s\n' "$OUTPUT" >"$root/etc/greetd/config.toml"
desktop_dry "$root"
assert_dry_pure "greetd converge" "$OUTPUT"
assert_contains "greetd: current config recognised" "$OUTPUT" "login: /etc/greetd/config.toml is current"
assert_not_contains "greetd: not rewritten" "$OUTPUT" "write /etc/greetd"
assert_not_contains "greetd: not re-enabled" "$OUTPUT" "enable greetd"
printf '%s\n' "# Written by haseen layers/desktop. old" "[default_session]" 'command = "old"' >"$root/etc/greetd/config.toml"
desktop_dry "$root"
assert_contains "greetd: stale haseen config refreshed" "$OUTPUT" "DRYRUN: write /etc/greetd/config.toml"
assert_not_contains "greetd: own config not backed up" "$OUTPUT" "haseen-orig"
rm "$root/etc/systemd/system/display-manager.service"
printf '%s\n' "[default_session]" 'command = "agreety --cmd /bin/sh"' >"$root/etc/greetd/config.toml"
desktop_dry "$root"
assert_contains "greetd: packaged default backed up once" "$OUTPUT" "DRYRUN: sudo cp -a /etc/greetd/config.toml /etc/greetd/config.toml.haseen-orig"

# --- user files: seeded once, env files converge ---------------------------
sandbox desk-seed
fx="$FIXTURES/desk-cachyos-nvidia-dm"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=false bash -c "$LAYER_LIB; desktop_user_setup"
assert_status "seed: first run" 0 "$STATUS"
assert_dry_pure "seed: user setup runs no privileged binary" "$OUTPUT"
assert_eq "seed: hyprland.lua is the shipped seed" "$(<"$HASEEN_PATH/default/hypr/user/hyprland.lua")" "$(<"$HOME/.config/hypr/hyprland.lua")"
assert_eq "seed: foot.ini is the shipped seed" "$(<"$HASEEN_PATH/default/foot/foot.ini")" "$(<"$HOME/.config/foot/foot.ini")"
assert_contains "seed: foot includes the theme" "$(<"$HOME/.config/foot/foot.ini")" "include=~/.local/state/haseen/current/theme/foot.ini"
assert_eq "seed: foot theme placeholder present" "$(<"$HASEEN_PATH/default/foot/theme-fallback.ini")" "$(<"$HOME/.local/state/haseen/current/theme/foot.ini")"
if command -v foot >/dev/null; then
    capture foot --check-config -c "$HOME/.config/foot/foot.ini"
    assert_status "seed: foot accepts the seeded config before any theme" 0 "$STATUS"
fi
assert_contains "seed: gpu env written" "$(<"$HOME/.config/uwsm/env.d/50-haseen-gpu")" "export GBM_BACKEND=nvidia-drm"
# shellcheck disable=SC1091
assert_eq "seed: session env is valid shell" "$HASEEN_PATH" "$(
    unset HASEEN_PATH
    source "$HOME/.config/uwsm/env.d/10-haseen"
    printf '%s' "$HASEEN_PATH"
)"
# Qt follows the GTK platform theme rather than a second Qt theming stack
# (qt6ct/Kvantum); the plugin ships with qt6-base, so nothing extra installs.
assert_contains "seed: Qt apps follow the GTK theme" \
    "$(<"$HOME/.config/uwsm/env.d/10-haseen")" "export QT_QPA_PLATFORMTHEME=gtk3"
printf '%s\n' '-- mine' >>"$HOME/.config/hypr/hyprland.lua"
printf '%s\n' '# mine' >"$HOME/.config/foot/foot.ini"
printf '%s\n' '[colors-dark]' 'background=000000' >"$HOME/.local/state/haseen/current/theme/foot.ini"
capture env HASEEN_SYSROOT="$fx" DRY_RUN=false bash -c "$LAYER_LIB; desktop_user_setup"
assert_contains "seed: user edit to hyprland.lua survives" "$(<"$HOME/.config/hypr/hyprland.lua")" "-- mine"
assert_eq "seed: user foot.ini survives" "# mine" "$(<"$HOME/.config/foot/foot.ini")"
assert_contains "seed: rendered theme not replaced by the placeholder" "$(<"$HOME/.local/state/haseen/current/theme/foot.ini")" "background=000000"
capture env HASEEN_SYSROOT="$fx" haseen layer apply desktop --dry-run
assert_not_contains "seed: re-apply plans no seed" "$OUTPUT" "DRYRUN: seed"
assert_not_contains "seed: unchanged env files are not rewritten" "$OUTPUT" "uwsm/env.d"
# GPU changes (here: the same HOME on an AMD machine) do rewrite the env.
capture env HASEEN_SYSROOT="$FIXTURES/desk-cachyos-amd" haseen layer apply desktop --dry-run
assert_contains "seed: stale gpu env rewritten" "$OUTPUT" "write $HOME/.config/uwsm/env.d/50-haseen-gpu:"

sandbox desk-foreign-hypr
mkdir -p "$HOME/.config/hypr"
printf '%s\n' 'require("default.hypr.omarchy")' >"$HOME/.config/hypr/hyprland.lua"
desktop_dry "$FIXTURES/desk-cachyos-nvidia-dm"
assert_contains "foreign hyprland.lua: warned" "$OUTPUT" "does not load haseen's defaults"
assert_not_contains "foreign hyprland.lua: not seeded over" "$OUTPUT" "seed $HOME/.config/hypr/hyprland.lua"

# --- the Lua entry point under a stub hl -----------------------------------
if command -v lua >/dev/null; then
    sandbox desk-lua
    stub_lua="$SANDBOX/hl-stub.lua"
    cat >"$stub_lua" <<'EOF'
-- Records what the config does instead of configuring a compositor.
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...) return { dsp = name, args = { ... } } end,
  })
end
local function value(v)
  if type(v) ~= "table" then return tostring(v) end
  if v.colors then return "gradient(" .. table.concat(v.colors, ",") .. "@" .. tostring(v.angle) .. ")" end
  local parts = {}
  for _, item in ipairs(v) do parts[#parts + 1] = tostring(item) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function flat(prefix, t)
  for k, v in pairs(t) do
    local key = prefix == "" and k or (prefix .. "." .. k)
    if type(v) == "table" and not v.colors and v[1] == nil then flat(key, v) else print("CONFIG " .. key .. "=" .. value(v)) end
  end
end
-- One line per call, its fields sorted, so a test can pin a whole spec.
local function fields(t)
  local keys, parts = {}, {}
  for k in pairs(t) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  for _, k in ipairs(keys) do
    if type(t[k]) == "table" and t[k][1] == nil and not t[k].colors then
      parts[#parts + 1] = k .. "=[" .. fields(t[k]) .. "]"
    else
      parts[#parts + 1] = k .. "=" .. value(t[k])
    end
  end
  return table.concat(parts, " ")
end
hl = setmetatable({
  dsp = proxy("dsp"),
  config = function(t) flat("", t) end,
  animation = function(t) print("ANIM " .. fields(t)) end,
  curve = function(name, t)
    local a, b = t.points[1], t.points[2]
    print(("CURVE %s %s %g,%g %g,%g"):format(name, t.type, a[1], a[2], b[1], b[2]))
  end,
  window_rule = function(t) print("RULE " .. fields(t)) end,
  layer_rule = function(t) print("LAYER " .. fields(t)) end,
  bind = function(keys, d, _)
    -- A Lua function is a valid dispatcher (Hyprland runs it on the key).
    local what = type(d) == "function" and "lua:function" or (d.dsp == "dsp.exec_cmd" and d.args[1] or d.dsp)
    print("BIND " .. keys .. " -> " .. what)
  end,
  unbind = function(keys) print("UNBIND " .. keys) end,
  on = function(event, _) print("ON " .. event) end,
}, { __index = function() return function() end end })
EOF
    mkdir -p "$HOME/.config/hypr" "$HOME/.local/state/haseen/current/theme"
    cp "$HASEEN_PATH/default/hypr/user/hyprland.lua" "$HOME/.config/hypr/hyprland.lua"
    lua_run() { capture lua -e "dofile('$stub_lua')" "$HOME/.config/hypr/hyprland.lua"; }

    lua_run
    assert_status "lua: seeded config loads" 0 "$STATUS"
    assert_contains "lua: launcher bind" "$OUTPUT" "BIND SUPER + SHIFT + SPACE -> haseen shell ipc launcher toggle"
    assert_contains "lua: lock bind" "$OUTPUT" "BIND SUPER + CTRL + L -> haseen shell ipc lock lock"
    assert_contains "lua: AI panel bind" "$OUTPUT" "-> haseen shell ipc panel toggle 'haseen.ai'"
    assert_contains "lua: notifications bind" "$OUTPUT" "-> haseen shell ipc notifications clear"
    assert_contains "lua: volume via wpctl" "$OUTPUT" "BIND XF86AudioRaiseVolume -> wpctl set-volume"
    assert_contains "lua: brightness via haseen brightness" "$OUTPUT" "BIND XF86MonBrightnessUp -> haseen brightness up"
    assert_contains "lua: keyboard backlight via haseen brightness" "$OUTPUT" "BIND XF86KbdBrightnessDown -> haseen brightness down kbd"
    assert_contains "lua: screenshot via haseen capture" "$OUTPUT" "BIND PRINT -> haseen capture screenshot"
    assert_contains "lua: menu bind" "$OUTPUT" "BIND SUPER + SPACE -> haseen menu"
    assert_eq "lua: no key bound twice" "" "$(grep -oE '^BIND [^>]+->' <<<"$OUTPUT" | sort | uniq -d)"
    assert_contains "lua: workspace binds" "$OUTPUT" "BIND SUPER + code:19 -> dsp.focus"
    assert_contains "lua: autostart on hyprland.start only" "$OUTPUT" "ON hyprland.start"
    assert_contains "lua: no blur" "$OUTPUT" "CONFIG decoration.blur.enabled=false"

    # Omarchy 4.5's window look, value for value (plan 114):
    # default/hypr/looknfeel.lua@v4.5.0-rc1, the line each value is on.
    for want in general.gaps_in=5:8 general.gaps_out=10:9 general.border_size=2:10 \
        "general.col.active_border=gradient(rgba(33ccffee),rgba(00ff99ee)@45):3" \
        general.col.inactive_border=rgba\(595959aa\):4 general.resize_on_border=true:17 \
        general.extend_border_grab_area=8:18 general.hover_icon_on_border=true:19 \
        general.allow_tearing=false:20 general.layout=dwindle:21 decoration.rounding=0:25 \
        decoration.shadow.enabled=false:28 group.groupbar.font_size=12:43 \
        group.groupbar.font_family=monospace:44 group.groupbar.font_weight_active=ultraheavy:45 \
        group.groupbar.font_weight_inactive=normal:46 group.groupbar.indicator_height=1:47 \
        group.groupbar.indicator_gap=5:48 group.groupbar.height=22:49 group.groupbar.gaps_in=5:50 \
        group.groupbar.gaps_out=0:51 "group.groupbar.text_color=rgb(ffffff):52" \
        "group.groupbar.text_color_inactive=rgba(ffffff90):53" "group.groupbar.col.active=rgba(00000040):55" \
        "group.groupbar.col.inactive=rgba(00000020):56" group.groupbar.gradients=true:58 \
        group.groupbar.gradient_rounding=0:59 group.groupbar.gradient_round_only_edges=false:60 \
        animations.enabled=true:65 dwindle.preserve_split=true:94 dwindle.force_split=2:95 \
        scrolling.column_width=0.49:99 master.new_status=master:103 \
        misc.disable_hyprland_logo=true:107 misc.disable_splash_rendering=true:108 \
        "misc.background_color=rgb(000000):109" misc.disable_scale_notification=true:110 \
        misc.focus_on_activate=true:111 misc.anr_missed_pings=3:112 \
        misc.on_focus_under_fullscreen=1:113 misc.initial_workspace_tracking=0:114 \
        misc.allow_session_lock_restore=true:117 cursor.hide_on_key_press=true:121 \
        cursor.warp_on_change_workspace=1:122 binds.hide_special_on_workspace_change=true:126; do
        assert_contains "lua: Omarchy's ${want%%=*} (looknfeel.lua:${want##*:})" "$OUTPUT" "CONFIG ${want%:*}"$'\n'
    done
    for want in "easeOutQuint bezier 0.23,1 0.32,1:70" "easeInOutCubic bezier 0.65,0.05 0.36,1:71" \
        "linear bezier 0,0 1,1:72" "almostLinear bezier 0.5,0.5 0.75,1:73" "quick bezier 0.15,0 0.1,1:74"; do
        assert_contains "lua: Omarchy's curve ${want%% *} (looknfeel.lua:${want##*:})" "$OUTPUT" "CURVE ${want%:*}"$'\n'
    done
    for want in \
        "bezier=default enabled=true leaf=global speed=10:76" \
        "bezier=easeOutQuint enabled=true leaf=border speed=5.39:77" \
        "bezier=easeOutQuint enabled=true leaf=windows speed=3.79:78" \
        "bezier=easeOutQuint enabled=true leaf=windowsIn speed=4.1 style=popin 87%:79" \
        "bezier=linear enabled=true leaf=windowsOut speed=1.49 style=popin 87%:80" \
        "bezier=almostLinear enabled=true leaf=fadeIn speed=1.73:81" \
        "bezier=almostLinear enabled=true leaf=fadeOut speed=1.46:82" \
        "bezier=quick enabled=true leaf=fade speed=3.03:83" \
        "enabled=false leaf=fadeSwitch:84" \
        "bezier=easeOutQuint enabled=true leaf=layers speed=3.81:85" \
        "bezier=easeOutQuint enabled=true leaf=layersIn speed=4 style=fade:86" \
        "bezier=linear enabled=true leaf=layersOut speed=1.5 style=fade:87" \
        "bezier=almostLinear enabled=true leaf=fadeLayersIn speed=1.79:88" \
        "bezier=almostLinear enabled=true leaf=fadeLayersOut speed=1.39:89" \
        "enabled=false leaf=workspaces:90"; do
        assert_contains "lua: Omarchy's animation ${want%%:*} (looknfeel.lua:${want##*:})" "$OUTPUT" "ANIM ${want%:*}"$'\n'
    done
    assert_eq "lua: Omarchy's fifteen animation calls and no others at load" 15 "$(grep -c '^ANIM ' <<<"$OUTPUT")"
    # Omarchy's window rules for the look (default/hypr/windows.lua:22-23,
    # apps/pip.lua, apps/system.lua): see-through terminals, the PiP corner.
    assert_contains "lua: terminals are see-through" "$OUTPUT" 'RULE match=[tag=terminal] opacity=0.985 0.96 tag=+transparent-window'
    assert_contains "lua: PiP is borderless in the top-right corner" "$OUTPUT" \
        'RULE border_size=0 float=true keep_aspect_ratio=true match=[tag=pip] move={(monitor_w-window_w-40),(monitor_h*0.04)} name=haseen_pip pin=true size={600,338}'
    assert_contains "lua: viewers and dialogs float at 875 x 600" "$OUTPUT" \
        'RULE center=true float=true match=[tag=floating-window] name=haseen_floating_window size={875,600}'
    assert_contains "lua: the bar layer is never animated" "$OUTPUT" 'LAYER animation=none match=[namespace=^haseen-bar$] name=haseen_bar_layer no_anim=true'
    assert_not_contains "lua: no bar launched" "$OUTPUT" "qs -p"

    # Toggles persisted by `haseen toggle …` load after the defaults.
    mkdir -p "$HOME/.local/state/haseen/toggles/hypr"
    printf '%s\n' 'hl.config({ general = { gaps_in = 0 } })' >"$HOME/.local/state/haseen/toggles/hypr/gaps.lua"
    lua_run
    assert_contains "lua: persisted toggle loaded" "$OUTPUT" "CONFIG general.gaps_in=0"
    rm -rf "$HOME/.local/state/haseen/toggles"

    # Theme and user files load after the defaults, in that order.
    printf '%s\n' 'hl.config({ general = { col = { active_border = "rgb(THEME)" } } })' \
        >"$HOME/.local/state/haseen/current/theme/hyprland.lua"
    printf '%s\n' 'hl.unbind("SUPER + B")' 'haseen.bind("SUPER + B", "Browser", "uwsm-app -- firefox")' \
        >"$HOME/.config/hypr/bindings.lua"
    printf '%s\n' 'error("broken local file")' >"$HOME/.config/hypr/local.lua"
    lua_run
    assert_status "lua: broken local.lua is not fatal" 0 "$STATUS"
    assert_contains "lua: broken local.lua reported" "$OUTPUT" "local.lua failed to load"
    theme_line="$(grep -n 'active_border=rgb(THEME)' <<<"$OUTPUT" | cut -d: -f1)"
    default_line="$(grep -n 'general.col.active_border=gradient(rgba(33ccffee),rgba(00ff99ee)@45)' <<<"$OUTPUT" | cut -d: -f1)"
    assert_eq "lua: theme overrides default border" "true" "$([[ -n $theme_line && -n $default_line && $theme_line -gt $default_line ]] && echo true || echo false)"
    unbind_line="$(grep -n '^UNBIND SUPER + B$' <<<"$OUTPUT" | cut -d: -f1)"
    rebind_line="$(grep -n '^BIND SUPER + B -> uwsm-app -- firefox$' <<<"$OUTPUT" | cut -d: -f1)"
    assert_eq "lua: user bindings after defaults" "true" "$([[ -n $unbind_line && -n $rebind_line && $unbind_line -lt $rebind_line ]] && echo true || echo false)"

    # init.lua finds share/haseen from its own location (a first login can
    # have no HASEEN_PATH yet).
    capture env -u HASEEN_PATH lua -e "dofile('$stub_lua')" -e "dofile('$HASEEN_PATH/default/hypr/init.lua'); print('PATH ' .. haseen.path)"
    assert_contains "lua: own location wins" "$OUTPUT" "PATH $HASEEN_PATH"
fi

# --- gaming ------------------------------------------------------------------
sandbox gaming-cachyos
desktop_dry "$FIXTURES/desk-cachyos-amd" gaming
assert_status "gaming cachyos: exit" 0 "$STATUS"
assert_dry_pure "gaming cachyos" "$OUTPUT"
assert_contains "gaming cachyos: meta package" "$OUTPUT" "DRYRUN: sudo pacman -S --needed cachyos-gaming-meta steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope lib32-mesa lib32-vulkan-radeon"
assert_not_contains "gaming cachyos: launchers opt-in" "$OUTPUT" "cachyos-gaming-applications"
assert_contains "gaming: secure boot note" "$OUTPUT" "haseen secureboot setup"
assert_contains "gaming: user added to gamemode group" "$OUTPUT" "DRYRUN: sudo usermod -aG gamemode $USER"
USER=someone desktop_dry "$FIXTURES/desk-cachyos-amd" gaming
assert_not_contains "gaming: member of gamemode not re-added" "$OUTPUT" "usermod"
desktop_dry "$FIXTURES/desk-cachyos-amd" gaming -- --apps
assert_contains "gaming cachyos --apps" "$OUTPUT" "cachyos-gaming-applications"

sandbox gaming-arch
desktop_dry "$FIXTURES/desk-arch-hybrid" gaming
assert_status "gaming arch: exit" 0 "$STATUS"
assert_dry_pure "gaming arch" "$OUTPUT"
assert_contains "gaming arch: plain packages" "$OUTPUT" "DRYRUN: sudo pacman -S --needed steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope lib32-mesa lib32-vulkan-intel"
assert_not_contains "gaming arch: no cachyos meta" "$OUTPUT" "cachyos-gaming"
assert_contains "gaming arch: legacy nvidia lib32 from AUR" "$OUTPUT" "DRYRUN: paru -S --needed lib32-nvidia-580xx-utils"
desktop_dry "$FIXTURES/desk-arch-hybrid" gaming -- --apps
assert_contains "gaming arch: --apps refused politely" "$OUTPUT" "--apps needs the CachyOS repositories"

sandbox gaming-nomultilib
desktop_dry "$FIXTURES/desk-arch-intel" gaming
assert_status "gaming: multilib missing refuses" 1 "$STATUS"
assert_contains "gaming: multilib message" "$OUTPUT" "[multilib] repository is not enabled"
assert_not_contains "gaming: nothing installed when refused" "$OUTPUT" "steam"
assert_not_contains "gaming: refusal leaves no marker" "$OUTPUT" "write /var/lib/haseen/layers/gaming"
capture env HASEEN_SYSROOT="$FIXTURES/desk-arch-intel" haseen layer status gaming
assert_status "gaming status: not applied" 1 "$STATUS"
assert_contains "gaming status: multilib" "$OUTPUT" "missing: [multilib]"

# --- base options --------------------------------------------------------------
sandbox base-options
desktop_dry "$FIXTURES/desk-cachyos-amd" base -- --bluetooth
assert_dry_pure "base --bluetooth" "$OUTPUT"
assert_contains "base --bluetooth: bluez" "$OUTPUT" "DRYRUN: sudo pacman -S --needed bluez bluez-utils"
assert_contains "base --bluetooth: service" "$OUTPUT" "DRYRUN: sudo systemctl enable --now bluetooth.service"
desktop_dry "$FIXTURES/desk-cachyos-amd" base
assert_not_contains "base: bluetooth only on request" "$OUTPUT" "bluez"
desktop_dry "$FIXTURES/desk-cachyos-amd" base -- --nope
assert_status "base: unknown option" 1 "$STATUS"
assert_contains "base: unknown option named" "$OUTPUT" "unknown option '--nope'"

# --- herdr and xdg-terminal-exec only from [omarchy] (owner, 2026-10-08) -------
# Without the omarchy-repo layer they are skipped with a warning; with it they
# install from [omarchy] and from nothing else: not from an official repo or
# Chaotic-AUR that carries the same name, and never built from the AUR.
sandbox desk-omarchy
fx="$SANDBOX/fx"
cp -a "$FIXTURES/desk-cachyos-amd/." "$fx/"
desktop_dry "$fx"
assert_status "no [omarchy]: the desktop still applies" 0 "$STATUS"
assert_dry_pure "no [omarchy]" "$OUTPUT"
assert_contains "no [omarchy]: a clear warning names both" "$OUTPUT" \
    "skipping xdg-terminal-exec herdr omasnap: haseen installs them only from Omarchy's [omarchy] repo, which is not enabled. To add them: haseen layer apply omarchy-repo desktop"
assert_eq "no [omarchy]: neither is installed from any source" "" \
    "$(grep -E '^DRYRUN: .*(pacman|paru|yay) .*(herdr|xdg-terminal-exec|omasnap)' <<<"$OUTPUT" || true)"
assert_contains "no [omarchy]: the rest of the AUR row still installs" "$OUTPUT" "ttfx"
assert_contains "no [omarchy]: and the layer completes" "$OUTPUT" "layer desktop applied"

# Selected in the same run, before desktop: the dry run plans them from the repo.
capture env HASEEN_SYSROOT="$fx" haseen layer apply omarchy-repo desktop --dry-run
assert_status "omarchy-repo selected: exit" 0 "$STATUS"
assert_contains "omarchy-repo selected: both from [omarchy]" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed omarchy/xdg-terminal-exec omarchy/herdr omarchy/omasnap"
assert_not_contains "omarchy-repo selected: no skip warning" "$OUTPUT" "skipping xdg-terminal-exec"
# Selected after desktop: the real run would reach desktop without the repo.
capture env HASEEN_SYSROOT="$fx" haseen layer apply desktop omarchy-repo --dry-run
assert_contains "omarchy-repo after desktop: still skipped, with the warning" "$OUTPUT" "skipping xdg-terminal-exec herdr omasnap"

# Chaotic-AUR enabled and carrying both, the same names [omarchy] has.
mkdir -p "$fx/var/lib/pacman/sync"
printf '[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' >>"$fx/etc/pacman.conf"
printf 'paru\nherdr\nxdg-terminal-exec\nbibata-cursor-theme\n' >"$fx/var/lib/pacman/sync/chaotic-aur.pkgs"
printf '[omarchy]\nSigLevel = Required DatabaseOptional\nServer = x\n' >>"$fx/etc/pacman.conf"
printf 'omarchy-keyring\nherdr\nxdg-terminal-exec\nomasnap\nttfx\n' >"$fx/var/lib/pacman/sync/omarchy.pkgs"
desktop_dry "$fx"
assert_status "[omarchy] enabled: exit" 0 "$STATUS"
assert_contains "[omarchy] enabled: both from [omarchy]" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed omarchy/xdg-terminal-exec omarchy/herdr omarchy/omasnap"
assert_not_contains "[omarchy] enabled: never Chaotic-AUR's build" "$OUTPUT" "chaotic-aur/herdr"
assert_not_contains "[omarchy] enabled: no skip warning" "$OUTPUT" "skipping xdg-terminal-exec"

# [omarchy] enabled but not carrying them, or its database unreadable (a
# failed lookup): skipped with the warning even though Chaotic-AUR has both
# and an AUR helper is at hand.
stub paru 'exit 0'
for lookup in absent failed; do
    printf 'omarchy-keyring\nttfx\n' >"$fx/var/lib/pacman/sync/omarchy.pkgs"
    [[ $lookup == absent ]] || chmod 000 "$fx/var/lib/pacman/sync/omarchy.pkgs"
    desktop_dry "$fx"
    chmod 644 "$fx/var/lib/pacman/sync/omarchy.pkgs"
    assert_status "[omarchy] enabled, lookup $lookup: the desktop still applies" 0 "$STATUS"
    assert_contains "[omarchy] enabled, lookup $lookup: a warning names both" "$OUTPUT" \
        "skipping xdg-terminal-exec herdr omasnap: haseen installs them only from Omarchy's [omarchy] repo, which does not list them; no other repository is used and nothing is built from the AUR"
    assert_eq "[omarchy] enabled, lookup $lookup: neither is installed from any source" "" \
        "$(grep -E '^DRYRUN: .*(pacman|paru|yay) .*(herdr|xdg-terminal-exec|omasnap)' <<<"$OUTPUT" || true)"
    assert_contains "[omarchy] enabled, lookup $lookup: the layer completes" "$OUTPUT" "layer desktop applied"
done
