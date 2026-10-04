# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# theme layer — the theme pipeline (theme-lib.sh, share/haseen/themed,
# share/haseen/themes) renders with bash + awk. Applying the layer gives the
# invoking user the default theme when they have none, so the desktop and
# shell find current/theme/* on first login, and enables
# haseen-background.service (swaybg showing current/background).

LAYER_SUMMARY="theme pipeline: Omarchy-format themes rendered for Hyprland, terminals, GTK and the shell; swaybg background"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

THEME_BG_WANTS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/graphical-session.target.wants/haseen-background.service"

_theme_layer_lib() {
    # shellcheck source=theme-lib.sh
    source "$LAYER_DIR/theme-lib.sh"
}

layer_status() {
    _theme_layer_lib
    local n name rc=0
    n="$(theme_names | wc -l)"
    if ((n > 0)); then
        echo "ok: $n themes available"
    else
        echo "missing: no themes in $THEME_STOCK_DIR"
        rc=2
    fi
    if name="$(theme_current_name)" && [[ -f $THEME_CURRENT_PATH/shell.json ]]; then
        echo "ok: current theme $name"
    else
        echo "missing: no theme set for ${USER:-$(id -un)} (haseen theme set $THEME_DEFAULT)"
        ((rc != 0)) || rc=1
    fi
    if have swaybg; then
        echo "ok: swaybg installed"
    else
        echo "missing: swaybg (backgrounds are not shown)"
        ((rc != 0)) || rc=1
    fi
    # The enable symlink, not `systemctl is-enabled`: status stays a pure read.
    if [[ -L $THEME_BG_WANTS ]]; then
        echo "ok: haseen-background.service enabled"
    else
        echo "missing: haseen-background.service not enabled"
        ((rc != 0)) || rc=1
    fi
    return "$rc"
}

layer_apply() {
    _theme_layer_lib
    local name args=("$THEME_DEFAULT")
    if [[ -L $THEME_BG_WANTS ]]; then
        info "haseen-background.service already enabled"
    else
        run systemctl --user enable haseen-background.service
    fi
    if name="$(theme_current_name)" && [[ -d $THEME_CURRENT_PATH ]]; then
        info "theme already set: $name (left as is)"
        return 0
    fi
    $DRY_RUN && args+=(--dry-run)
    "$HASEEN_PATH/../../bin/haseen-theme-set" "${args[@]}"
}

layer_remove() {
    if [[ -L $THEME_BG_WANTS ]]; then
        run systemctl --user disable haseen-background.service
    fi
    info "kept the current theme and the fetched images in ~/.cache/haseen/themes"
}
