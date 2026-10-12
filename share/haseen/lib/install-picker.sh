# shellcheck shell=bash
# install-picker.sh — the guided choice ./install.sh offers at a terminal:
# which layers to apply and which optional setup steps to run after them,
# remembered so a re-run can offer "reuse last choices". Sourced by
# install.sh, never executed. Plan: plans/063-install-picker.md.
#
# The idea (a guided picker that remembers the last answer) comes from
# aphotic-hypr's installer; that project is GPL, so nothing of its code or
# text is used here.
#
# The choice lives in $HASEEN_USER_CONFIG/install.toml as a flat TOML subset:
#
#   layers = ["base", "chaotic", "desktop"]
#   setup = ["keyd"]
#   dotfiles_url = "https://example.com/dotfiles.git"
#
# TOML rather than JSON because install.sh runs before the base layer installs
# jq: three flat keys are read and written with bash builtins alone, and the
# file stays something a person edits by hand (like a theme's colors.toml).
#
# The UI is gum when it is installed and stdin and stdout are a terminal;
# otherwise a bash `select` toggle list on stdin, which is what `--pick` with
# scripted stdin (and the tests) drive. End of input accepts what is ticked.

[[ -n ${HASEEN_INSTALL_PICKER_SH:-} ]] && return 0
HASEEN_INSTALL_PICKER_SH=1
# shellcheck source=layers.sh
source "$(dirname "${BASH_SOURCE[0]}")/layers.sh"

# Optional setup steps, in the order they run after the layers. Each is the
# `haseen setup <step>` command; all start off (owner rule).
PICKER_SETUP_STEPS=(keyd fingerprint geoclue dotfiles)

PICK_LAYERS=()
PICK_SETUP=()
PICK_DOTFILES_URL=""
PICK_REUSED=false

picker_file() { printf '%s/install.toml\n' "$HASEEN_USER_CONFIG"; }

_picker_has() { # NEEDLE ITEM... — NEEDLE is one of the ITEMs
    local needle="$1" x
    shift
    for x in "$@"; do
        [[ $x == "$needle" ]] && return 0
    done
    return 1
}

