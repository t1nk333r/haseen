# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/secureboot — sbctl, the re-sign pacman hook and the status summary.
# Contract: share/haseen/lib/layers.sh. Plan: plans/002-secureboot-layer.md.
#
# Applying the layer never touches firmware keys: key creation, signing and
# enrollment are the explicit, interactive `haseen secureboot setup`.

LAYER_SUMMARY="sbctl own keys + Microsoft + firmware keys, signing hooks, Limine config enrollment"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# BASH_SOURCE, not LAYER_DIR: layer_field sources this file without the env.
# shellcheck source=secureboot.sh
source "$(dirname "${BASH_SOURCE[0]}")/secureboot.sh"

# layer_status — 0 enforcing and fully signed, 1 sbctl or the hook missing,
# 2 installed but Secure Boot not (yet) complete.
layer_status() {
    sb_report && return 0
    $SB_HAVE_SBCTL && $SB_HAVE_HOOK && return 2
    return 1
}

# Refuse before the runner installs sbctl: a BIOS machine gains nothing from it.
layer_precheck() {
    (($# == 0)) || die "secureboot layer takes no arguments (got: $*)"
    [[ $FIRMWARE == uefi ]] || die "Secure Boot needs UEFI firmware; this machine boots in legacy BIOS mode"
}

layer_apply() {
    if sb_hook_current; then
        info "pacman hook up to date: $SB_HOOK_DEST"
    else
        sb_hook_render | write_root_file "$SB_HOOK_DEST" 0644
    fi
    if [[ $SECUREBOOT_STATE == enabled ]] && sb_keys_exist; then
        info "Secure Boot keys exist and Secure Boot is on; the hook keeps the boot chain signed (haseen secureboot status)"
    else
        info "next: haseen secureboot setup (interactive: creates keys, signs the boot chain, enrolls them with Microsoft's and the firmware's keys after a typed confirmation)"
    fi
}

# layer_remove — the hook only. Keys, the firmware enrollment and sbctl's
# signing database stay: removing enrolled keys needs the firmware.
layer_remove() {
    run_root rm -f "$SB_HOOK_DEST"
    info "kept: Secure Boot keys in $(sb_keydir), their firmware enrollment, sbctl and its signing database"
}
