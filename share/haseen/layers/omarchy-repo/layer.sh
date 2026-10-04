# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# omarchy-repo — Omarchy's signed package repository (pkgs.omarchy.org) as a
# binary source for leaf packages that are not in the official repos or
# Chaotic-AUR, such as ttfx (the screensaver's text effects).
#
# It is a package source only, never a base (ADR 0001):
#   - the stanza goes LAST in pacman.conf, so for the dozen names it shares
#     with core/extra/CachyOS (ghostty, gpu-screen-recorder, the limine hooks,
#     …) the official package keeps winning;
#   - lib/packages.sh asks it after Chaotic-AUR and before the AUR;
#   - `omarchy` and `omarchy-settings` are refused by name (PKG_DENY): they
#     overwrite pacman.conf, the mirrorlist and the initramfs HOOKS.
#
# Trust follows Omarchy's own bin/omarchy-update-keyring (MIT): key
# 40DFB630FF42BCFFB047046CF0134EE680CAC571 from keys.openpgp.org, verified by
# fingerprint, then omarchy-keyring. SigLevel Required DatabaseOptional is the
# setting omacachy uses for this repo.

LAYER_SUMMARY="Omarchy's package repo, last in pacman.conf: leaf packages like ttfx prebuilt, never Omarchy itself"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

OMARCHY_KEY_FPR=40DFB630FF42BCFFB047046CF0134EE680CAC571
OMARCHY_REPO_SERVER='https://pkgs.omarchy.org/stable/$arch'

omarchy_repo_works() { omarchy_repo_enabled && pkg_repo_has omarchy omarchy-keyring; }

layer_status() {
    if omarchy_repo_works; then
        echo "ok: [omarchy] enabled and its database resolves"
        local last
        last="$(pkg_enabled_repos | tail -n1)"
        [[ $last == omarchy ]] || echo "warn: [omarchy] is not the last repo in pacman.conf ($last is); its packages can shadow official ones"
        return 0
    fi
    if omarchy_repo_enabled; then
        echo "warn: [omarchy] is in pacman.conf but its database does not resolve (sudo pacman -Syy)"
        return 2
    fi
    echo "missing: [omarchy] (haseen layer apply omarchy-repo)"
    return 1
}

layer_apply() {
    (($# == 0)) || die "omarchy-repo layer takes no arguments (got: $*)"
    if omarchy_repo_works; then
        info "[omarchy] already enabled"
        return 0
    fi
    confirm "Add Omarchy's package repository (last in /etc/pacman.conf, leaf packages only)?" || die "declined"

    run_root pacman-key --recv-keys "$OMARCHY_KEY_FPR" --keyserver keys.openpgp.org
    if ! $DRY_RUN; then
        sudo pacman-key --finger "$OMARCHY_KEY_FPR" 2>/dev/null | tr -d ' ' | grep -q "$OMARCHY_KEY_FPR" ||
            die "the Omarchy key fingerprint does not match $OMARCHY_KEY_FPR; not trusting it"
    else
        echo "DRYRUN: verify the key fingerprint is $OMARCHY_KEY_FPR"
    fi
    run_root pacman-key --lsign-key "$OMARCHY_KEY_FPR"
    if ! omarchy_repo_enabled; then
        printf '\n[omarchy]\nSigLevel = Required DatabaseOptional\nServer = %s\n' "$OMARCHY_REPO_SERVER" |
            append_root_file /etc/pacman.conf
    fi
    local flags=()
    $ASSUME_YES && flags+=(--noconfirm)
    # Full upgrade, not -Sy (partial upgrades); then the keyring, so key
    # rotations arrive through pacman from now on.
    run_root pacman -Syu "${flags[@]}"
    run_root pacman -S --needed "${flags[@]}" omarchy/omarchy-keyring
    $DRY_RUN || omarchy_repo_works ||
        die "[omarchy] is configured but its database does not resolve: sudo pacman -Syy"
}
