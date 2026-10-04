# shellcheck shell=bash
# layers.sh — the layer runner. Sourced, never executed.
#
# A layer is a directory share/haseen/layers/<name>/ holding:
#
#   layer.sh       REQUIRED. Sourced in a subshell. Defines:
#                    LAYER_SUMMARY="one line"
#                    LAYER_REQUIRES=(other layers applied first)
#                    LAYER_CONFLICTS=(layers that must not be applied with it)
#                    LAYER_DISTROS=(cachyos arch omarchy)   # installer targets
#                    layer_status   read-only; prints "ok: …" / "missing: …" /
#                                   "warn: …" lines; returns 0 applied and
#                                   healthy, 1 not applied, 2 degraded
#                    layer_apply    idempotent; every mutation through the
#                                   common.sh helpers; receives the layer's
#                                   own arguments ("$@")
#                    layer_remove   optional; undoes what is safely reversible
#                    layer_usage    optional; prints the layer's own flags
#   packages.txt   optional manifest (lib/packages.sh), installed by the runner
#                  before layer_apply
#   files/         optional, anything the layer installs
#
# The runner sources common.sh, preflight.sh and packages.sh into the layer's
# subshell and runs preflight_all first, so layers read HASEEN_DISTRO,
# BOOTLOADER, ESP_PATH, SECUREBOOT_STATE, GPU_VENDORS and friends directly.
# LAYER_DIR is the layer's own directory.
#
# Applied state: /var/lib/haseen/layers/<name> (key=value lines).

[[ -n ${HASEEN_LAYERS_SH:-} ]] && return 0
HASEEN_LAYERS_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# shellcheck source=preflight.sh
source "$(dirname "${BASH_SOURCE[0]}")/preflight.sh"
# shellcheck source=packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"

HASEEN_LAYERS_DIR=${HASEEN_LAYERS_DIR:-$HASEEN_PATH/layers}

haseen_version() {
    local v
    v="$(cat "$HASEEN_PATH/VERSION" 2>/dev/null || echo unknown)"
    printf '%s\n' "$v"
}

layer_dir() { printf '%s/%s\n' "$HASEEN_LAYERS_DIR" "$1"; }

layer_exists() { [[ -r $(layer_dir "$1")/layer.sh ]]; }

# layer_names — every layer shipped, sorted.
layer_names() {
    local d
    for d in "$HASEEN_LAYERS_DIR"/*/; do
        [[ -r $d/layer.sh ]] && basename "$d"
    done
}

# layer_field NAME VAR — print a scalar or array variable from layer.sh
# without running any of its functions.
layer_field() {
    local name="$1" var="$2"
    (
        # shellcheck disable=SC1090,SC1091
        source "$(layer_dir "$name")/layer.sh"
        declare -n ref="$var" 2>/dev/null || exit 0
        if [[ $(declare -p "$var" 2>/dev/null) == "declare -a"* ]]; then
            printf '%s\n' "${ref[@]}"
        else
            printf '%s\n' "${ref:-}"
        fi
    )
}

layer_state_file() { sysroot_path "$HASEEN_STATE_DIR/layers/$1"; }

layer_is_applied() { [[ -r $(layer_state_file "$1") ]]; }

layer_mark_applied() {
    printf 'version=%s\napplied=%s\n' "$(haseen_version)" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" |
        write_root_file "$HASEEN_STATE_DIR/layers/$1"
}

layer_mark_removed() { run_root rm -f "$HASEEN_STATE_DIR/layers/$1"; }

# resolve_layers NAME... — print NAME and its requirements in apply order
# (dependencies first, each once). Dies on unknown layers and cycles.
resolve_layers() {
    local -A state=()
    local order=()
    _visit() {
        local n="$1" dep
        layer_exists "$n" || die "unknown layer: $n (see: haseen layer list)"
        case "${state[$n]:-}" in
        done) return 0 ;;
        active) die "layer dependency cycle through: $n" ;;
        esac
        state[$n]=active
        while read -r dep; do
            [[ -n $dep ]] && _visit "$dep"
        done < <(layer_field "$n" LAYER_REQUIRES)
        state[$n]="done"
        order+=("$n")
    }
    local n
    for n in "$@"; do _visit "$n"; done
    unset -f _visit
    printf '%s\n' "${order[@]}"
}

# check_conflicts NAME... — die if any pair in the set (plus layers already
# applied) declares a conflict.
check_conflicts() {
    local -a set=("$@")
    local n c other
    for other in $(layer_names); do
        layer_is_applied "$other" && set+=("$other")
    done
    for n in "$@"; do
        while read -r c; do
            [[ -n $c ]] || continue
            for other in "${set[@]}"; do
                [[ $other == "$c" ]] && die "layer $n conflicts with $c (remove one first: haseen layer remove $c)"
            done
        done < <(layer_field "$n" LAYER_CONFLICTS)
    done
}

# _layer_env NAME — the preamble every layer subshell runs.
_layer_env() {
    LAYER_NAME="$1"
    LAYER_DIR="$(layer_dir "$1")"
    export LAYER_NAME LAYER_DIR
    preflight_all
    # shellcheck disable=SC1090,SC1091
    source "$LAYER_DIR/layer.sh"
}

# layer_run_status NAME — prints the layer's status lines; returns its code.
layer_run_status() {
    (
        _layer_env "$1"
        layer_status
    )
}

# layer_run_apply NAME [ARGS...] — distro gate, packages, layer_apply, marker.
layer_run_apply() {
    local name="$1"
    shift
    (
        _layer_env "$name"
        local d ok=false
        for d in "${LAYER_DISTROS[@]}"; do
            [[ $d == "$HASEEN_DISTRO" ]] && ok=true
        done
        $ok || die "layer $name does not support distro '$HASEEN_DISTRO' (supports: ${LAYER_DISTROS[*]})"
        info "layer $name: $LAYER_SUMMARY"
        if [[ -r $LAYER_DIR/packages.txt ]]; then
            pkg_install_manifest "$LAYER_DIR/packages.txt"
        fi
        layer_apply "$@"
        layer_mark_applied "$name"
        info "layer $name applied"
    )
}

layer_run_remove() {
    local name="$1"
    shift
    (
        _layer_env "$name"
        declare -F layer_remove >/dev/null || die "layer $name has no remove step"
        layer_remove "$@"
        layer_mark_removed "$name"
        info "layer $name removed"
    )
}
