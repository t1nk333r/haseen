# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/desktop — Hyprland (Lua) under uwsm, login, portals, audio, fonts and
# the GPU session environment.
#
# GPU handling is ported from omacachy bin/gpu-detect.sh, gpu-setup.sh,
# nvidia.sh and amd-rocm.sh (MIT, Copyright (c) 2025 Mark Roboff; t1nk33r's
# fork): keep whatever driver chwd installed, add only what the session needs
# (VA-API driver, nvidia_drm modeset), and put the environment in uwsm's
# env.d. Detection comes from preflight's GPU_VENDORS (sysfs) instead of
# lspci, which wakes a runtime-suspended dGPU. The ROCm runtime is left to
# layers/ai (ollama-rocm / ggml-hip), its only consumer.

LAYER_SUMMARY="Hyprland (Lua) + uwsm, greetd/tuigreet when no display manager, portals, audio, fonts, GPU session env"
# chaotic: aur: entries prefer Chaotic-AUR binaries over AUR builds (owner, 2026-10-04).
LAYER_REQUIRES=(base chaotic)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# shellcheck source=../base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../base/lib.sh"

# Marks files under /etc that this layer owns and may rewrite.
DESKTOP_MARKER="# Written by haseen layers/desktop"
GREETD_CONFIG=/etc/greetd/config.toml
NVIDIA_MODESET_CONF=/etc/modprobe.d/haseen-nvidia.conf

desktop_config_home() { printf '%s\n' "${XDG_CONFIG_HOME:-$HOME/.config}"; }

# --- GPU -----------------------------------------------------------------------

# gpu_profile — nvidia | amd | intel | hybrid-nvidia | hybrid-amd | none
# (hybrid-*: an integrated GPU drives the desktop and the named dGPU sleeps).
gpu_profile() {
    if has_gpu nvidia; then
        if has_gpu intel || has_gpu amd; then echo hybrid-nvidia; else echo nvidia; fi
    elif has_gpu amd && has_gpu intel; then
        echo hybrid-amd
    elif has_gpu amd; then
        echo amd
    elif has_gpu intel; then
        echo intel
    else
        echo none
    fi
}

# nvidia_has_gsp — the NVIDIA GPU is Turing (device id 0x1e00) or newer, so it
# has GSP firmware: the open kernel module and nvidia-vaapi-driver's direct
# backend work. Unknown ids count as modern (every new card is).
nvidia_has_gsp() {
    local id
    id="$(nvidia_device_id)"
    [[ -n $id ]] || return 0
    ((16#$id >= 0x1e00))
}

nvidia_driver_packages() { installed_packages_matching '^(nvidia(-open)?(-[0-9]+xx)?-(dkms|utils)|linux.*-nvidia(-open)?)$'; }

# desktop_gpu_env — the content of ~/.config/uwsm/env.d/50-haseen-gpu.
desktop_gpu_env() {
    local profile
    profile="$(gpu_profile)"
    cat <<EOF
$DESKTOP_MARKER (GPU: ${GPU_VENDORS:-none}).
# Rewritten on every apply. Put your own overrides in a later file, e.g.
# ~/.config/uwsm/env.d/90-local.
EOF
    case "$profile" in
    nvidia)
        if nvidia_has_gsp; then
            cat <<'EOF'
# NVIDIA, Turing or newer: hardware video decode through nvidia-vaapi-driver.
export LIBVA_DRIVER_NAME=nvidia
export NVD_BACKEND=direct
export MOZ_DISABLE_RDD_SANDBOX=1
EOF
        else
            cat <<'EOF'
# NVIDIA before Turing: no GSP, so nvidia-vaapi-driver's direct backend does
# not work; VA-API stays off and the EGL backend is selected for apps that ask.
export NVD_BACKEND=egl
EOF
        fi
        cat <<'EOF'
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export GBM_BACKEND=nvidia-drm
EOF
        ;;
    amd)
        cat <<'EOF'
# AMD: Mesa's VA-API driver.
export LIBVA_DRIVER_NAME=radeonsi
EOF
        ;;
    intel)
        cat <<'EOF'
# Intel: libva picks iHD (intel-media-driver) or i965 by itself; nothing to set.
EOF
        ;;
    hybrid-nvidia)
        cat <<'EOF'
# Hybrid graphics: the integrated GPU drives the desktop and the NVIDIA GPU
# sleeps until an app asks for it. NVIDIA-wide variables (GBM_BACKEND,
# __GLX_VENDOR_LIBRARY_NAME, LIBVA_DRIVER_NAME) are deliberately NOT set: they
# would route every app to the sleeping dGPU. Offload one app with:
#   prime-run <app>
EOF
        ;;
    hybrid-amd)
        cat <<'EOF'
