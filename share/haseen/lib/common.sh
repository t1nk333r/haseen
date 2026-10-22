# shellcheck shell=bash
# common.sh — helpers shared by every haseen script. Sourced, never executed.
#
# Adapted from omacachy bin/lib/common.sh (t1nk33r, own code).
#
# The dry-run contract: every state-changing command flows through one of the
# helpers below. In dry-run mode they print the command (and, for file writes,
# the full content) instead of running it. Review enforces "no sudo outside
# run_root / run_cold / write_root_file / append_root_file / install_root_file"
# with one grep, and tests/run.sh enforces "no state change under --dry-run"
# with PATH stubs that fail on any privileged binary.
#
# Reads of system state go through sysroot_path so the fixture trees under
# tests/fixtures/<name>/ can stand in for a real machine (HASEEN_SYSROOT).

[[ -n ${HASEEN_COMMON_SH:-} ]] && return 0
HASEEN_COMMON_SH=1

DRY_RUN=${DRY_RUN:-false}
ASSUME_YES=${ASSUME_YES:-false}

# Where the installed tree lives: share/haseen next to bin/. Works for the repo
# checkout, /usr/local (installer) and /usr (package) alike. As root it is
# always the tree this file was sourced from, whatever HASEEN_PATH says, so a
# root command never sources a library from a tree an inherited variable
# names (plan 101; bin/haseen does the same before it runs a command). A
# command started directly with a hostile HASEEN_PATH has already sourced
# this file from it: only the router, sudo's env_reset and pacman's clean
# hook environment close that, and the pacman hooks start at the router.
if ((EUID == 0)) || [[ -z ${HASEEN_PATH:-} ]]; then
    HASEEN_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
export HASEEN_PATH

# Test fixtures set this to a directory that mirrors / . Empty on a real host.
HASEEN_SYSROOT=${HASEEN_SYSROOT:-}

# System-wide state written by layers (applied markers). Root-owned.
HASEEN_STATE_DIR=${HASEEN_STATE_DIR:-/var/lib/haseen}
# Per-user locations. The shell, themes and hooks read these.
HASEEN_USER_CONFIG=${HASEEN_USER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/haseen}
HASEEN_USER_STATE=${HASEEN_USER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/haseen}

# sysroot_path /etc/os-release -> the path to READ for that system file.
sysroot_path() { printf '%s%s\n' "$HASEEN_SYSROOT" "$1"; }

# True when we are inspecting a fixture rather than the live machine. Probes
# that need a live kernel/firmware (bootctl, lsblk, sbctl) must skip then.
in_sysroot() { [[ -n $HASEEN_SYSROOT ]]; }

# root_node_stat PATH... — "uid mode type<TAB>path", NUL-terminated, one per
# PATH that exists, in one stat(1) call. The root-only checks below read
# ownership and mode only through it (tests/test-omarchy-guard.sh stands in a
# stat that answers as root would).
root_node_stat() { LC_ALL=C stat --printf '%u %a %F\t%n\0' -- "$@" 2>/dev/null; }