# A URL is stored between double quotes without escapes, so it may hold none.
_picker_url_ok() { [[ -n $1 && $1 != *[[:space:]\"\\]* ]]; }

# _picker_toml_list VALUE NAME — the strings of a TOML array of strings into
# the array NAME. Returns 1 when VALUE is not an array.
_picker_toml_list() {
    local -n _out="$2"
    local part parts=()
    _out=()
    [[ $1 =~ ^\[(.*)\]$ ]] || return 1
    IFS=, read -r -a parts <<<"${BASH_REMATCH[1]}"
    for part in "${parts[@]}"; do
        part="${part#"${part%%[![:space:]]*}"}"
        part="${part%"${part##*[![:space:]]}"}"
        [[ -z $part ]] && continue
        [[ $part =~ ^\"([^\"]*)\"$ ]] && part="${BASH_REMATCH[1]}"
        _out+=("$part")
    done
}

# picker_load FILE — read a saved choice into PICK_*. Unknown layers and steps
# are dropped with a warning. Returns 1 when there is no usable choice.
picker_load() {
    local file="$1" line key value x list=()
    PICK_LAYERS=()
    PICK_SETUP=()
    PICK_DOTFILES_URL=""
    [[ -r $file ]] || return 1
    while IFS= read -r line || [[ -n $line ]]; do
        [[ $line =~ ^[[:space:]]*([a-z_]+)[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$ ]] || continue
        key="${BASH_REMATCH[1]}" value="${BASH_REMATCH[2]}"
        case "$key" in
        layers)
            _picker_toml_list "$value" list || continue
            for x in "${list[@]}"; do
                if ! layer_exists "$x"; then
                    warn "$file: unknown layer '$x', dropped"
                elif ! _picker_pickable "$x"; then
                    warn "$file: layer '$x' needs its own arguments and is not picked here, dropped (see ./install.sh --help)"
                else
                    PICK_LAYERS+=("$x")
                fi
            done
            ;;
        setup)
            _picker_toml_list "$value" list || continue
            for x in "${list[@]}"; do
                if _picker_has "$x" "${PICKER_SETUP_STEPS[@]}"; then
                    PICK_SETUP+=("$x")
                else
                    warn "$file: unknown setup step '$x', dropped"
                fi
            done
            ;;
        dotfiles_url)
            [[ $value =~ ^\"([^\"]*)\"$ ]] && PICK_DOTFILES_URL="${BASH_REMATCH[1]}"
            ;;
        esac
    done <"$file"
    _picker_check_dotfiles
    ((${#PICK_LAYERS[@]} > 0))
}

# The dotfiles step needs its repository; without a usable URL it is dropped.
_picker_check_dotfiles() {
    local x kept=()
    _picker_has dotfiles "${PICK_SETUP[@]}" || return 0
    _picker_url_ok "$PICK_DOTFILES_URL" && return 0
    info "no usable dotfiles URL; skipping the dotfiles step"
    for x in "${PICK_SETUP[@]}"; do
        [[ $x == dotfiles ]] || kept+=("$x")
    done
    PICK_SETUP=("${kept[@]}")
    PICK_DOTFILES_URL=""
}

_picker_join() { # ITEM... — "a, b" or "none"
    local IFS=,
    local s="$*"
    printf '%s\n' "${s:-none}" | sed 's/,/, /g'
}

# picker_summary — the choice in two lines, for the prompt and the reuse offer.
picker_summary() {
    printf '    layers: %s\n' "$(_picker_join "${PICK_LAYERS[@]}")"
    printf '    setup:  %s%s\n' "$(_picker_join "${PICK_SETUP[@]}")" \
        "${PICK_DOTFILES_URL:+ (dotfiles from $PICK_DOTFILES_URL)}"
}

_picker_gum() { have gum && [[ -t 0 && -t 1 ]]; }

# _picker_yes PROMPT — yes unless the user says no; end of input is yes.
_picker_yes() {
    local reply=""
    if _picker_gum; then
        gum confirm --default=true "$1"
        return
    fi
    read -r -p "$1 [Y/n] " reply || true
    [[ ! $reply =~ ^[Nn] ]]
}

# _picker_input PROMPT — one line from the user; end of input is empty.
_picker_input() {
    local reply=""
    if _picker_gum; then
        gum input --placeholder "$1" || true
        return 0
    fi
    read -r -p "$1 " reply || true
    printf '%s\n' "$reply"
}

_picker_setup_summary() {
    sed -n 's/^# haseen:summary[[:space:]]*//p' "$HASEEN_PATH/../../bin/haseen-setup-$1" | head -n1
}

# _picker_toggle TITLE ITEMS SELECTED DESCRIBE — let the user tick ITEMS (an
# array name); SELECTED (an array name) holds the ticked ones before and
# after, in ITEMS order. DESCRIBE prints an item's one-line summary.
_picker_toggle() {
    local title="$1" describe="$4" i n choice out
    local -n _items="$2" _sel="$3"
    local -A desc=() on=()
    for i in "${_items[@]}"; do desc[$i]="$("$describe" "$i")"; done
    for i in "${_sel[@]}"; do on[$i]=1; done

    if _picker_gum; then
        printf '%s\n' "$title" >&2
        for i in "${_items[@]}"; do printf '  %-13s %s\n' "$i" "${desc[$i]}" >&2; done
        local args=(choose --no-limit --height "$((${#_items[@]} + 2))" --header "$title")
        ((${#_sel[@]} > 0)) && args+=(--selected "$(IFS=,; printf '%s' "${_sel[*]}")")
        out="$(gum "${args[@]}" "${_items[@]}")" || die "install picker cancelled"
        on=()
        while IFS= read -r i; do
            [[ -n $i ]] && on[$i]=1
        done <<<"$out"
    else
        local opts=() PS3
        n=${#_items[@]}
        PS3="Toggle a number, or $((n + 1)) to continue: "
        printf '%s\n' "$title" >&2
        while :; do
            opts=()
            for i in "${_items[@]}"; do
                if [[ -n ${on[$i]:-} ]]; then
                    opts+=("$(printf '[x] %-13s %s' "$i" "${desc[$i]}")")
                else
                    opts+=("$(printf '[ ] %-13s %s' "$i" "${desc[$i]}")")
                fi
            done
            opts+=(continue)
            REPLY="" choice=""
            select choice in "${opts[@]}"; do break; done
            # select only leaves with an empty REPLY at end of input.
            [[ -z $REPLY || $choice == continue ]] && break
            [[ -z $choice ]] && continue
            i="${_items[REPLY - 1]}"
            if [[ -n ${on[$i]:-} ]]; then unset 'on[$i]'; else on[$i]=1; fi
        done
    fi
    _sel=()
    for i in "${_items[@]}"; do
        if [[ -n ${on[$i]:-} ]]; then _sel+=("$i"); fi
    done
}

# A layer that needs its own arguments (LAYER_PICKABLE=false, e.g. vapt's
# explicit groups) is never offered: applied bare it would refuse and abort
# the install after earlier layers applied. Its installer flags are the route.
_picker_pickable() { [[ $(layer_field "$1" LAYER_PICKABLE) != false ]]; }

# picker_run CORE_LAYER... — the guided choice into PICK_*. A saved choice is
# offered for reuse first; declining it starts the picker from that choice.
# Without one, the CORE layers start ticked and everything optional starts off.
picker_run() {
    local core=("$@") optional=() all=() n url
    for n in $(layer_names); do
        _picker_has "$n" "${core[@]}" || ! _picker_pickable "$n" || optional+=("$n")
    done
    # shellcheck disable=SC2034  # read by name in _picker_toggle
    all=("${core[@]}" "${optional[@]}")

    if picker_load "$(picker_file)"; then
        info "last install choices ($(picker_file)):"
        picker_summary
        if _picker_yes "Reuse last choices?"; then
            PICK_REUSED=true
            return 0
        fi
    else
        PICK_LAYERS=("${core[@]}")
        PICK_SETUP=()
        PICK_DOTFILES_URL=""
    fi

    _picker_toggle "Layers to apply (a layer's requirements are added for it):" \
        all PICK_LAYERS _picker_layer_summary
    ((${#PICK_LAYERS[@]} > 0)) || die "no layer chosen; ./install.sh --tree-only installs the tree alone"
    _picker_toggle "Optional setup steps, run after the layers:" \
        PICKER_SETUP_STEPS PICK_SETUP _picker_setup_summary
    if _picker_has dotfiles "${PICK_SETUP[@]}"; then
        url="$(_picker_input "Dotfiles git URL${PICK_DOTFILES_URL:+ [$PICK_DOTFILES_URL]} (empty skips):")"
        [[ -n $url ]] && PICK_DOTFILES_URL="$url"
        _picker_check_dotfiles
    else
        PICK_DOTFILES_URL=""
    fi
    return 0
}

_picker_layer_summary() { layer_field "$1" LAYER_SUMMARY; }

_picker_toml_strings() { # ITEM... — a TOML array of strings
    local out="" x
    for x in "$@"; do out+="${out:+, }\"$x\""; done
    printf '[%s]\n' "$out"
}

# picker_save — write the choice for the next run (a reused one is unchanged).
picker_save() {
    $PICK_REUSED && return 0
    {
        echo "# haseen install choices, written by ./install.sh (plans/063-install-picker.md)."
        echo "# A re-run at a terminal offers to reuse them. Edit or delete freely."
        printf 'layers = %s\n' "$(_picker_toml_strings "${PICK_LAYERS[@]}")"
        printf 'setup = %s\n' "$(_picker_toml_strings "${PICK_SETUP[@]}")"
        [[ -z $PICK_DOTFILES_URL ]] || printf 'dotfiles_url = "%s"\n' "$PICK_DOTFILES_URL"
    } | write_user_file "$(picker_file)"
}

# picker_run_setup HASEEN_BIN FLAG... — run the chosen setup steps through
# HASEEN_BIN. A failed step is reported and the rest still run: the layers
# are already applied, and each step can be re-run on its own.
picker_run_setup() {
    local bin="$1" step args
    shift
    for step in "${PICK_SETUP[@]}"; do
        args=(setup "$step")
        case "$step" in
        keyd | geoclue) args+=(on) ;;
        dotfiles) args+=("$PICK_DOTFILES_URL") ;;
        esac
        info "setup step: haseen ${args[*]}"
        HASEEN_PATH="$(dirname "$bin")/../share/haseen" "$bin" "${args[@]}" "$@" ||
            warn "haseen ${args[*]} failed; the layers are applied, run it again on its own"
    done
}