# Hybrid graphics: the integrated Intel GPU drives the desktop. Offload one
# app to the AMD GPU with:
#   DRI_PRIME=1 <app>
EOF
        ;;
    none)
        echo "# No Intel, AMD or NVIDIA display controller detected; nothing to set."
        ;;
    esac
}

desktop_gpu_system() {
    local profile
    profile="$(gpu_profile)"
    # VA-API for Intel (Broadwell and newer); Mesa already covers AMD.
    if has_gpu intel; then pkg_install intel-media-driver; fi
    if [[ $profile == hybrid-nvidia ]]; then pkg_install nvidia-prime; fi
    has_gpu nvidia || return 0

    local drivers
    drivers="$(nvidia_driver_packages)"
    if [[ -n $drivers ]]; then
        info "gpu: keeping the installed NVIDIA driver ($(tr '\n' ' ' <<<"$drivers" | sed 's/ $//'))"
        if ! nvidia_has_gsp && grep -q -- '-open' <<<"$drivers"; then
            warn "an open NVIDIA kernel module is installed but this GPU predates Turing (no GSP firmware) and will not initialise with it. Switch to the proprietary branch as root: 'chwd -i nvidia-dkms-580xx' (Pascal) or 'chwd -i nvidia-dkms-470xx' (Maxwell)."
        fi
    elif [[ $HASEEN_DISTRO == cachyos ]]; then
        # chwd picks the right NVIDIA profile from its own device-id table.
        # Scope it to display controllers (VGA 0300, 3D 0302) so unrelated
        # hardware profiles are left alone.
        info "gpu: no NVIDIA driver installed; letting CachyOS's chwd choose one"
        run_root chwd -a 0300
        run_root chwd -a 0302
    else
        warn "no NVIDIA driver is installed. Install one first (Turing or newer: nvidia-open; older cards: see the Arch wiki NVIDIA page); haseen does not pick drivers on Arch."
    fi

    [[ $profile == nvidia ]] && nvidia_has_gsp && pkg_install libva-nvidia-driver

    # DRM kernel mode setting is required for Wayland. Recent drivers default
    # to it and CachyOS ships a drop-in; write ours only when nothing sets it.
    local d
    for d in /etc/modprobe.d /usr/lib/modprobe.d; do
        if grep -rqs 'nvidia[-_]drm.*modeset' "$(sysroot_path "$d")"; then
            info "gpu: nvidia_drm modeset already configured under $d"
            return 0
        fi
    done
    write_root_file "$NVIDIA_MODESET_CONF" <<EOF
$DESKTOP_MARKER: DRM kernel mode setting for Wayland.
options nvidia_drm modeset=1 fbdev=1
EOF
    warn "wrote $NVIDIA_MODESET_CONF; it takes effect after the initramfs is rebuilt ('mkinitcpio -P' as root) and a reboot."
}

# --- session env and user files ------------------------------------------------

desktop_session_env() {
    cat <<EOF
$DESKTOP_MARKER. Rewritten on every apply.
# uwsm sources this before Hyprland starts, so the compositor, every systemd
# user unit (haseen-shell.service) and every app share these variables.
export HASEEN_PATH=$(printf '%q' "$HASEEN_PATH")
export TERMINAL=foot
export ELECTRON_OZONE_PLATFORM_HINT=auto
export QT_QPA_PLATFORM='wayland;xcb'
# Cursor: the owner's luna setup (Bibata Modern Ice, 20 px). Override in your
# own ~/.config/uwsm/env.d/ file; Hyprland and GTK pick it up at session start.
export XCURSOR_THEME=Bibata-Modern-Ice
export XCURSOR_SIZE=20
EOF
}

# write_user_file_if_changed DEST — write_user_file, skipped (and silent) when
# DEST already holds exactly this content, so re-applies converge quietly.
write_user_file_if_changed() {
    local dest="$1" content
    content="$(cat)"
    if [[ -r $dest && "$(<"$dest")" == "$content" ]]; then
        return 0
    fi
    printf '%s\n' "$content" | write_user_file "$dest"
}

# desktop_user_setup — everything under $HOME. Unprivileged; also run on its
# own by tests in a scratch HOME.
desktop_user_setup() {
    local cfg hypr
    cfg="$(desktop_config_home)"
    hypr="$cfg/hypr/hyprland.lua"
    if [[ -e $hypr ]] && ! grep -q 'default/hypr/init.lua' "$hypr"; then
        warn "$hypr exists and does not load haseen's defaults; it stays as it is. To use them, add near the top: dofile((os.getenv(\"HASEEN_PATH\") or \"/usr/local/share/haseen\") .. \"/default/hypr/init.lua\")"
    fi
    seed_user_file "$HASEEN_PATH/default/hypr/user/hyprland.lua" "$hypr"
    seed_user_file "$HASEEN_PATH/default/foot/foot.ini" "$cfg/foot/foot.ini"
    # The include target must exist before the first `haseen theme set`.
    seed_user_file "$HASEEN_PATH/default/foot/theme-fallback.ini" "$HASEEN_USER_STATE/current/theme/foot.ini"
    desktop_session_env | write_user_file_if_changed "$cfg/uwsm/env.d/10-haseen"
    desktop_gpu_env | write_user_file_if_changed "$cfg/uwsm/env.d/50-haseen-gpu"
}

