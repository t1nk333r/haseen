# shellcheck shell=bash
# branding.sh — haseen's brand marks (plan 059). Sourced, never executed.
#
# Three original marks ship in share/haseen/branding/<mark>/ (kufic, shield,
# gate), each as mark.svg, symbolic.svg (16 px grid), symbolic-24.svg and
# wordmark.svg, filled with currentColor so the reader colours them, plus a
# terminal rendering in share/haseen/branding/logo-<mark>.txt. The choice is
# `branding.mark` in shell.json, read here and in Haseen/Branding.qml with the
# same rule: an unknown or missing value is kufic.

[[ -n ${HASEEN_BRANDING_SH:-} ]] && return 0
HASEEN_BRANDING_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BRANDING_MARKS=(kufic shield gate)
BRANDING_DEFAULT=kufic
BRANDING_DIR="$HASEEN_PATH/branding"

branding_known() {
    local m
    for m in "${BRANDING_MARKS[@]}"; do
        [[ $m == "${1:-}" ]] && return 0
    done
    return 1
}

# branding_mark — the selected mark: branding.mark from default/shell.json
# merged with the user file. An unreadable user file or a bad value is the
# default, never an error: a logo must not stop `haseen about` or the splash.
branding_mark() {
    local user="$HASEEN_USER_CONFIG/shell.json" mark="" files=("$HASEEN_PATH/default/shell.json")
    [[ -r $user ]] && files+=("$user")
    if have jq; then
        mark="$(jq -rs 'map(objects) | reduce .[] as $o ({}; . * $o) | .branding.mark // "" | strings' \
            "${files[@]}" 2>/dev/null)" || mark=""
    fi
    if branding_known "$mark"; then printf '%s\n' "$mark"; else printf '%s\n' "$BRANDING_DEFAULT"; fi
}

# branding_file KIND [MARK] — the path of KIND (mark, symbolic, symbolic-24,
# wordmark, logo) for MARK, default the selected one.
branding_file() {
    local kind="$1" mark="${2:-$(branding_mark)}"
    case "$kind" in
    logo) printf '%s\n' "$BRANDING_DIR/logo-$mark.txt" ;;
    *) printf '%s\n' "$BRANDING_DIR/$mark/$kind.svg" ;;
    esac
}

# branding_svg KIND COLOR [MARK] — the SVG with currentColor replaced by COLOR,
# for readers that cannot colour it themselves (plymouth, the app icon).
branding_svg() {
    sed "s/currentColor/$2/g" "$(branding_file "$1" "${3:-}")"
}

# branding_accent — the current theme's accent as #rrggbb (the app icon's
# colour), or a neutral grey readable on light and dark backgrounds.
branding_accent() {
    local colors="$HASEEN_USER_STATE/current/theme/colors.toml" accent=""
    [[ -r $colors ]] &&
        accent="$(sed -n 's/^accent[[:space:]]*=[[:space:]]*"\(#[0-9a-fA-F]\{6\}\)".*/\1/p' "$colors" | head -n1)"
    printf '%s\n' "${accent:-#8a8a8a}"
}
