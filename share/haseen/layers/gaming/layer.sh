# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/gaming — Steam, Proton, gamemode, MangoHud, gamescope and the 32-bit
# GPU drivers Steam needs.
#
# With the CachyOS repositories enabled it uses cachyos-gaming-meta (Proton
# CachyOS, umu, wine-cachyos, the 32-bit runtime libraries). The larger
# cachyos-gaming-applications (Lutris, Heroic, Faugus, GOverlay) is opt-in
# with --apps: launchers are clutter for someone who only runs Steam.
# Package lists checked against CachyOS-PKGBUILDS master, 2026-10-04.
#
# There is no packages.txt: the set depends on the repositories and the GPU,
# so layer_apply decides it.

LAYER_SUMMARY="Steam, Proton, gamemode, MangoHud, gamescope (CachyOS gaming packages when available)"
LAYER_REQUIRES=(desktop)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# shellcheck source=../base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../base/lib.sh"

layer_usage() {
    cat <<'EOF'
  --apps   also install cachyos-gaming-applications (Lutris, Heroic, Faugus,
           GOverlay); CachyOS repositories only
EOF
}

# gaming_lib32_drivers — 32-bit Vulkan/GL drivers for every GPU present, in
# manifest form (aur:NAME for AUR). For NVIDIA the 32-bit package must match
# the installed driver branch (nvidia-utils, nvidia-580xx-utils, …) or pacman
# refuses the version pair. Legacy branches are in the CachyOS repositories
# but only in the AUR on Arch.
gaming_lib32_drivers() {
    local utils
    if has_gpu amd || has_gpu intel; then echo lib32-mesa; fi
    if has_gpu amd; then echo lib32-vulkan-radeon; fi
    if has_gpu intel; then echo lib32-vulkan-intel; fi
    if has_gpu nvidia; then
        utils="$(installed_packages_matching '^nvidia(-[0-9]+xx)?-utils$' | head -n1)"
        utils="${utils:-nvidia-utils}"
        if [[ $utils != nvidia-utils ]] && ! pacman_repo_enabled cachyos; then
            echo "aur:lib32-$utils"
        else
            echo "lib32-$utils"
        fi
    fi
}

# gaming_packages [--apps] — the full package set for this machine.
gaming_packages() {
    local apps="$1"
    if pacman_repo_enabled cachyos; then
        echo cachyos-gaming-meta
        $apps && echo cachyos-gaming-applications
    fi
    printf '%s\n' steam gamemode lib32-gamemode mangohud lib32-mangohud gamescope
    gaming_lib32_drivers
}

gaming_user_in_group() {
    local group="$1" user="${USER:-$(id -un)}" line
    line="$(grep -E "^$group:" "$(sysroot_path /etc/group)" 2>/dev/null || true)"
    [[ ",${line##*:}," == *",$user,"* ]]
}

gaming_secureboot_note() {
    [[ $SECUREBOOT_STATE == enabled ]] && return 0
    info "anti-cheat games on the Windows side of a dual boot need Secure Boot on (now: $SECUREBOOT_STATE). 'haseen secureboot setup' enrolls haseen's keys together with Microsoft's, so Windows and its anti-cheat keep working."
}

layer_status() {
    local rc=0 missing=() p
    while read -r p; do
        [[ -n $p ]] || continue
        p="${p#aur:}"
        pkg_installed "$p" || missing+=("$p")
    done < <(gaming_packages false)
    if ((${#missing[@]} > 0)); then
        echo "missing: packages ${missing[*]}"
        rc=1
    else
        echo "ok: packages"
    fi
    if pacman_repo_enabled multilib; then echo "ok: [multilib] enabled"; else
        echo "missing: [multilib] repository (Steam is 32-bit)"
        rc=1
    fi
    [[ $SECUREBOOT_STATE == enabled ]] || echo "warn: Secure Boot is $SECUREBOOT_STATE; see 'haseen secureboot setup' for anti-cheat dual boot"
    return "$rc"
}

layer_apply() {
    local apps=false arg
    for arg in "$@"; do
        case "$arg" in
        --apps) apps=true ;;
        *) die "gaming: unknown option '$arg' (see: haseen layer list)" ;;
        esac
    done
    # pacman.conf is the user's; haseen never edits it (layers/base).
    pacman_repo_enabled multilib ||
        die "gaming: the [multilib] repository is not enabled. Steam and the 32-bit drivers live there; uncomment [multilib] and its Include line in /etc/pacman.conf, refresh with 'pacman -Sy' as root, then apply again."
    if $apps && ! pacman_repo_enabled cachyos; then
        warn "gaming: --apps needs the CachyOS repositories; skipping cachyos-gaming-applications"
    fi
    local p repo=() aur=()
    while read -r p; do
        case "$p" in
        aur:*) aur+=("${p#aur:}") ;;
        ?*) repo+=("$p") ;;
        esac
    done < <(gaming_packages "$apps")
    pkg_install "${repo[@]}"
    ((${#aur[@]} == 0)) || pkg_install_aur "${aur[@]}"
    # gamemode's daemon renices and changes the CPU governor only for members
    # of the gamemode group.
    if ! gaming_user_in_group gamemode; then
        run_root usermod -aG gamemode "${USER:-$(id -un)}"
        info "gaming: added ${USER:-$(id -un)} to the gamemode group (log out and back in)"
    fi
    gaming_secureboot_note
}
