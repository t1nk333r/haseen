# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# layers/flatpak — Flatpak with the Flathub remote, in the user's own
# installation (~/.local/share/flatpak).
#
# Why user scope (plan 017): haseen installs apps Flathub-first from the menu.
# In the user installation, installing, updating and removing an app needs no
# root and no polkit prompt, so `haseen install app`, `haseen remove app` and
# the Flatpak step of `haseen update` never ask for a password. The cost is
# one copy of each runtime per user, which is fine on a single-user desktop.
# Apps already in the system installation keep working: `haseen remove
# flatpak` and `haseen update` handle that scope too.
#
# The flatpak package's systemd user-environment generator adds both export
# directories to XDG_DATA_DIRS, so uwsm-launched sessions see the app
# launchers without any profile edits.

LAYER_SUMMARY="Flatpak + the Flathub remote (per-user installation) for Flathub-first app installs"
LAYER_REQUIRES=(desktop)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

# shellcheck source=../../lib/catalog.sh
source "$HASEEN_PATH/lib/catalog.sh"

layer_status() {
    local rc=0
    if pkg_installed flatpak; then echo "ok: flatpak installed"; else
        echo "missing: package flatpak"
        rc=1
    fi
    if flathub_user_remote_present; then echo "ok: Flathub remote (user)"; else
        echo "missing: Flathub remote in $(flatpak_user_dir)"
        ((rc == 0)) && rc=2
    fi
    return "$rc"
}

layer_apply() {
    (($# == 0)) || die "flatpak: takes no options (got: $*)"
    if flathub_user_remote_present; then
        info "flatpak: Flathub remote already configured for $USER"
    else
        ensure_flathub_user
    fi
    info "flatpak: install apps with 'haseen install app <name>' or 'haseen install flatpak <id>'"
}

layer_remove() {
    # Apps and their data stay; only the remote goes, and only when no user
    # app still depends on it for updates.
    if compgen -G "$(flatpak_user_dir)/app/*" >/dev/null; then
        info "flatpak: user apps are installed; keeping the Flathub remote (remove the apps first)"
        return 0
    fi
    flathub_user_remote_present || return 0
    run flatpak remote-delete --user flathub
}
