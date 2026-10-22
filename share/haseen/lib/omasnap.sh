# shellcheck shell=bash
# omasnap.sh — how haseen starts Omasnap, its screenshot tool (plan 107).
# Sourced after common.sh, never executed.
#
# Omasnap ([omarchy]/omasnap 1.21.0, MIT + OFL-1.1,
# https://github.com/omacom/omasnap) captures the focused monitor before its
# overlay maps, picks a region, a window, the whole monitor or a scrolling
# region, then saves, copies and shows a preview to pin or edit; its editor
# annotates, redacts and reads text (OCR). It replaced Tensaku by owner
# decision (2026-10-21). haseen hands it the folder haseen's screenshots go to
# and the OCR languages haseen reads, and leaves everything else to Omasnap
# and the user's ~/.config/omasnap/omasnap.conf.

[[ -n ${HASEEN_OMASNAP_SH:-} ]] && return 0
HASEEN_OMASNAP_SH=1

# The languages `haseen capture text` reads by default (bin/haseen-capture-text):
# mixed Arabic and English screen text needs both.
HASEEN_OCR_DEFAULT=ara+eng

# screenshot_dir — where haseen's screenshots go: $HASEEN_SCREENSHOT_DIR, else
# the XDG pictures folder, else ~/Pictures (never $HOME itself, which
# xdg-user-dir prints when no pictures folder is configured).
screenshot_dir() {
    local d=${HASEEN_SCREENSHOT_DIR:-}
    [[ -n $d ]] || d="$(xdg-user-dir PICTURES 2>/dev/null || true)"
    [[ -n $d && $d != "$HOME" ]] || d="$HOME/Pictures"
    printf '%s\n' "$d"
}

# omasnap_use — true when a capture should go to Omasnap. HASEEN_SCREENSHOT_TOOL
# picks: auto (unset) uses Omasnap when it is installed; omasnap requires it;
# grim never starts it, so haseen's own slurp/grim capture and Tensaku or
# swappy as the editor are used, as before plan 107.
omasnap_use() {
    case ${HASEEN_SCREENSHOT_TOOL:-auto} in
    auto) have omasnap ;;
    omasnap)
        have omasnap ||
            die "HASEEN_SCREENSHOT_TOOL=omasnap, but omasnap is not installed (haseen layer apply omarchy-repo desktop installs it)"
        ;;
    grim) return 1 ;;
    *) die "HASEEN_SCREENSHOT_TOOL wants auto, omasnap or grim, got: $HASEEN_SCREENSHOT_TOOL" ;;
    esac
}

# omasnap_conf SECTION KEY — KEY's value in [SECTION] of the user's
# omasnap.conf, trimmed (empty when unset). Omasnap reads the file with
# QSettings' INI format (src/output-config.cpp@v1.21.0): exact section and key
# names, surrounding double quotes removed.
omasnap_conf() {
    local file="${XDG_CONFIG_HOME:-$HOME/.config}/omasnap/omasnap.conf"
    [[ -r $file ]] || return 0
    awk -v want="[$1]" -v key="$2" '
        { sub(/\r$/, "") }
        /^[[:space:]]*\[/ { s = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); in_s = (s == want); next }
        in_s && index($0, "=") {
            k = substr($0, 1, index($0, "=") - 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", k)
            if (k != key) next
            v = substr($0, index($0, "=") + 1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
            if (v ~ /^".*"$/) v = substr(v, 2, length(v) - 2)
            val = v
        }
        END { printf "%s", val }
    ' "$file"
}

# omasnap_editor_mode — overlay or window: the editor presentation the user
# chose in omasnap.conf ([editor] mode), which an explicit --editor would
# otherwise override.
omasnap_editor_mode() {
    local mode
    mode="$(omasnap_conf editor mode)"
    [[ ${mode,,} == window ]] && echo window || echo overlay
}

# omasnap_env — set OMASNAP_ENV to the NAME=VALUE words haseen starts Omasnap
# with (for `env`), leaving out any the user decided:
#   OMASNAP_SCREENSHOT_DIR  $HASEEN_SCREENSHOT_DIR when set, else the XDG
#                           pictures folder unless omasnap.conf names its own
#                           ([output] directory); Omasnap's default would be
#                           ~/Pictures/Screenshots, apart from haseen's grim
#                           captures
#   OMASNAP_OCR_LANGS       $HASEEN_OCR_LANGS, else ara+eng unless
#                           OMARCHY_OCR_LANGS is set, which Omasnap reads next
#                           (src/capture.cpp@v1.21.0 recognizeText)
# Omasnap's pins and its notification's edit action are processes it starts,
# so they inherit both.
omasnap_env() {
    OMASNAP_ENV=()
    if [[ -z ${OMASNAP_SCREENSHOT_DIR:-} ]] &&
        { [[ -n ${HASEEN_SCREENSHOT_DIR:-} ]] || [[ -z $(omasnap_conf output directory) ]]; }; then
        OMASNAP_ENV+=("OMASNAP_SCREENSHOT_DIR=$(screenshot_dir)")
    fi
    if [[ -z ${OMASNAP_OCR_LANGS:-} ]]; then
        if [[ -n ${HASEEN_OCR_LANGS:-} ]]; then
            OMASNAP_ENV+=("OMASNAP_OCR_LANGS=$HASEEN_OCR_LANGS")
        elif [[ -z ${OMARCHY_OCR_LANGS:-} ]]; then
            OMASNAP_ENV+=("OMASNAP_OCR_LANGS=$HASEEN_OCR_DEFAULT")
        fi
    fi
}

# omasnap_exec ARGS... — start Omasnap with ARGS and haseen's environment, in
# place of this process (a second press of the same key then dismisses the
# overlay: Omasnap's single-instance lock). Under --dry-run, print it.
omasnap_exec() {
    omasnap_env
    local cmd=(env "${OMASNAP_ENV[@]}" omasnap "$@")
    if $DRY_RUN; then
        echo "DRYRUN: ${cmd[*]}"
        exit 0
    fi
    exec "${cmd[@]}"
}
