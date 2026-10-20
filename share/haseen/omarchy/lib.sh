# shellcheck shell=bash
# omarchy/lib.sh — shared by haseen's Omarchy commands. Sourced, never executed.
#
# haseen answers every command Omarchy 4.0.6 ships under /usr/bin, except the
# Apple-hardware ones (plan 093, architecture 5.4). Each lives in
# share/haseen/omarchy/bin/<name>: a link to ../dispatch when its row in
# commands.tsv says what to do (shim, refuse, inert), else a script of its own
# (translate, port). install.sh links them into PREFIX/bin, ahead of
# Omarchy's /usr/bin copies on PATH, and `haseen shell run` puts the directory
# on the shell's PATH.
#
# A command finds haseen from its own location, not the caller's environment:
# it is reached from /usr/local/bin through a link, from a terminal with no
# HASEEN_PATH, from Hyprland's exec and from systemd user units. HASEEN_PATH
# still wins when it is set, as everywhere in haseen (tests point it at a tree
# of recording stubs).

[[ -n ${HASEEN_OMARCHY_LIB:-} ]] && return 0
HASEEN_OMARCHY_LIB=1

HASEEN_OMARCHY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HASEEN_PATH="${HASEEN_PATH:-$(cd "$HASEEN_OMARCHY_DIR/.." && pwd)}"
export HASEEN_PATH
# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

# haseen's own commands sit in bin/ beside share/haseen, in a checkout and
# under PREFIX alike.
HASEEN_BIN="$HASEEN_PATH/../../bin"
# The Omarchy name this process was started as: $0 keeps the link's name.
OMARCHY_NAME="${0##*/}"

# omarchy_row NAME — NAME's commands.tsv row (name, kind, target, note).
omarchy_row() {
    awk -F'\t' -v n="$1" '$1 == n { print; found = 1; exit } END { exit !found }' \
        "$HASEEN_OMARCHY_DIR/commands.tsv"
}

# haseen_exec NAME [ARGS...] — exec haseen's bin/haseen-NAME.
haseen_exec() {
    local cmd="$HASEEN_BIN/haseen-$1"
    shift
    [[ -x $cmd ]] || die "$OMARCHY_NAME: haseen command missing: $cmd"
    exec "$cmd" "$@"
}

# haseen_cmd NAME [ARGS...] — run haseen's bin/haseen-NAME and return its status.
haseen_cmd() {
    local cmd="$HASEEN_BIN/haseen-$1"
    shift
    "$cmd" "$@"
}

# omarchy_refuse WAY WHY — the command exists so that nothing falls through
# to Omarchy's, but doing what Omarchy's does would break a haseen rule or act
# on Omarchy's own install. Say so, why (a sentence) and the haseen way, and
# fail; never pretend to succeed. A WAY of "none: TEXT" means haseen has
# nothing in its place; TEXT says what to do instead.
omarchy_refuse() {
    printf '%s: not available under haseen.\n%s\n' "$OMARCHY_NAME" "$2" >&2
    case $1 in
    "none: "*) printf 'No haseen equivalent: %s\n' "${1#none: }" >&2 ;;
    *) printf 'The haseen way: %s\n' "$1" >&2 ;;
    esac
    exit 1
}

# omarchy_help TEXT — print TEXT and exit 0 when the arguments ask for help.
omarchy_help() {
    local text="$1"
    shift
    case "${1:-}" in
    -h | --help)
        printf '%s\n' "$text"
        exit 0
        ;;
    esac
}

# Omarchy's installed tree, for commands that read what Omarchy ships there
# (they never write it). OMARCHY_PATH is Omarchy's session variable.
OMARCHY_PATH_SYSTEM="${OMARCHY_PATH:-/usr/share/omarchy}"