# root_only_record LABEL RECORD — RECORD (root_node_stat's) is owned by root
# and writable by neither its group nor others; prints why not, about LABEL.
root_only_record() {
    local uid mode
    read -r uid mode _ <<<"${2%%$'\t'*}"
    ((uid == 0)) || {
        echo "$1 is owned by uid $uid, not root"
        return 1
    }
    if ((8#$mode & 8#022)); then
        echo "$1 is writable by its group or by others"
        return 1
    fi
}

# root_only_node PATH — PATH (as the inspected system sees it) is owned by
# root and writable by neither its group nor others; prints why not.
root_only_node() {
    local rec
    rec="$(root_node_stat "${HASEEN_SYSROOT%/}$1" | tr -d '\0')" || rec=""
    [[ -n $rec ]] || {
        echo "$1 does not exist"
        return 1
    }
    root_only_record "$1" "$rec"
}

# root_trusted_resolve PATH — resolves PATH one directory entry at a time, as
# namei(1) walks it, following every symbolic link (inside HASEEN_SYSROOT
# when set; `..` after a link is the parent of its target): every directory
# an entry is read from, and what PATH resolves to, must pass root_only_node.
# Prints the resolved path, or why not with status 1. Whoever can write a
# directory on the way decides what the entry in it is: a link kept in one a
# user can write can be pointed elsewhere later, whatever it points at now.
root_trusted_resolve() {
    local path="$1" rest comp cur="" target hops=0
    [[ $path == /* ]] || {
        echo "$path is not an absolute path"
        return 1
    }
    rest="$path"
    while [[ -n $rest ]]; do
        rest="${rest#/}"
        comp="${rest%%/*}"
        if [[ $rest == */* ]]; then rest="${rest#*/}"; else rest=""; fi
        case "$comp" in
        "" | .) continue ;;
        ..)
            cur="${cur%/*}"
            continue
            ;;
        esac
        root_only_node "${cur:-/}" || return 1
        if [[ -L ${HASEEN_SYSROOT%/}$cur/$comp ]]; then
            ((++hops <= 40)) || {
                echo "$path: too many levels of symbolic links"
                return 1
            }
            target="$(readlink -- "${HASEEN_SYSROOT%/}$cur/$comp")"
            [[ $target == /* ]] && cur=""
            rest="$target${rest:+/$rest}"
            continue
        fi
        cur="$cur/$comp"
    done
    root_only_node "${cur:-/}" || return 1
    printf '%s\n' "${cur:-/}"
}

# root_trusted_exec PATH... — every PATH resolves (root_trusted_resolve) to a
# regular file only root can change. A pacman hook runs its Exec as root, so
# an Exec a user could replace, or point somewhere else, is root for that
# user: a haseen run from a checkout fails at the checkout's first directory.
# Prints why not, with the path as the inspected system sees it.
root_trusted_exec() {
    local path real
    for path in "$@"; do
        real="$(root_trusted_resolve "$path")" || {
            printf '%s\n' "$real"
            return 1
        }
        [[ -f ${HASEEN_SYSROOT%/}$real ]] || {
            echo "$real is not a regular file"
            return 1
        }
    done
}

# root_trusted_dir DIR... — every DIR resolves to a directory only root can
# change, and so does every entry directly in it (a link is resolved the same
# way): a file root sources from it can be neither replaced nor edited by
# anyone else. Prints why not.
root_trusted_dir() {
    local dir real top="${HASEEN_SYSROOT%/}" rec name why dir_nodes=()
    for dir in "$@"; do
        real="$(root_trusted_resolve "$dir")" || {
            printf '%s\n' "$real"
            return 1
        }
        [[ -d $top$real ]] || {
            echo "$real is not a directory"
            return 1
        }
        mapfile -d '' dir_nodes < <(find "$top$real" -mindepth 1 -maxdepth 1 -print0)
        ((${#dir_nodes[@]})) || continue
        while IFS= read -r -d '' rec; do
            name="${rec#*$'\t'}"
            name="${name#"$top"}"
            if [[ ${rec%%$'\t'*} == *' symbolic link' ]]; then
                why="$(root_trusted_resolve "$name")" || {
                    printf '%s\n' "$why"
                    return 1
                }
            else
                root_only_record "$name" "$rec" || return 1
            fi
        done < <(root_node_stat "${dir_nodes[@]}")
    done
}

# root_trusted_haseen ROUTER ROUTE [DIR...] — what a pacman hook whose Exec is
# ROUTER (a haseen bin/haseen) with ROUTE's words runs as root is root's
# alone, checked along the router's own resolution (bin/haseen:14-19) so the
# check and what runs are the same files: the router; the command it
# executes, haseen-ROUTE next to the router's readlink -f; the tree it sets as
# HASEEN_PATH, ../share/haseen from there, with every entry in it; and each
# DIR of that tree the command sources from (lib holds common.sh and the
# libraries), with every entry in it. Prints why not.
root_trusted_haseen() {
    local router="$1" route="$2" real bin dir
    shift 2
    real="$(root_trusted_resolve "$router")" || {
        printf '%s\n' "$real"
        return 1
    }
    [[ -f ${HASEEN_SYSROOT%/}$real ]] || {
        echo "$real is not a regular file"
        return 1
    }
    bin="${real%/*}"
    root_trusted_exec "$bin/haseen-$route" || return 1
    root_trusted_dir "$bin/../share/haseen" || return 1
    for dir in "$@"; do
        root_trusted_dir "$bin/../share/haseen/$dir" || return 1
    done
}

run() {
    if $DRY_RUN; then
        echo "DRYRUN: $*"
    else
        "$@"
    fi
}

run_root() {
    if $DRY_RUN; then
        echo "DRYRUN: sudo $*"
    else
        sudo "$@"
    fi
}

# run_polkit CMD... — run CMD as root through polkit (pkexec), for a command
# started from the desktop, where no terminal exists for sudo to ask in.
run_polkit() {
    if $DRY_RUN; then
        echo "DRYRUN: pkexec $*"
    else
        pkexec "$@"
    fi
}

# run_cold CMD... — run CMD, which runs code haseen did not write (an AUR
# helper building PKGBUILDs), without the sudo authorization an earlier step
# cached. The timestamp is dropped before CMD and again after it, and CMD finds
# a `sudo` first on PATH that adds -N (--no-update): every sudo it runs, its
# own or a PKGBUILD's, asks and caches nothing, so no build inherits the
# password the update asked for. A sudo without -N (older, or another
# implementation), or a temporary directory where the wrapper cannot be made
# or run (full, read-only, mounted noexec), gets the dropped timestamp only,
# with a warning. Adapted from Omarchy bin/omarchy-update and
# default/omarchy/sudo-no-update/sudo (MIT, Copyright (c) David Heinemeier
# Hansson), plan 103.
#
# CMD runs in a subshell whose EXIT trap removes the wrapper and drops the
# timestamp, however it ends (plan 111): a Ctrl+C, a closed terminal or a
# SIGTERM, to the whole job or to this shell alone, still runs both once CMD
# has stopped, and the caller's own traps are untouched.
run_cold() {
    if $DRY_RUN; then
        echo "DRYRUN: sudo -k"
        echo "DRYRUN: $* (each sudo it runs is sudo -N: it asks, and caches nothing)"
        echo "DRYRUN: sudo -k"
        return 0
    fi
    local real help tmp
    real="$(command -v sudo)" || die "run_cold: no sudo on PATH"
    # The wrapper's directory goes first on PATH, so it must be absolute and
    # free of ':': a relative entry would be looked up from whatever directory
    # CMD is in (a PKGBUILD's), and a ':' would split it into two entries.
    tmp="${TMPDIR:-/tmp}"
    if [[ $tmp != /* ]]; then
        tmp="$(realpath -e -- "$tmp" 2>/dev/null)" || tmp=/tmp
    fi
    [[ $tmp != *:* ]] || tmp=/tmp
    sudo -k
    # sudo -h prints its usage lines; -N is in their option brackets when this
    # sudo has it (the long-option list does not always name it).
    help="$(LC_ALL=C "$real" -h 2>&1)" || true
    (
        dir="" status=0 why=""
        # shellcheck disable=SC2317  # run by the EXIT trap
        cold_end() {
            [[ -z $dir ]] || rm -rf -- "$dir"
            dir=""
            sudo -k || true
        }
        trap cold_end EXIT
        trap 'exit 130' INT
        trap 'exit 143' TERM
        trap 'exit 129' HUP
        if ! grep -Eq '^usage: sudo .*\[[^]]*N[^]]*\]' <<<"$help"; then
            why="this sudo has no -N (--no-update)"
        elif ! dir="$(mktemp -d "$tmp/haseen-sudo.XXXXXX")"; then
            dir=""
            why="no directory for the wrapper could be made in $tmp"
        elif ! _cold_sudo_wrapper "$dir/sudo" "$real"; then
            why="the wrapper could not be written in $tmp"
        elif ! "$dir/sudo" --haseen-probe 2>/dev/null; then
            why="$tmp cannot run programs"
        fi
        if [[ -n $why ]]; then
            [[ -z $dir ]] || rm -rf -- "$dir"
            dir=""
            warn "$why: $1 runs with the cached authorization dropped, but a password it asks for is cached again"
            "$@" || status=$?
        else
            PATH="$dir:$PATH" "$@" || status=$?
        fi
        exit "$status"
    )
}

# _cold_sudo_wrapper FILE REAL — write run_cold's sudo, which execs REAL with
# -N. The timestamp and informational modes stand alone: -N beside them is an
# error. --haseen-probe only asks whether the wrapper runs at all; an argument,
# so nothing a command inherits can trigger it.
_cold_sudo_wrapper() {
    local q="'${2//\'/\'\\\'\'}'"
    cat >"$1" <<EOF || return 1
#!/bin/sh
if [ \$# -eq 1 ]; then
    case \$1 in
    --haseen-probe) exit 0 ;;
    -k | --reset-timestamp | -K | --remove-timestamp | -h | --help | -V | --version) exec $q "\$1" ;;
    esac
fi
exec $q -N "\$@"
EOF
    chmod 0755 "$1"
}

# write_root_file DEST [MODE] — write stdin as privileged file DEST. Parent
# directories are created. Dry-run prints the content indented so the plan
# shows exactly what would land.
write_root_file() {
    local dest="$1" mode="${2:-0644}"
    if $DRY_RUN; then
        echo "DRYRUN: write $dest (mode $mode):"
        sed 's/^/    | /'
    else
        sudo install -d -m 0755 "$(dirname "$dest")"
        sudo tee "$dest" >/dev/null
        sudo chmod "$mode" "$dest"
    fi
}

# append_root_file DEST — append stdin to privileged file DEST; an existing
# file keeps its mode. sudo keeps the caller's umask, so a DEST that does not
# exist yet is created under umask 022 (0644): a plain `tee -a` under umask
# 077 would leave a root config file only root can read. A DEST this user
# cannot see takes that path too, which still appends.
append_root_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: append to $dest:"
        sed 's/^/    | /'
    elif [[ -e $dest ]]; then
        sudo tee -a "$dest" >/dev/null
    else
        # shellcheck disable=SC2016  # $1 expands in the root shell
        sudo sh -c 'umask 022 && exec tee -a -- "$1" >/dev/null' sh "$dest"
    fi
}

# install_root_file SRC DEST [MODE] — copy a file shipped in the tree.
install_root_file() {
    local src="$1" dest="$2" mode="${3:-0644}"
    if $DRY_RUN; then
        echo "DRYRUN: sudo install -Dm$mode $src $dest"
    else
        sudo install -Dm"$mode" "$src" "$dest"
    fi
}

# write_user_file DEST — write stdin as unprivileged file DEST.
write_user_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: write $dest:"
        sed 's/^/    | /'
    else
        mkdir -p "$(dirname "$dest")"
        cat >"$dest"
    fi
}

# replace_user_file DEST — write stdin over unprivileged file DEST atomically:
# a temporary file beside it, then a rename, so an application reading DEST
# (an editor's state file) never sees it half written. A DEST that is a link
# (a stowed or yadm-managed dotfile) stays one: the file it points to is
# replaced. That file keeps its mode; a new one gets the umask's, as a plain
# write would, not mktemp's 0600.
replace_user_file() {
    local dest tmp
    if $DRY_RUN; then
        echo "DRYRUN: write $1:"
        sed 's/^/    | /'
        return 0
    fi
    dest="$(readlink -m -- "$1")"
    mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp "$dest.XXXXXX")" || return 1
    if [[ -e $dest ]]; then
        chmod --reference="$dest" "$tmp"
    else
        chmod "$(printf '%04o' $((0666 & ~$(umask))))" "$tmp"
    fi
    if ! cat >"$tmp" || ! mv -fT -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
}

# append_user_file DEST — append stdin to unprivileged file DEST, creating it
# and its parents if needed. The caller decides whether appending is right:
# this helper never looks at what is already there.
append_user_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: append to $dest:"
        sed 's/^/    | /'
    else
        mkdir -p "$(dirname "$dest")"
        cat >>"$dest"
    fi
}

# seed_user_file SRC DEST — copy SRC to DEST only if DEST does not exist.
# User files are seeded once and then belong to the user; re-runs never
# overwrite them. A dangling link counts as existing: it is the user's (a
# dotfiles checkout not cloned yet), and following it would create its target.
seed_user_file() {
    local src="$1" dest="$2"
    [[ -e $dest || -L $dest ]] && return 0
    if $DRY_RUN; then
        echo "DRYRUN: seed $dest from $src"
    else
        mkdir -p "$(dirname "$dest")"
        cp -- "$src" "$dest"
    fi
}

have() { command -v "$1" &>/dev/null; }

info() { printf '[*] %s\n' "$*"; }
warn() { printf 'Warning: %s\n' "$*" >&2; }
die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_not_root() {
    [[ $EUID -eq 0 ]] || return 0
    die "do not run this as root: it works on \$HOME and calls sudo itself where needed."
}

require_cmds() {
    local missing=() c
    for c in "$@"; do
        have "$c" || missing+=("$c")
    done
    ((${#missing[@]} == 0)) || die "missing required command(s): ${missing[*]}"
}

# confirm PROMPT — true unless the user declines. Auto-true under ASSUME_YES
# or DRY_RUN so a plan can always be printed unattended.
confirm() {
    local reply
    { $ASSUME_YES || $DRY_RUN; } && return 0
    read -r -p "$1 [y/N] " reply
    [[ $reply =~ ^[Yy]$ ]]
}

# confirm_typed PROMPT WORD — for irreversible steps (firmware key enrollment):
# the user must type WORD exactly. --yes does NOT bypass this; only dry-run does.
confirm_typed() {
    local prompt="$1" word="$2" reply
    $DRY_RUN && return 0
    read -r -p "$prompt Type '$word' to continue: " reply
    [[ $reply == "$word" ]]
}

start_logging() {
    local log="$1"
    mkdir -p "$(dirname "$log")"
    exec > >(tee -a "$log") 2>&1
    info "log: $log"
}

# parse_common_flags "$@" — consumes --dry-run/--yes/-h and leaves the rest in
# the REST array. Callers print their own usage for -h via a usage() function.
parse_common_flags() {
    REST=()
    local arg
    for arg in "$@"; do
        case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --yes | -y) ASSUME_YES=true ;;
        -h | --help)
            if declare -F usage >/dev/null; then usage; else echo "Usage: $(basename "$0") [--dry-run] [--yes]"; fi
            exit 0
            ;;
        *) REST+=("$arg") ;;
        esac
    done
}