# --- login -----------------------------------------------------------------------

desktop_greetd_config() {
    cat <<EOF
$DESKTOP_MARKER. Rewritten on every apply while this line is here;
# delete the line to take the file over.
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --asterisks --cmd 'uwsm start hyprland.desktop'"
user = "greeter"
EOF
}

greetd_config_ours() {
    local f
    f="$(sysroot_path "$GREETD_CONFIG")"
    [[ -r $f ]] && grep -qF "$DESKTOP_MARKER" "$f"
}

greetd_config_current() {
    local f
    f="$(sysroot_path "$GREETD_CONFIG")"
    [[ -r $f && "$(<"$f")" == "$(desktop_greetd_config)" ]]
}

# An enabled display manager (sddm, gdm, plasma-login, …) stays: uwsm's
# "Hyprland (uwsm-managed)" session entry is all it needs. Without one, greetd
# with tuigreet starts Hyprland through uwsm.
desktop_login() {
    local dm
    dm="$(display_manager_unit)"
    if [[ -n $dm && $dm != greetd.service ]]; then
        info "login: $dm is enabled; keeping it. Pick 'Hyprland (uwsm-managed)' in its session menu."
        return 0
    fi
    if [[ $dm == greetd.service ]] && ! greetd_config_ours; then
        info "login: greetd is enabled with a config haseen did not write; leaving $GREETD_CONFIG alone"
        return 0
    fi
    pkg_install greetd greetd-tuigreet
    if greetd_config_current; then
        info "login: $GREETD_CONFIG is current"
    else
        if [[ -e $(sysroot_path "$GREETD_CONFIG") ]] && ! greetd_config_ours &&
            [[ ! -e $(sysroot_path "$GREETD_CONFIG.haseen-orig") ]]; then
            run_root cp -a "$GREETD_CONFIG" "$GREETD_CONFIG.haseen-orig"
        fi
        desktop_greetd_config | write_root_file "$GREETD_CONFIG"
    fi
    # Enable only: starting greetd now would take the VT from under this run.
    [[ $dm == greetd.service ]] || run_root systemctl enable greetd.service
}

# --- layer contract ----------------------------------------------------------------

layer_status() {
    local rc=0 missing=() p out cfg
    out="$(manifest_entries "$LAYER_DIR/packages.txt" repo)"
    while read -r p; do
        [[ -n $p ]] || continue
        pkg_installed "$p" || missing+=("$p")
    done <<<"$out"
    if ((${#missing[@]} > 0)); then
        echo "missing: packages ${missing[*]}"
        rc=1
    else
        echo "ok: packages"
    fi

    local dm
    dm="$(display_manager_unit)"
    if [[ -n $dm ]]; then echo "ok: login ($dm)"; else
        echo "missing: login (no display manager enabled)"
        rc=1
    fi

    cfg="$(desktop_config_home)"
    local f
    for f in hypr/hyprland.lua foot/foot.ini uwsm/env.d/10-haseen; do
        if [[ -e $cfg/$f ]]; then echo "ok: ~/.config/$f"; else
            echo "missing: ~/.config/$f"
            rc=1
        fi
    done
    if [[ -r $cfg/uwsm/env.d/50-haseen-gpu && "$(<"$cfg/uwsm/env.d/50-haseen-gpu")" == "$(desktop_gpu_env)" ]]; then
        echo "ok: GPU session env ($(gpu_profile))"
    else
        echo "warn: GPU session env missing or stale for $(gpu_profile); re-apply desktop"
        ((rc == 0)) && rc=2
    fi
    if [[ -e $cfg/hypr/hyprland.lua ]] && ! grep -q 'default/hypr/init.lua' "$cfg/hypr/hyprland.lua"; then
        echo "warn: ~/.config/hypr/hyprland.lua does not load haseen's defaults"
        ((rc == 0)) && rc=2
    fi
    return "$rc"
}

layer_apply() {
    (($# == 0)) || die "desktop: takes no options (got: $*)"
    desktop_gpu_system
    desktop_login
    desktop_user_setup
    info "desktop: log out and start 'Hyprland (uwsm-managed)' to use it"
}