# qs_instances — every running Quickshell instance, as `qs list -a -j` prints
# it (a JSON array; -a lists instances on every display, and takes no
# --any-display: Quickshell 0.3.2 exits 108 on the pair). Fails, with a
# warning, when Quickshell cannot list them or answers something that is not
# JSON: a caller must not take that for "no instance runs".
qs_instances() {
    local out
    if ! out="$(qs list -a -j)"; then
        warn "could not list Quickshell instances (qs list -a -j failed)"
        return 1
    fi
    [[ -n ${out//[[:space:]]/} ]] || out="[]"
    if ! jq -e 'type == "array"' <<<"$out" >/dev/null 2>&1; then
        warn "could not list Quickshell instances (qs list -a -j printed no JSON array)"
        return 1
    fi
    printf '%s\n' "$out"
}

# omarchy_shell_pids — PIDs of running Quickshell instances whose config is
# Omarchy's shell, one per line; haseen's own shell never counts, even if
# OMARCHY_PATH were a prefix of haseen's tree. Fails as qs_instances does.
omarchy_shell_pids() {
    local instances
    have qs || return 0
    instances="$(qs_instances)" || return 1
    jq -r --arg dir "${OMARCHY_PATH_SYSTEM%/}/shell/" \
        --arg mine "${HASEEN_PATH%/}/shell/" --arg real "$(readlink -f -- "$HASEEN_PATH/shell")/" \
        '.[] | (.config_path // "") as $p
            | select(($p | startswith($dir)) and ($p | startswith($mine) | not) and ($p | startswith($real) | not))
            | .pid' <<<"$instances"
}

# haseen_shell_instance_running — a Quickshell instance of haseen's shell
# runs (`qs -p $HASEEN_PATH/shell`, the path as given or resolved). Exit 2
# when Quickshell cannot tell.
haseen_shell_instance_running() {
    local instances
    instances="$(qs_instances)" || return 2
    jq -e --arg qml "${HASEEN_PATH%/}/shell/shell.qml" --arg real "$(readlink -f -- "$HASEEN_PATH/shell")/shell.qml" \
        'any(.[]; .config_path == $qml or .config_path == $real)' <<<"$instances" >/dev/null
}

# omarchy_shell_stop — stop every running Omarchy shell. Under haseen it is a
# second bar over haseen's (an Omarchy update used to start it on IO, plan
# 093), never the desktop's shell. When Quickshell cannot list its instances
# this says so and goes on: restarting haseen's own shell is still right.
omarchy_shell_stop() {
    local pids pid
    if ! pids="$(omarchy_shell_pids)"; then
        warn "an Omarchy shell, if one runs, was not stopped"
        return 0
    fi
    for pid in $pids; do
        [[ $pid =~ ^[0-9]+$ ]] || continue
        info "stopping Omarchy's shell (pid $pid): haseen's shell is the desktop's"
        # --pid selects the instance; Quickshell rejects --any-display with it.
        run qs kill --pid "$pid" || warn "could not stop Omarchy's shell (pid $pid)"
    done
}

# haseen_lock_held — haseen's lock screen holds this session. haseen.lock
# writes "1 <Hyprland instance>" to $XDG_RUNTIME_DIR/haseen-lock-held while a
# lock is requested and "0" once it is released (plan 091). From outside the
# session (no HYPRLAND_INSTANCE_SIGNATURE), a marker whose Hyprland instance
# still has its runtime directory counts.
haseen_lock_held() {
    local runtime="${XDG_RUNTIME_DIR:-/tmp}" held="" sig=""
    [[ -r $runtime/haseen-lock-held ]] || return 1
    read -r held sig <"$runtime/haseen-lock-held" || true
    [[ $held == 1 ]] || return 1
    if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
        [[ -z $sig || $sig == "$HYPRLAND_INSTANCE_SIGNATURE" ]]
    else
        [[ -z $sig || -d $runtime/hypr/$sig ]]
    fi
}

# active_shell — the desktop shell `haseen shell use` chose: haseen or dms.
active_shell() {
    local f="$HASEEN_USER_STATE/active-shell" shell=haseen
    [[ -r $f ]] && read -r shell <"$f"
    [[ $shell == dms ]] || shell=haseen
    printf '%s\n' "$shell"
}
