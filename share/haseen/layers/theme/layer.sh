# shellcheck shell=bash disable=SC2034  # LAYER_* are read by lib/layers.sh
# theme layer — the theme pipeline (theme-lib.sh, share/haseen/themed,
# share/haseen/themes) needs no packages: rendering is bash + awk. Applying the
# layer gives the invoking user the default theme when they have none, so the
# desktop and shell find current/theme/* on first login.

LAYER_SUMMARY="theme pipeline: Omarchy-format themes rendered for Hyprland, terminals, GTK and the shell"
LAYER_REQUIRES=(base)
LAYER_CONFLICTS=()
LAYER_DISTROS=(cachyos arch omarchy)

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
    return "$rc"
}

layer_apply() {
    _theme_layer_lib
    local name args=("$THEME_DEFAULT")
    if name="$(theme_current_name)" && [[ -d $THEME_CURRENT_PATH ]]; then
        info "theme already set: $name (left as is)"
        return 0
    fi
    $DRY_RUN && args+=(--dry-run)
    "$HASEEN_PATH/../../bin/haseen-theme-set" "${args[@]}"
}
