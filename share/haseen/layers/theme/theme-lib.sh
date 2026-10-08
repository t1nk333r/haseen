# shellcheck shell=bash disable=SC2034  # THEME_* globals are read by the commands and tests
# theme-lib.sh — the theme pipeline shared by bin/haseen-theme-* and the theme
# layer. Sourced after lib/common.sh, never executed.
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
#   bin/omarchy-theme-color          colors.toml parser + alias/derive cascade
#   bin/omarchy-theme-set-templates  template renderer (one awk pass)
#   bin/omarchy-theme-set            staging dir, installed-theme denylist
#   bin/omarchy-theme-osc            foot retint via OSC sequences
#   bin/omarchy-theme-set-gnome      GTK colour scheme + Adwaita/Adwaita-dark
#   bin/omarchy-git-url-check        git URL refusal rules
# The colors.toml format and the template syntax ({{ key }}, {{ key_strip }},
# {{ key_rgb }}, {{ mix… }}, {{ hypr_gradient… }}, {{ gradient_start… }},
# {{ shell_gradient… }}) are kept byte-compatible so Omarchy themes and
# Omarchy-style user templates work unchanged.

[[ -n ${HASEEN_THEME_LIB_SH:-} ]] && return 0
HASEEN_THEME_LIB_SH=1

THEME_TEMPLATES_DIR="$HASEEN_PATH/themed"
THEME_STOCK_DIR="$HASEEN_PATH/themes"
THEME_USER_DIR="$HASEEN_USER_CONFIG/themes"
THEME_USER_TEMPLATES_DIR="$HASEEN_USER_CONFIG/themed"
THEME_USER_BACKGROUNDS_DIR="$HASEEN_USER_CONFIG/backgrounds"
THEME_CURRENT_DIR="$HASEEN_USER_STATE/current"
THEME_CURRENT_PATH="$THEME_CURRENT_DIR/theme"
THEME_NEXT_PATH="$THEME_CURRENT_DIR/next-theme"
THEME_NAME_FILE="$THEME_CURRENT_DIR/theme.name"
THEME_BACKGROUND_LINK="$THEME_CURRENT_DIR/background"
# haseen's own theme (plan 066): HANCORE's Greek Noir with the owner's "akane"
# border wipe. Not an Omarchy stock theme, so `theme fetch` has no images for
# it; backgrounds go in ~/.config/haseen/backgrounds/<name>/.
THEME_DEFAULT=haseen
# Renamed stock themes, old name -> current name. `theme set OLD` and an old
# theme.name resolve to the current name, and the current name also finds
# backgrounds under ~/.config/haseen/backgrounds/OLD/.
declare -A THEME_ALIASES=([greek-noir-akane]=haseen)
# Fetched Omarchy images (never shipped: third-party artwork, 64 MB). Pinned
# to one commit of omacom/omarchy; omarchy-assets.txt lists every image with
# its sha256 and size at that commit.
THEME_CACHE_DIR="${HASEEN_USER_CACHE:-${XDG_CACHE_HOME:-$HOME/.cache}/haseen}/themes"
THEME_OMARCHY_REPO=omacom/omarchy
THEME_OMARCHY_COMMIT=5c4da021469517449770579793b37ce26d0a0d48
THEME_ASSETS_MANIFEST="$HASEEN_PATH/layers/theme/omarchy-assets.txt"
# Largest image at the pin is 4.1 MB; anything over this is not one of them.
THEME_ASSET_MAX_BYTES=$((8 * 1024 * 1024))
THEME_BG_UNIT=haseen-background.service
# The user's monospace font (`haseen font set`): one line, a family name.
THEME_FONT_FILE="$HASEEN_USER_CONFIG/font"

# What a theme installed from a git repo may not ship, because these run code:
# Hyprland dofile()s the theme's hyprland.lua and Neovim loads neovim.lua, so no
# *.lua is staged at all; each terminal config names the program the terminal
# launches; vscode.json names an extension (arbitrary JavaScript). Shell
# scripts and anything carrying an exec bit are dropped too: nothing in a theme
# has a reason to be executable. Everything else is colour and is kept.
#
# Adding a template for another terminal, or another editor that loads code,
# means adding it here or to THEME_COLOUR_ONLY below; tests/test-theme.sh fails
# on a template output that is in neither list.
# fonts.conf is here rather than in the colour-only list: fontconfig's
# <include> reads any path, so a stranger's theme could pull a file of its own
# choosing into every application's font configuration.
THEME_INSTALLED_DENIED=(alacritty.toml foot.ini fonts.conf ghostty.conf kitty.conf vscode.json)
# Template outputs reviewed as pure data (colours, sizes, font names).
THEME_COLOUR_ONLY=(btop.theme gtk.css satty.css shell.json yazi.toml)

# Defaults for the non-colour shell tokens. A theme may set any of these in its
# colors.toml; the value then wins, like every other key.
declare -A THEME_TOKEN_DEFAULTS=(
    [font_family]="Inter"
    [font_mono]="JetBrainsMono Nerd Font"
    [font_size]=11
    [radius]=6
    [gap]=6
    [border_width]=1
)

