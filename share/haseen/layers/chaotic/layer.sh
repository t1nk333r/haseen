# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# chaotic — enable Chaotic-AUR, the prebuilt and signed binary repository for
# AUR packages. The owner prefers it over building from the AUR, which
# lib/packages.sh only falls back to as the last resort.
#
# Steps follow https://aur.chaotic.cx/docs; ported from the owner's waydots
# lib/packages.sh (ensure_chaotic_aur), including its pinned key fingerprint.
# pacman has no drop-in directory for repositories, so the [chaotic-aur]
# stanza is appended to /etc/pacman.conf: the one exception to the drop-in
# rule besides Limine's (docs/architecture.md §3).

LAYER_SUMMARY="Chaotic-AUR: prebuilt AUR packages, preferred over building from the AUR"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

CHAOTIC_KEY_FPR=EF925EA60F33D0CB85C44AD13056513887B78AEB # gitleaks:allow (public GPG key fingerprint)
CHAOTIC_CDN=https://cdn-mirror.chaotic.cx/chaotic-aur

# Usable, not merely configured: a half-failed enable leaves the stanza with
# no database, and every lookup then misses silently. The repo's own
# mirrorlist package is the canary.
chaotic_works() { chaotic_enabled && pkg_repo_has chaotic-aur chaotic-mirrorlist; }

layer_status() {
    if chaotic_works; then
        echo "ok: [chaotic-aur] enabled and its database resolves"
        return 0
    fi
    if chaotic_enabled; then
        echo "warn: [chaotic-aur] is in pacman.conf but its database does not resolve (sudo pacman-key --populate chaotic; sudo pacman -Syy)"
        return 2
    fi
    echo "missing: [chaotic-aur] (haseen layer apply chaotic)"
    return 1
}

layer_apply() {
    (($# == 0)) || die "chaotic layer takes no arguments (got: $*)"
    if chaotic_works; then
        info "Chaotic-AUR already enabled"
        return 0
    fi
    confirm "Enable Chaotic-AUR (prebuilt, signed AUR binaries) in /etc/pacman.conf?" || die "declined"

    run_root pacman-key --recv-key "$CHAOTIC_KEY_FPR" --keyserver keyserver.ubuntu.com
    if ! $DRY_RUN; then
        sudo pacman-key --finger "$CHAOTIC_KEY_FPR" 2>/dev/null | tr -d ' ' | grep -q "$CHAOTIC_KEY_FPR" ||
            die "the Chaotic-AUR key fingerprint does not match $CHAOTIC_KEY_FPR; not trusting it"
    else
        echo "DRYRUN: verify the key fingerprint is $CHAOTIC_KEY_FPR"
    fi
    run_root pacman-key --lsign-key "$CHAOTIC_KEY_FPR"
    run_root pacman -U --noconfirm "$CHAOTIC_CDN/chaotic-keyring.pkg.tar.zst" "$CHAOTIC_CDN/chaotic-mirrorlist.pkg.tar.zst"
    if ! chaotic_enabled; then
        printf '\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist\n' | append_root_file /etc/pacman.conf
    fi
    # A full upgrade, not a bare -Sy: syncing without upgrading and then
    # installing is a partial upgrade.
    local flags=()
    $ASSUME_YES && flags+=(--noconfirm)
    run_root pacman -Syu "${flags[@]}"
    $DRY_RUN || chaotic_works ||
        die "Chaotic-AUR is configured but its database does not resolve: sudo pacman-key --populate chaotic; sudo pacman -Syy"
}
