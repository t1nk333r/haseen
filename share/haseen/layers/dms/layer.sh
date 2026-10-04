# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/dms — DankMaterialShell, installed so it can be switched in for the
# haseen shell with `haseen shell use dms`. Never enabled by default.
#
# The package step mirrors DMS's own Arch installer (MIT, AvengeMedia,
# core/internal/distros/arch.go:577-578): Arch's dms-shell depends on the
# virtual dms-shell-compositor, which no compositor package provides, so it is
# assumed installed. DMS's installer (dankinstall) and its config deployer are
# never run: they rewrite ~/.config/hypr, which haseen seeds and the user owns.

LAYER_SUMMARY="DankMaterialShell, switchable in place of the haseen shell (haseen shell use dms)"
LAYER_REQUIRES=(desktop)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# The package installs the unit here (pacman -Fl dms-shell; DMS
# assets/systemd/dms.service). Read-only for haseen.
DMS_UNIT=/usr/lib/systemd/user/dms.service

# dms_prefix — haseen's PREFIX (/usr/local or /usr), resolved from HASEEN_PATH
# = PREFIX/share/haseen. systemd merges dms.service.d/ from every user unit
# path, so the drop-in sits next to haseen-shell.service, not in /usr/lib.
dms_prefix() { (cd "$HASEEN_PATH/../.." && pwd); }

dms_dropin() { printf '%s/lib/systemd/user/dms.service.d/haseen.conf\n' "$(dms_prefix)"; }

dms_dropin_src() { printf '%s/files/haseen.conf\n' "$LAYER_DIR"; }

dms_pkg_installed() { pkg_installed dms-shell || pkg_installed dms-shell-git; }

dms_dropin_current() {
    local f
    f="$(sysroot_path "$(dms_dropin)")"
    [[ -r $f ]] && cmp -s "$f" "$(dms_dropin_src)"
}

dms_active_shell() {
    local f="$HASEEN_USER_STATE/active-shell"
    if [[ -r $f ]]; then head -n1 "$f"; else echo haseen; fi
}

layer_status() {
    local found=0 missing=0
    if dms_pkg_installed; then
        echo "ok: dms-shell installed"
        found=$((found + 1))
        if [[ -r $(sysroot_path "$DMS_UNIT") ]]; then
            echo "ok: $DMS_UNIT"
        else
            echo "warn: $DMS_UNIT missing (reinstall dms-shell)"
            missing=$((missing + 1))
        fi
    else
        echo "missing: dms-shell package"
        missing=$((missing + 1))
    fi
    if dms_dropin_current; then
        echo "ok: conflict drop-in $(dms_dropin)"
        found=$((found + 1))
    elif [[ -e $(sysroot_path "$(dms_dropin)") ]]; then
        echo "warn: $(dms_dropin) differs from the shipped drop-in (re-apply: haseen layer apply dms)"
        found=$((found + 1))
        missing=$((missing + 1))
    else
        echo "missing: conflict drop-in $(dms_dropin)"
        missing=$((missing + 1))
    fi
    echo "ok: active shell: $(dms_active_shell) (switch: haseen shell use dms|haseen)"
    ((missing == 0)) && return 0
    ((found == 0)) && return 1
    return 2
}

layer_apply() {
    (($# == 0)) || die "the dms layer takes no arguments"
    if dms_pkg_installed; then
        info "dms-shell already installed"
    else
        local flags=(--needed)
        $ASSUME_YES && flags+=(--noconfirm)
        run_root pacman -S "${flags[@]}" --assume-installed dms-shell-compositor=1 dms-shell
    fi
    if dms_dropin_current; then
        info "conflict drop-in up to date: $(dms_dropin)"
    else
        write_root_file "$(dms_dropin)" 0644 <"$(dms_dropin_src)"
    fi
    info "DMS is installed but not enabled. Switch: haseen shell use dms (back: haseen shell use haseen)"
    info "optional DMS features (matugen wallpaper theming, cava, qt6-multimedia, ...): pacman -Si dms-shell"
}

layer_remove() {
    (($# == 0)) || die "the dms layer takes no arguments"
    if [[ $(dms_active_shell) == dms ]]; then
        if layer_is_applied shell; then
            info "switching back to the haseen shell first"
            local flags=(--yes)
            $DRY_RUN && flags+=(--dry-run)
            "$(dms_prefix)/bin/haseen-shell-use" haseen "${flags[@]}"
        else
            warn "the shell layer is not applied: stopping DMS with no shell to replace it"
            run systemctl --user disable --now dms.service
            run rm -f "$HASEEN_USER_STATE/active-shell"
        fi
    fi
    local dropin
    dropin="$(dms_dropin)"
    if [[ -e $(sysroot_path "$dropin") ]]; then
        run_root rm -f "$dropin"
        run_root rmdir --ignore-fail-on-non-empty "$(dirname "$dropin")"
        run systemctl --user daemon-reload || warn "systemctl --user daemon-reload failed; it applies at next login"
    fi
    local pkg
    for pkg in dms-shell dms-shell-git; do
        pkg_installed "$pkg" || continue
        info "$pkg stays installed; to remove it, run as root: pacman -Rns $pkg"
    done
}