# theme_normalize_name RAW — "Tokyo Night" -> tokyo-night (Omarchy rule). Sets
# REPLY; returns 1 for names that could leave the themes directory.
theme_normalize_name() {
    local name
    name="$(printf '%s' "$1" | sed -E 's/<[^>]+>//g' | tr '[:upper:]' '[:lower:]' | tr ' ' '-')"
    REPLY="$name"
    [[ -n $name && $name != .* && $name != */* ]]
}

# theme_resolve_alias NAME — REPLY = the current name of a renamed stock theme,
# with a one-line notice on stderr; any other name is kept. A user theme
# directory of the old name is the user's own and is kept too.
theme_resolve_alias() {
    REPLY="$1"
    local new="${THEME_ALIASES[$1]:-}"
    [[ -n $new && ! -d $THEME_USER_DIR/$1 ]] || return 0
    printf "theme '%s' is now called '%s'\n" "$1" "$new" >&2
    REPLY="$new"
}

# theme_alias_names NAME — the old names that resolve to NAME, one per line.
theme_alias_names() {
    local old
    for old in "${!THEME_ALIASES[@]}"; do
        if [[ ${THEME_ALIASES[$old]} == "$1" ]]; then printf '%s\n' "$old"; fi
    done | LC_ALL=C sort
}

# theme_exists NAME — a stock or user theme directory exists.
theme_exists() { [[ -d $THEME_STOCK_DIR/$1 || -d $THEME_USER_DIR/$1 ]]; }

# theme_names — stock and user themes, sorted. The glob skips dot dirs, so an
# in-progress `.install-*` clone is never listed.
theme_names() {
    local d
    for d in "$THEME_STOCK_DIR"/*/ "$THEME_USER_DIR"/*/; do
        if [[ -d $d ]]; then basename "$d"; fi
    done | LC_ALL=C sort -u
}

# theme_current_name — the current theme's name; an old name (theme.name
# written before a rename) prints the current one.
theme_current_name() {
    [[ -r $THEME_NAME_FILE ]] || return 1
    local name
    name="$(<"$THEME_NAME_FILE")"
    [[ -n $name ]] || return 1
    theme_resolve_alias "$name"
    printf '%s\n' "$REPLY"
}

# --- colors.toml ------------------------------------------------------------

declare -A THEME_COLORS=()

# _theme_mix START END AMOUNT — REPLY = blend of two #rrggbb colours. AMOUNT is a
# fraction (0.35), a percentage (35%) or a bare number over 1 (35). Integer
# parts-per-million arithmetic, rounded half up like Omarchy's awk.
_theme_mix() {
    local s="${1#\#}" e="${2#\#}" amount="$3" pct=false int frac a i out=""
    REPLY=""
    [[ $s =~ ^[0-9A-Fa-f]{6}$ && $e =~ ^[0-9A-Fa-f]{6}$ ]] || return 1
    [[ $amount == *% ]] && pct=true && amount="${amount%\%}"
    [[ $amount =~ ^[0-9]+([.][0-9]+)?$|^[.][0-9]+$ ]] || return 1
    int="${amount%%.*}"
    frac=""
    [[ $amount == *.* ]] && frac="${amount#*.}"
    frac="${frac}000000"
    a=$((10#${int:-0} * 1000000 + 10#${frac:0:6}))
    if $pct || ((a > 1000000)); then a=$((a / 100)); fi
    ((a > 1000000)) && a=1000000
    for i in 0 2 4; do
        out+="$(printf '%02x' $(((16#${s:i:2} * (1000000 - a) + 16#${e:i:2} * a + 500000) / 1000000)))"
    done
    REPLY="#$out"
}

# colors.toml charset (omarchy-theme-color): letters spelled out because a
# bracket range follows locale collation. Values exclude quotes, backslash and
# anything else that could break out of a rendered config.
_THEME_KEY_RE='^[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-]+$'
_THEME_VALUE_RE='^[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789#(),._+/% -]*$'
_THEME_NAME_RE='^[abcdefghijklmnopqrstuvwxyz0123456789_][abcdefghijklmnopqrstuvwxyz0123456789._+-]*$'

_theme_alias() { [[ -n ${THEME_COLORS[$1]:-} ]] || THEME_COLORS[$1]="${THEME_COLORS[$2]:-}"; }

_theme_derive() { # KEY SOURCE TARGET AMOUNT — KEY = mix(SOURCE, TARGET) unless set
    [[ -n ${THEME_COLORS[$1]:-} ]] && return 0
    _theme_mix "${THEME_COLORS[$2]:-}" "$3" "$4" && THEME_COLORS[$1]="$REPLY"
    return 0
}

# theme_colors_load FILE — parse colors.toml into THEME_COLORS and resolve the
# legacy aliases, derived shades and mode exactly as omarchy-theme-color does.
# Keys/values outside the safe charset are skipped with a warning so a hostile
# theme cannot smuggle text into a rendered config.
theme_colors_load() {
    local file="$1" key value bg lum
    THEME_COLORS=()
    [[ -f $file ]] || return 1

    while IFS='=' read -r key value || [[ -n $key ]]; do
        key="${key//[\"\' ]/}"
        [[ -n $key && $key != \#* ]] || continue
        if [[ $value == *[\"\']* ]]; then
            value="${value#*[\"\']}"
            value="${value%%[\"\']*}"
        else
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"
        fi
        # Letters spelled out: a bracket range follows locale collation.
        if [[ ! $key =~ $_THEME_KEY_RE ]]; then
            warn "colors.toml: skipping key with unsupported characters"
            continue
        fi
        if [[ ! $value =~ $_THEME_VALUE_RE ]]; then
            warn "colors.toml: skipping $key: unsupported characters in value"
            continue
        fi
        THEME_COLORS[$key]="$value"
    done <"$file"

    local -A legacy_palette=(
        [background]=bg [dark_background]=dark_bg [darker_background]=darker_bg
        [lighter_background]=lighter_bg [foreground]=fg [dark_foreground]=dark_fg
        [light_foreground]=light_fg [bright_foreground]=bright_fg
    )
    for key in "${!legacy_palette[@]}"; do _theme_alias "$key" "${legacy_palette[$key]}"; done

    _theme_alias background color0
    _theme_alias foreground color7
    [[ -n ${THEME_COLORS[background]:-} ]] && THEME_COLORS[color0]="${THEME_COLORS[background]}"
    [[ -n ${THEME_COLORS[foreground]:-} ]] && THEME_COLORS[color7]="${THEME_COLORS[foreground]}"

    local -A legacy_ansi=(
        [red]=color1 [green]=color2 [yellow]=color3 [blue]=color4 [magenta]=color5
        [cyan]=color6 [bright_red]=color9 [bright_green]=color10
        [bright_yellow]=color11 [bright_blue]=color12 [bright_magenta]=color13
        [bright_cyan]=color14
    )
    for key in "${!legacy_ansi[@]}"; do _theme_alias "$key" "${legacy_ansi[$key]}"; done
    _theme_alias magenta purple
    _theme_alias bright_magenta bright_purple

    _theme_alias light_foreground color7
    _theme_alias light_foreground foreground
    _theme_alias bright_foreground color15
    _theme_alias bright_foreground foreground
    THEME_COLORS[cursor]="${THEME_COLORS[bright_foreground]:-}"
    _theme_alias lighter_background color0
    _theme_alias lighter_background background
    _theme_alias dark_foreground color8
    _theme_alias dark_foreground foreground
    _theme_alias muted color8
    _theme_alias muted dark_foreground
    _theme_alias selection selection_background
    _theme_alias selection color8
    _theme_alias selection color0
    _theme_alias selection background
    _theme_alias selection_background selection
    _theme_alias selection_foreground bright_foreground
    _theme_alias orange yellow
    # Omarchy leaves {{ accent }} raw for themes that predate it; the shell
    # needs a value, and blue is what Omarchy's own consumers fall back to.
    _theme_alias accent blue
    _theme_derive brown orange "#000000" 50%
    _theme_derive dark_background background "#000000" 25%
    _theme_derive darker_background background "#000000" 50%
    for key in red yellow green cyan blue magenta; do
        _theme_derive "bright_$key" "$key" "#ffffff" 20%
    done
    _theme_alias purple magenta
    _theme_alias bright_purple bright_magenta

    local -A ansi=(
        [color0]=background [color1]=red [color2]=green [color3]=yellow
        [color4]=blue [color5]=magenta [color6]=cyan [color7]=foreground
        [color8]=muted [color9]=bright_red [color10]=bright_green
        [color11]=bright_yellow [color12]=bright_blue [color13]=bright_magenta
        [color14]=bright_cyan [color15]=bright_foreground
    )
    for key in "${!ansi[@]}"; do _theme_alias "$key" "${ansi[$key]}"; done
    for key in "${!legacy_palette[@]}"; do
        [[ -n ${THEME_COLORS[$key]:-} ]] && THEME_COLORS[${legacy_palette[$key]}]="${THEME_COLORS[$key]}"
    done

    # Mode precedence: mode, legacy theme_type, light.mode marker, background
    # luminance, dark.
    _theme_alias mode theme_type
    if [[ -z ${THEME_COLORS[mode]:-} ]]; then
        bg="${THEME_COLORS[background]:-}"
        if [[ -f $(dirname "$file")/light.mode ]]; then
            THEME_COLORS[mode]=light
        elif [[ $bg =~ ^#[0-9A-Fa-f]{6}$ ]]; then
            lum=$((16#${bg:1:2} + 16#${bg:3:2} + 16#${bg:5:2}))
            if ((lum > 382)); then THEME_COLORS[mode]=light; else THEME_COLORS[mode]=dark; fi
        else
            THEME_COLORS[mode]=dark
        fi
    fi
    THEME_COLORS[mode]="${THEME_COLORS[mode],,}"
    [[ ${THEME_COLORS[mode]} == light ]] || THEME_COLORS[mode]=dark
    THEME_COLORS[theme_type]="${THEME_COLORS[mode]}"

    # Shell tokens: numbers must be numbers (they land unquoted in shell.json).
    for key in "${!THEME_TOKEN_DEFAULTS[@]}"; do
        value="${THEME_COLORS[$key]:-}"
        if [[ -n $value && $key != font_family && $key != font_mono && ! $value =~ ^[0-9]+([.][0-9]+)?$ ]]; then
            warn "colors.toml: $key must be a number, using ${THEME_TOKEN_DEFAULTS[$key]}"
            value=""
        fi
        [[ -n $value ]] || THEME_COLORS[$key]="${THEME_TOKEN_DEFAULTS[$key]}"
    done
    _theme_shell_selection
    # Remove keys that resolved to nothing (a theme without e.g. red).
    for key in "${!THEME_COLORS[@]}"; do
        [[ -n ${THEME_COLORS[$key]} ]] || unset "THEME_COLORS[$key]"
    done
    return 0
}

# _theme_contrast A B — REPLY = WCAG contrast ratio of two #rrggbb colours,
# times 100 (integer), or empty when either is not a hex colour.
_theme_contrast() {
    REPLY=""
    [[ $1 =~ ^#[0-9A-Fa-f]{6}$ && $2 =~ ^#[0-9A-Fa-f]{6}$ ]] || return 1
    REPLY="$(awk -v a="${1#\#}" -v b="${2#\#}" '
        function ch(h,   v) { v = index("0123456789abcdef", substr(h, 1, 1)) * 16 + index("0123456789abcdef", substr(h, 2, 1)) - 17
            v /= 255; return v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4 }
        function lum(h) { h = tolower(h); return 0.2126 * ch(substr(h, 1, 2)) + 0.7152 * ch(substr(h, 3, 2)) + 0.0722 * ch(substr(h, 5, 2)) }
        BEGIN { x = lum(a); y = lum(b); if (x < y) { t = x; x = y; y = t }
            printf "%d", int((x + 0.05) / (y + 0.05) * 100) }')"
}

# The shell draws its foreground text on `selection` (highlighted rows, pager
# buttons, switches). Terminals pair selection_background with its own
# selection_foreground instead, so themes often pick a bright accent there
# (haseen: orange under light grey, 2.3:1). shell_selection is that
# colour pulled toward the background until foreground text on it reaches
# 4.5:1 (WCAG AA); a selection that already reads well is kept as is.
_theme_shell_selection() {
    local sel="${THEME_COLORS[selection]:-}" fg="${THEME_COLORS[foreground]:-}"
    local bg="${THEME_COLORS[background]:-}" amount=0 candidate
    THEME_COLORS[shell_selection]="$sel"
    _theme_contrast "$sel" "$fg" || return 0
    ((REPLY >= 450)) && return 0
    [[ $bg =~ ^#[0-9A-Fa-f]{6}$ ]] || return 0
    while ((amount <= 100)); do
        _theme_mix "$sel" "$bg" "$amount%" || return 0
        candidate=$REPLY
        _theme_contrast "$candidate" "$fg"
        if ((REPLY >= 450)); then
            THEME_COLORS[shell_selection]="$candidate"
            return 0
        fi
        amount=$((amount + 5))
    done
    return 0
}

# theme_colors_valid FILE — the minimum a theme needs to render: hex
# background and foreground after alias resolution.
theme_colors_valid() {
    theme_colors_load "$1" 2>/dev/null || return 1
    [[ ${THEME_COLORS[background]:-} =~ ^#[0-9A-Fa-f]{6}$ && ${THEME_COLORS[foreground]:-} =~ ^#[0-9A-Fa-f]{6}$ ]]
}

# --- template rendering -----------------------------------------------------

_THEME_MIX_RE='\{\{[[:space:]]*mix(_strip|_rgb)?[[:space:]]+[A-Za-z0-9_]+[[:space:]]+[A-Za-z0-9_]+[[:space:]]+[0-9]+([.][0-9]+)?%?[[:space:]]*\}\}'
_THEME_GRADIENT_RE='\{\{[[:space:]]*(hypr_gradient|gradient_start|shell_gradient)[[:space:]]+[^}]+[[:space:]]*\}\}'

_theme_trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    REPLY="${v%"${v##*[![:space:]]}"}"
}

_theme_resolve_ref() { # REF [FALLBACK] — palette key, else fallback key, else verbatim
    if [[ -n ${THEME_COLORS[$1]+_} ]]; then
        REPLY="${THEME_COLORS[$1]}"
    elif [[ -n ${2:-} && -n ${THEME_COLORS[$2]+_} ]]; then
        REPLY="${THEME_COLORS[$2]}"
    else
        REPLY="${2:-$1}"
    fi
}

_theme_parse_gradient() { # SPEC — sets GRADIENT_COLORS / GRADIENT_ANGLE
    local part
    local -a parts
    GRADIENT_COLORS=()
    GRADIENT_ANGLE=""
    read -ra parts <<<"$1"
    for part in "${parts[@]}"; do
        if [[ $part =~ ^-?[0-9]+([.][0-9]+)?deg$ ]]; then
            GRADIENT_ANGLE="${part%deg}"
        else
            _theme_trim "$part"
            [[ -n ${THEME_COLORS[$REPLY]+_} ]] && REPLY="${THEME_COLORS[$REPLY]}"
            GRADIENT_COLORS+=("$REPLY")
        fi
    done
}

_theme_shell_hex() { # COLOR — first #rrggbb of hex / rgb() / rgba() / 0xAARRGGBB
    local color="$1" r g b
    [[ -n ${THEME_COLORS[$color]+_} ]] && color="${THEME_COLORS[$color]}"
    if [[ $color =~ ^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$ ]]; then
        REPLY="#${color:1:6}"
    elif [[ $color =~ ^[Rr][Gg][Bb][Aa]?\(([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?\)$ ]]; then
        REPLY="#${BASH_REMATCH[1]}"
    elif [[ $color =~ ^[Rr][Gg][Bb][Aa]?\(([0-9]+),([0-9]+),([0-9]+)(,[0-9.]+)?\)$ ]]; then
        r=${BASH_REMATCH[1]} g=${BASH_REMATCH[2]} b=${BASH_REMATCH[3]}
        ((r > 255)) && r=255
        ((g > 255)) && g=255
        ((b > 255)) && b=255
        printf -v REPLY '#%02x%02x%02x' "$r" "$g" "$b"
    elif [[ $color =~ ^0x[0-9A-Fa-f]{8}$ ]]; then
        REPLY="#${color:4:6}"
    else
        REPLY="$color"
    fi
}

_theme_gradient_token() { # TOKEN — value for a gradient helper token, in REPLY
    local content fn key fallback spec i value
    content="${1#\{\{}"
    content="${content%\}\}}"
    read -r fn key fallback <<<"$content"
    _theme_resolve_ref "$key" "${fallback:-}"
    spec="$REPLY"
    _theme_parse_gradient "$spec"
    case "$fn" in
    hypr_gradient)
        if ((${#GRADIENT_COLORS[@]} == 0)); then
            REPLY="\"$spec\""
        elif ((${#GRADIENT_COLORS[@]} == 1)); then
            REPLY="\"${GRADIENT_COLORS[0]}\""
        else
            value='{ colors = {'
            for i in "${!GRADIENT_COLORS[@]}"; do
                ((i > 0)) && value+=','
                value+=" \"${GRADIENT_COLORS[$i]}\""
            done
            value+=' }'
            [[ -n $GRADIENT_ANGLE ]] && value+=", angle = $GRADIENT_ANGLE"
            REPLY="$value }"
        fi
        ;;
    gradient_start)
        if ((${#GRADIENT_COLORS[@]} == 0)); then _theme_shell_hex "$spec"; else _theme_shell_hex "${GRADIENT_COLORS[0]}"; fi
        ;;
    shell_gradient)
        if ((${#GRADIENT_COLORS[@]} == 0)); then
            REPLY="$spec"
        else
            value="${GRADIENT_COLORS[*]}"
            [[ -n $GRADIENT_ANGLE ]] && value+=" ${GRADIENT_ANGLE}deg"
            REPLY="$value"
        fi
        ;;
    *) return 1 ;;
    esac
}

# theme_template_files — user templates first, then stock; for each output
# name the first one wins, so a user template overrides the stock one.
theme_template_files() {
    local tpl out
    local -A seen=()
    shopt -s nullglob
    for tpl in "$THEME_USER_TEMPLATES_DIR"/*.tpl "$THEME_TEMPLATES_DIR"/*.tpl; do
        out="${tpl##*/}"
        out="${out%.tpl}"
        [[ -n ${seen[$out]:-} ]] && continue
        seen[$out]=1
        printf '%s\n' "$tpl"
    done
    shopt -u nullglob
}

# _theme_window_radius — THEME_COLORS[window_radius]: the one corner radius
# windows and the menu share (plans 046, 068): the inner radius of the shell's
# screen frame, by the rule Config.qml's frameRadius applies. shell.json's
# frame.radius (the user's file over the shipped default) when it is a number
# from 0 to 64, rounded; else twice the theme's radius token. Read with jq
# (base layer); a file jq cannot read counts as absent, as the shell skips it.
_theme_window_radius() {
    local f raw r=""
    if have jq; then
        for f in "$HASEEN_USER_CONFIG/shell.json" "$HASEEN_PATH/default/shell.json"; do
            [[ -r $f ]] || continue
            raw="$(jq -c '.frame.radius // empty' "$f" 2>/dev/null)" || continue
            [[ -n $raw ]] || continue
            r="$(jq -r 'if type == "number" and . >= 0 and . <= 64 then (. + 0.5 | floor) else empty end' <<<"$raw")"
            break
        done
    fi
    if [[ -z $r ]]; then
        # Theme.qml holds the token in an int property, which truncates a
        # fraction (6.5 -> 6); the same here, so the rule cannot drift.
        r="${THEME_COLORS[radius]:-}"
        if [[ $r =~ ^([0-9]+)(\.[0-9]*)?$ ]]; then
            r="${BASH_REMATCH[1]}"
        else
            r="${THEME_TOKEN_DEFAULTS[radius]}"
        fi
        r=$((10#$r * 2))
    fi
    THEME_COLORS[window_radius]="$r"
}

# _theme_window_rounding DIR — the shared radius for Hyprland (plans 046, 068).
# DIR/rounding.lua carries window_radius as decoration.rounding; init.lua loads
# it with the defaults, so `haseen toggle gaps`, hyprmod and the user's files
# still override it. DIR/hyprland.lua (rendered or the theme's own) loads
# later, so it is prefixed with a local `hl` (init.lua's haseen.theme_hl) that
# drops decoration.rounding from its hl.config calls: a theme's own rounding
# never splits the windows from the frame and the menu. A prefix, not a
# suffix, so a file that ends in `return` still parses. The file is
# rewritten, never written through: a user theme may link it.
_theme_window_rounding() {
    local dir="$1" f="$1/hyprland.lua" body=""
    [[ -e $f ]] && body="$(<"$f")"
    [[ -e $f || -L $f ]] && rm -f -- "$f"
    printf '%s\n%s\n\n%s\n' \
        "-- haseen: decoration.rounding is the shared window radius in rounding.lua (plan 046)." \
        "local hl = haseen and haseen.theme_hl and haseen.theme_hl(hl) or hl" \
        "$body" >"$f"
    rm -f -- "$dir/rounding.lua"
    printf '%s\nhl.config({ decoration = { rounding = %s } })\n' \
        "-- haseen: window corners follow the shell's frame (plan 046); written by haseen theme set." \
        "${THEME_COLORS[window_radius]}" >"$dir/rounding.lua"
}

# theme_render_templates DIR — render every template into DIR from
# DIR/colors.toml. A file the theme already ships is never overwritten, so a
# hand-written themes/<name>/foot.ini wins over the template.
theme_render_templates() {
    local dir="$1" key value token tpl out content fn a b amount
    local -a templates pairs=()
    local -A seen=()
    theme_colors_load "$dir/colors.toml" || return 1
    _theme_window_radius
    local font=""
    theme_font_override && font="$REPLY" && THEME_COLORS[font_mono]="$font"
    mapfile -t templates < <(theme_template_files)
    ((${#templates[@]} > 0)) || return 0

    local table mixes
    table="$(mktemp)"
    mixes="$(mktemp)"
    for key in "${!THEME_COLORS[@]}"; do
        value="${THEME_COLORS[$key]}"
        printf '{{ %s }}\037%s\n{{ %s_strip }}\037%s\n' "$key" "$value" "$key" "${value#\#}" >>"$table"
        if [[ $value =~ ^#[0-9A-Fa-f]{6}$ ]]; then
            printf '{{ %s_rgb }}\037%d,%d,%d\n' "$key" "$((16#${value:1:2}))" "$((16#${value:3:2}))" "$((16#${value:5:2}))" >>"$table"
        fi
    done

    while IFS= read -r token; do
        [[ -n ${seen[$token]:-} ]] && continue
        seen[$token]=1
        if [[ $token =~ ^$_THEME_MIX_RE$ ]]; then
            content="${token#\{\{}"
            content="${content%\}\}}"
            read -r fn a b amount <<<"$content"
            _theme_mix "${THEME_COLORS[$a]:-}" "${THEME_COLORS[$b]:-}" "$amount" || continue
            case "$fn" in
            mix) value="$REPLY" ;;
            mix_strip) value="${REPLY#\#}" ;;
            mix_rgb) value="$((16#${REPLY:1:2})),$((16#${REPLY:3:2})),$((16#${REPLY:5:2}))" ;;
            *) continue ;;
            esac
            printf '%s\037%s\n' "$token" "$value" >>"$mixes"
        elif _theme_gradient_token "$token"; then
            printf '%s\037%s\n' "$token" "$REPLY" >>"$mixes"
        fi
    done < <(grep -hEo "$_THEME_MIX_RE|$_THEME_GRADIENT_RE" "${templates[@]}" 2>/dev/null || true)

    for tpl in "${templates[@]}"; do
        out="${tpl##*/}"
        out="${out%.tpl}"
        # A dangling link (a user theme pointing at a file not there yet) is
        # replaced by the render inside the staging copy, never written through.
        if [[ -L $dir/$out && ! -e $dir/$out ]]; then
            rm -f -- "$dir/$out"
        fi
        [[ -e $dir/$out ]] || pairs+=("$tpl" "$dir/$out")
    done

    if ((${#pairs[@]} > 0)); then
        # One process renders every template: each {{ … }} span is looked up
        # whole; unknown spans are left as they are.
        awk -v table="$table" -v mixes="$mixes" '
            function render(line,    out, open, span, token) {
                out = ""
                while ((open = index(line, "{{")) > 0) {
                    span = index(substr(line, open + 2), "}}")
                    if (span == 0) break
                    token = substr(line, open, span + 3)
                    if (token in values) {
                        out = out substr(line, 1, open - 1) values[token]
                        line = substr(line, open + length(token))
                    } else {
                        out = out substr(line, 1, open)
                        line = substr(line, open + 1)
                    }
                }
                return out line
            }
            function load(file,    row, sep) {
                while ((getline row < file) > 0) {
                    sep = index(row, "\037")
                    values[substr(row, 1, sep - 1)] = substr(row, sep + 1)
                }
                close(file)
            }
            BEGIN {
                load(table)
                load(mixes)
                for (i = 1; i < ARGC; i += 2) {
                    tpl = ARGV[i]
                    out = ARGV[i + 1]
                    printf "" > out
                    while ((getline line < tpl) > 0) print render(line) > out
                    close(tpl)
                    close(out)
                }
                exit
            }
        ' "${pairs[@]}"
    fi
    rm -f "$table" "$mixes"
    # A key the theme lacks leaves its {{ placeholder }} behind; name the file
    # instead of letting the app fail to parse it later.
    local i
    for ((i = 1; i < ${#pairs[@]}; i += 2)); do
        grep -q '{{' "${pairs[i]}" && warn "unrendered placeholder left in ${pairs[i]##*/}"
    done
    # The user's font goes after the colours of each terminal config rendered
    # here (a theme-shipped config is left alone). The include sits after the
    # user's own [main] font in the seeded foot.ini, so this one wins.
    if [[ -n $font ]]; then
        for ((i = 1; i < ${#pairs[@]}; i += 2)); do
            case "${pairs[i]##*/}" in
            foot.ini) printf '\n[main]\nfont=%s:size=%s\n' "$font" "${THEME_COLORS[font_size]}" ;;
            kitty.conf) printf '\nfont_family %s\n' "$font" ;;
            # font-family accumulates fallbacks; the empty value resets the list.
            ghostty.conf) printf '\nfont-family = ""\nfont-family = %s\n' "$font" ;;
            alacritty.toml) printf '\n[font.normal]\nfamily = "%s"\n' "$font" ;;
            *) continue ;;
            esac >>"${pairs[i]}"
        done
    fi
    return 0
}

# theme_font_override — REPLY = the family in ~/.config/haseen/font (written by
# `haseen font set`); 1 when there is none. A name outside letters, digits,
# space and ._+- is ignored with a warning: it lands unquoted in configs.
theme_font_override() {
    local font
    REPLY=""
    [[ -r $THEME_FONT_FILE ]] || return 1
    IFS= read -r font <"$THEME_FONT_FILE" || [[ -n $font ]] || return 1
    _theme_trim "$font"
    font="$REPLY"
    REPLY=""
    [[ -n $font ]] || return 1
    if [[ ! $font =~ ^[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\ ._+-]+$ ]]; then
        warn "$THEME_FONT_FILE: unsupported characters in the font name, ignored"
        return 1
    fi
    REPLY="$font"
}

# --- staging ----------------------------------------------------------------

# theme_denied_file PATH — true when an installed (git-cloned) theme may not
# ship PATH. See THEME_INSTALLED_DENIED.
theme_denied_file() {
    local path="$1" name="${1##*/}" d
    [[ -L $path ]] && return 0
    case "$name" in *.lua | *.sh) return 0 ;; esac
    for d in "${THEME_INSTALLED_DENIED[@]}"; do
        [[ $name == "$d" ]] && return 0
    done
    [[ -f $path && -x $path ]]
}

# theme_from_repo DIR — `haseen theme install` clones, so a .git directory
# means a stranger's contents. A plain directory or a symlink to the user's
# own working copy is theirs and stages in full.
theme_from_repo() { [[ ! -L $1 && -d $1/.git ]]; }

# theme_denied_list DIR — relative paths a repo theme would have dropped.
# Dotfiles (.git, .github) are skipped: staging never copies them.
theme_denied_list() {
    local root="$1"
    _theme_walk_denied() {
        local e
        for e in "$1"/*; do
            [[ -e $e || -L $e ]] || continue
            if theme_denied_file "$e"; then
                printf '%s\n' "${e#"$root"/}"
            elif [[ -d $e ]]; then
                _theme_walk_denied "$e"
            fi
        done
    }
    _theme_walk_denied "$root"
    unset -f _theme_walk_denied
}

# _theme_copy_filtered SRC DEST — copy without following symlinks and without
# denied files, at any depth. Dotfiles (.git, .github) are not theme content.
_theme_copy_filtered() {
    local src="$1" dest="$2" e name
    mkdir -p "$dest"
    for e in "$src"/*; do
        [[ -e $e || -L $e ]] || continue
        name="${e##*/}"
        theme_denied_file "$e" && continue
        if [[ -d $e ]]; then
            _theme_copy_filtered "$e" "$dest/$name"
        else
            cp -- "$e" "$dest/$name"
        fi
    done
}

# theme_stage NAME — build THEME_NEXT_PATH: stock theme, then the user theme
# on top (filtered when it came from a repo), then rendered templates. Prints
# dropped files on stderr. Fails, removing the staging dir, without colors.toml.
theme_stage() {
    local name="$1" stock="$THEME_STOCK_DIR/$1" user="$THEME_USER_DIR/$1" dropped
    rm -rf "$THEME_NEXT_PATH"
    mkdir -p "$THEME_NEXT_PATH"
    [[ -d $stock ]] && cp -r -- "$stock"/. "$THEME_NEXT_PATH"/
    if theme_from_repo "$user"; then
        _theme_copy_filtered "$user" "$THEME_NEXT_PATH"
        dropped="$(theme_denied_list "$user" | grep -viE '(^|/)(readme|license|changelog)[^/]*$|\.(md|txt)$' || true)"
        [[ -z $dropped ]] || warn "ignored in $user (installed themes cannot ship code or terminal configs): $(echo "$dropped" | tr '\n' ' ')"
    elif [[ -d $user ]]; then
        cp -r -- "$user"/. "$THEME_NEXT_PATH"/
        rm -rf "$THEME_NEXT_PATH/.git"
    fi
    if ! theme_colors_valid "$THEME_NEXT_PATH/colors.toml"; then
        rm -rf "$THEME_NEXT_PATH"
        warn "theme '$name' has no usable colors.toml (needs hex background and foreground)"
        return 1
    fi
    theme_render_templates "$THEME_NEXT_PATH" || return 1
    _theme_window_rounding "$THEME_NEXT_PATH"
}

# theme_swap NAME — move the staged theme into place and record its name. The
# old tree is moved aside first, so current/theme is missing only between two
# renames, never half-written.
theme_swap() {
    local old="$THEME_CURRENT_DIR/old-theme"
    rm -rf "$old"
    [[ -e $THEME_CURRENT_PATH ]] && mv -- "$THEME_CURRENT_PATH" "$old"
    mv -- "$THEME_NEXT_PATH" "$THEME_CURRENT_PATH"
    rm -rf "$old"
    printf '%s\n' "$1" >"$THEME_NAME_FILE.tmp"
    mv -- "$THEME_NAME_FILE.tmp" "$THEME_NAME_FILE"
}

# theme_link_gtk — GTK 3 and GTK 4 (libadwaita apps included) load
# $XDG_CONFIG_HOME/gtk-{3,4}.0/gtk.css at user priority, above libadwaita's
# palette and an app's own stylesheet. Each is written once with an @import
# of the rendered current/theme/gtk.css, so every later theme set recolours
# newly started GTK apps. An existing gtk.css (or link) is the user's: left
# as it is. An absolute path, because GTK CSS has no ~ or $HOME.
theme_link_gtk() {
    local cfg="${XDG_CONFIG_HOME:-$HOME/.config}" css="$THEME_CURRENT_PATH/gtk.css" v dest
    if [[ $css == *[\"\\$'\n']* ]]; then
        warn "not linking GTK to the theme: unsupported characters in $css"
        return 0
    fi
    for v in 3.0 4.0; do
        dest="$cfg/gtk-$v/gtk.css"
        [[ -e $dest || -L $dest ]] && continue
        write_user_file "$dest" <<EOF
/* Written once by \`haseen theme set\`, yours from now on. The import keeps
 * GTK apps on the current haseen theme; add your own rules below it. */
@import url("$css");
EOF
    done
}

# --- Neovim (LazyVim, haseen.nvim) ----------------------------------------------
# Omarchy points ~/.config/nvim/lua/plugins/theme.lua at its current theme's
# neovim.lua (omarchy-nvim-setup) and ships omarchy-theme-hotreload.lua plus
# all-themes.lua beside it. lazy.nvim's change detection stats every spec file
# every 2 s, following the link, and fires `User LazyReload` when one changed;
# the hot-reload plugin answers it by applying the new colourscheme, and
# all-themes.lua keeps every theme's plugin installed so that works offline.
# haseen links its own copies of the three (share/haseen/default/nvim/).
# haseen.nvim (`haseen setup nvim`, plan 065) is a plain lazy.nvim config;
# its link to haseen-colorscheme.lua stands in for LazyVim.
THEME_NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
THEME_NVIM_PLUGINS="$THEME_NVIM_CONFIG/lua/plugins"
THEME_NVIM_DEFAULTS="$HASEEN_PATH/default/nvim"
THEME_NVIM_BRIDGE=haseen-colorscheme.lua
# Filled by theme_link_nvim: what changed, and what was left because it is
# the user's (or Omarchy's twin still does the job).
THEME_NVIM_CHANGED=()
THEME_NVIM_KEPT=()

# theme_nvim_lazyvim — nvim's config is LazyVim: the theme spec is a lazy.nvim
# spec whose LazyVim entry sets opts.colorscheme, which means nothing elsewhere.
theme_nvim_lazyvim() {
    [[ -f $THEME_NVIM_CONFIG/lazyvim.json ]] || grep -qs 'LazyVim/LazyVim' "$THEME_NVIM_CONFIG/lua/config/lazy.lua"
}

# theme_nvim_haseen — nvim's config is haseen.nvim: lua/plugins holds haseen's
# colourscheme bridge (a dangling link from another prefix counts too), which
# disables the LazyVim entry and applies its colourscheme.
theme_nvim_haseen() {
    [[ -L $THEME_NVIM_PLUGINS/$THEME_NVIM_BRIDGE || -e $THEME_NVIM_PLUGINS/$THEME_NVIM_BRIDGE ]]
}

# theme_nvim_follows — nvim's config takes haseen's theme spec.
theme_nvim_follows() { theme_nvim_lazyvim || theme_nvim_haseen; }

# theme_nvim_omarchy_file PATH — PATH is Omarchy's twin of a haseen nvim file:
# omarchy-theme-hotreload.lua by its name; all-themes.lua when it is the copy
# the omarchy-nvim package seeds or says Omarchy (a user's own list stays).
theme_nvim_omarchy_file() {
    local f
    case "${1##*/}" in
    omarchy-theme-hotreload.lua) [[ -e $1 || -L $1 ]] ;;
    all-themes.lua)
        [[ -f $1 ]] || return 1
        for f in /etc/skel/.config/nvim/lua/plugins/all-themes.lua /usr/share/omarchy-nvim/config/lua/plugins/all-themes.lua; do
            f="$(sysroot_path "$f")"
            [[ -f $f ]] && cmp -s -- "$1" "$f" && return 0
        done
        grep -qi omarchy -- "$1"
        ;;
    *) return 1 ;;
    esac
}

# _theme_nvim_link TARGET LINK ERE — point LINK at TARGET when LINK is absent
# or a symlink whose target matches ERE (one haseen or Omarchy made). A file
# or any other link is the user's and stays. The new link is renamed over the
# old one, so lazy's poll never sees the spec missing.
_theme_nvim_link() {
    local target="$1" link="$2" ere="$3" old="" rel="lua/plugins/${2##*/}"
    if [[ -L $link ]]; then
        old="$(readlink -- "$link")"
        [[ $old == "$target" ]] && return 0
        if [[ ! $old =~ $ere ]]; then
            THEME_NVIM_KEPT+=("nvim $rel links to $old: yours, left as is")
            return 0
        fi
    elif [[ -e $link ]]; then
        THEME_NVIM_KEPT+=("nvim $rel is your own file, left as is")
        return 0
    fi
    run mkdir -p -- "${link%/*}"
    run ln -sfn -- "$target" "$link.haseen-tmp"
    run mv -fT -- "$link.haseen-tmp" "$link"
    if [[ -n $old ]]; then
        THEME_NVIM_CHANGED+=("nvim $rel: $old -> $target")
    else
        THEME_NVIM_CHANGED+=("nvim $rel -> $target")
    fi
}

# theme_link_nvim [--replacing-omarchy] — in a LazyVim or haseen.nvim config,
# link lua/plugins/theme.lua to current/theme/neovim.lua and add haseen's
# hot-reload and theme-plugin list. While Omarchy's twin of either is still in
# lua/plugins, haseen's is not added (both would reload, or list, the same
# thing); `haseen import omarchy` moves the twins aside and passes
# --replacing-omarchy. haseen.nvim's bridge link is repointed when it comes
# from another prefix.
theme_link_nvim() {
    local replacing=false src name twin
    [[ ${1:-} == --replacing-omarchy ]] && replacing=true
    THEME_NVIM_CHANGED=()
    THEME_NVIM_KEPT=()
    theme_nvim_follows || return 0
    # A link to a file that is not there yet would break nvim's startup.
    if $DRY_RUN || [[ -f $THEME_CURRENT_PATH/neovim.lua ]]; then
        _theme_nvim_link "$THEME_CURRENT_PATH/neovim.lua" "$THEME_NVIM_PLUGINS/theme.lua" \
            '/(omarchy|haseen)/current/theme/neovim\.lua$'
    fi
    src="$(readlink -f -- "$THEME_NVIM_DEFAULTS")" || return 0
    for name in haseen-theme-hotreload.lua haseen-all-themes.lua; do
        [[ -f $src/$name ]] || continue
        twin=omarchy-theme-hotreload.lua
        [[ $name == haseen-all-themes.lua ]] && twin=all-themes.lua
        if ! $replacing && theme_nvim_omarchy_file "$THEME_NVIM_PLUGINS/$twin"; then
            THEME_NVIM_KEPT+=("nvim lua/plugins/$twin is Omarchy's and does the job of $name (haseen import omarchy swaps it)")
            continue
        fi
        _theme_nvim_link "$src/$name" "$THEME_NVIM_PLUGINS/$name" "/haseen/default/nvim/${name//./\\.}\$"
    done
    if [[ -L $THEME_NVIM_PLUGINS/$THEME_NVIM_BRIDGE ]]; then
        _theme_nvim_link "$src/$THEME_NVIM_BRIDGE" "$THEME_NVIM_PLUGINS/$THEME_NVIM_BRIDGE" \
            "/haseen/default/nvim/${THEME_NVIM_BRIDGE//./\\.}\$"
    fi
    return 0
}

# theme_backgrounds NAME — candidate images, each source sorted, in this order:
# ~/.config/haseen/backgrounds/<name>/ (the user's), the same folder under each
# old name of a renamed theme (THEME_ALIASES), current/theme/backgrounds/
# (shipped by an installed theme), then the fetched cache
# ~/.cache/haseen/themes/<name>/backgrounds/. Paths are absolute.
theme_backgrounds() {
    local dir old dirs=("$THEME_USER_BACKGROUNDS_DIR/$1")
    while IFS= read -r old; do
        if [[ -n $old ]]; then dirs+=("$THEME_USER_BACKGROUNDS_DIR/$old"); fi
    done < <(theme_alias_names "$1")
    dirs+=("$THEME_CURRENT_PATH/backgrounds" "$THEME_CACHE_DIR/$1/backgrounds")
    for dir in "${dirs[@]}"; do
        [[ -d $dir ]] || continue
        find -L "$dir/" -maxdepth 1 -type f \
            \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \) \
            ! -name '.*' -print 2>/dev/null | LC_ALL=C sort
    done
    return 0
}

# theme_set_background_link PATH — point current/background at PATH, or remove
# it for an empty PATH. A rename over the old link, so a watcher (the shell's
# FileView, haseen-background.service) never sees it missing mid-change.
theme_set_background_link() {
    local tmp="$THEME_CURRENT_DIR/.background.tmp"
    mkdir -p "$THEME_CURRENT_DIR"
    if [[ -n $1 ]]; then
        ln -nsf -- "$1" "$tmp"
        mv -fT -- "$tmp" "$THEME_BACKGROUND_LINK"
    else
        rm -f "$THEME_BACKGROUND_LINK"
    fi
}

# theme_link_background NAME — keep the current background when it belongs to
# this theme, else the first candidate; no candidate removes the link (the
# background service then paints the theme background colour).
theme_link_background() {
    local current first bg
    current="$(readlink "$THEME_BACKGROUND_LINK" 2>/dev/null || true)"
    first=""
    while IFS= read -r bg; do
        [[ -n $bg ]] || continue
        [[ -z $first ]] && first="$bg"
        if [[ $bg == "$current" ]]; then return 0; fi
    done < <(theme_backgrounds "$1")
    theme_set_background_link "$first"
}

# theme_background_active — haseen-background.service is running. systemd
# keeps an invocation:<unit> link in the user runtime dir while a unit is
# active; reading it keeps this a pure check (no systemctl in tests or dry runs).
theme_background_active() {
    [[ -n ${XDG_RUNTIME_DIR:-} && -L $XDG_RUNTIME_DIR/systemd/units/invocation:$THEME_BG_UNIT ]]
}

# theme_background_reload — restart the running background service so swaybg
# shows the new link. Not running (no session, other shell): nothing to do.
theme_background_reload() {
    theme_background_active || return 0
    run systemctl --user try-restart "$THEME_BG_UNIT" || warn "restarting $THEME_BG_UNIT failed"
}

# --- fetched images (haseen theme fetch) ------------------------------------

# theme_asset_base — URL prefix of the pinned Omarchy tree. Raw URLs carry the
# commit, never a branch: branch URLs are cached and served stale.
# HASEEN_THEME_MIRROR replaces the host part (tests use a file:// mirror laid
# out the same way: <mirror>/<commit>/themes/<name>/<file>).
theme_asset_base() {
    printf '%s/%s/themes\n' "${HASEEN_THEME_MIRROR:-https://raw.githubusercontent.com/$THEME_OMARCHY_REPO}" "$THEME_OMARCHY_COMMIT"
}

# theme_assets NAME — "sha256 size relpath" for every image of NAME in the
# pinned manifest (relpath under the theme: backgrounds/x.webp, preview.png).
theme_assets() {
    [[ -r $THEME_ASSETS_MANIFEST ]] || return 0
    awk -v p="$1/" '!/^#/ && NF == 3 && index($3, p) == 1 { print $1, $2, substr($3, length(p) + 1) }' "$THEME_ASSETS_MANIFEST"
}

# theme_asset_names — themes the manifest has images for.
theme_asset_names() {
    [[ -r $THEME_ASSETS_MANIFEST ]] || return 0
    awk '!/^#/ && NF == 3 { sub(/\/.*/, "", $3); print $3 }' "$THEME_ASSETS_MANIFEST" | LC_ALL=C sort -u
}

# theme_assets_missing NAME — true when an image of NAME is absent from the
# cache or has the wrong size (cheap: no hashing; fetch verifies hashes).
theme_assets_missing() {
    local sha size rel f
    while read -r sha size rel; do
        f="$THEME_CACHE_DIR/$1/$rel"
        [[ -f $f && $(stat -c %s -- "$f") == "$size" ]] || return 0
    done < <(theme_assets "$1")
    return 1
}

# theme_fetch_in_background NAME — `haseen theme set` starts a detached fetch
# when the theme has images not yet cached. HASEEN_THEME_FETCH=0 turns it off
# (tests, offline installs); the fetch logs to state/theme-fetch.log.
theme_fetch_in_background() {
    [[ ${HASEEN_THEME_FETCH:-1} != 0 ]] || return 0
    theme_assets_missing "$1" || return 0
    if $DRY_RUN; then
        echo "DRYRUN: haseen-theme-fetch --quiet $1 (detached)"
        return 0
    fi
    mkdir -p "$HASEEN_USER_STATE"
    setsid -f haseen-theme-fetch --quiet "$1" </dev/null >"$HASEEN_USER_STATE/theme-fetch.log" 2>&1 ||
        warn "could not start the background fetch for $1 (run: haseen theme fetch $1)"
}

# --- post-set: retint what is running ---------------------------------------

# theme_retint_foot — foot does not reload its config, so push the palette to
# every running foot terminal as OSC sequences (omarchy-theme-set-foot).
theme_retint_foot() {
    local osc="" key i pid child tty
    theme_colors_load "$THEME_CURRENT_PATH/colors.toml" || return 0
    for key in 10:foreground 11:background 12:cursor 17:selection_background 19:selection_foreground; do
        [[ -n ${THEME_COLORS[${key#*:}]:-} ]] && osc+="\033]${key%%:*};${THEME_COLORS[${key#*:}]}\007"
    done
    for i in {0..15}; do
        [[ -n ${THEME_COLORS[color$i]:-} ]] && osc+="\033]4;$i;${THEME_COLORS[color$i]}\007"
    done
    for pid in $(pgrep -x foot); do
        for child in $(pgrep -P "$pid"); do
            tty="$(readlink "/proc/$child/fd/1" 2>/dev/null || true)"
            [[ $tty == /dev/pts/* ]] && printf '%b' "$osc" >"$tty"
        done
    done
    return 0
}

_theme_running() { pgrep -x "$1" >/dev/null 2>&1; }

# theme_post_set DIR — reload only what is running; every action goes through
# `run`, so --dry-run prints them. DIR holds the new theme's colors.toml and
# icons.theme (the source theme in a dry run, which renders nothing).
# HASEEN_THEME_HEADLESS=1 (installer, chroot, tests) skips this entirely.
theme_post_set() {
    local dir="$1" mode=dark icons="" gtk_theme
    [[ ${HASEEN_THEME_HEADLESS:-0} == 1 ]] && return 0
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && have hyprctl; then
        run hyprctl reload || warn "hyprctl reload failed"
    fi
    if _theme_running foot; then run theme_retint_foot || warn "foot retint failed"; fi
    if _theme_running kitty; then run pkill -USR1 -x kitty || warn "kitty reload failed"; fi
    if _theme_running ghostty; then run pkill -USR2 -x ghostty || warn "ghostty reload failed"; fi
    if _theme_running btop; then run pkill -USR2 -x btop || warn "btop reload failed"; fi
    if [[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] && have gsettings; then
        theme_colors_load "$dir/colors.toml" && mode="${THEME_COLORS[mode]}"
        [[ $mode == light ]] || mode=dark
        run gsettings set org.gnome.desktop.interface color-scheme "prefer-$mode" || warn "gsettings failed"
        # GTK 3 ignores color-scheme; Adwaita has a separate dark theme. Any
        # other GTK theme is the user's choice and stays.
        gtk_theme="$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null || true)"
        gtk_theme="${gtk_theme//\'/}"
        if [[ -z $gtk_theme || $gtk_theme == Adwaita || $gtk_theme == Adwaita-dark ]]; then
            gtk_theme=Adwaita-dark
            [[ $mode == light ]] && gtk_theme=Adwaita
            run gsettings set org.gnome.desktop.interface gtk-theme "$gtk_theme" || warn "gsettings failed"
        fi
        [[ -r $dir/icons.theme ]] && icons="$(<"$dir/icons.theme")"
        if [[ $icons =~ ^[A-Za-z0-9._+-]+$ && -d $(sysroot_path "/usr/share/icons/$icons") ]]; then
            run gsettings set org.gnome.desktop.interface icon-theme "$icons" || warn "gsettings failed"
        fi
    fi
    return 0
}

# --- git URLs (omarchy-git-url-check) ---------------------------------------

# theme_git_url_ok URL — refuse git options, transport helpers (ext::) and
# schemes git should not clone from.
theme_git_url_ok() {
    local url="$1" scheme t
    [[ -n $url ]] || return 1
    [[ $url == -* || $url =~ ^[A-Za-z0-9][A-Za-z0-9+.-]*:: ]] && return 1
    if [[ $url =~ ^([A-Za-z0-9][A-Za-z0-9+.-]*):// ]]; then
        scheme="${BASH_REMATCH[1]}"
        for t in ssh git git+ssh ssh+git http https file; do
            [[ $scheme == "$t" ]] && return 0
        done
        return 1
    fi
    return 0
}

# theme_name_from_url URL — Omarchy rule: basename without .git, minus an
# omarchy-/haseen- prefix and -theme suffix. Sets REPLY; 1 when unusable.
theme_name_from_url() {
    local path="$1" name
    [[ $path != *"://"* && $path == *:* && ${path%%:*} != */* ]] && path="${path#*:}"
    path="${path%/}"
    name="$(basename -- "$path" .git | sed -E 's/^(omarchy|haseen)-//; s/-theme$//' | tr '[:upper:]' '[:lower:]')"
    REPLY="$name"
    [[ $name =~ $_THEME_NAME_RE ]]
}
