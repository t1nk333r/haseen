# shellcheck shell=bash
# common.sh — helpers shared by every haseen script. Sourced, never executed.
#
# Adapted from omacachy bin/lib/common.sh (t1nk33r, own code).
#
# The dry-run contract: every state-changing command flows through one of the
# helpers below. In dry-run mode they print the command (and, for file writes,
# the full content) instead of running it. Review enforces "no sudo outside
# run_root / write_root_file / append_root_file / install_root_file" with one
# grep, and tests/run.sh enforces "no state change under --dry-run" with PATH
# stubs that fail on any privileged binary.
#
# Reads of system state go through sysroot_path so the fixture trees under
# tests/fixtures/<name>/ can stand in for a real machine (HASEEN_SYSROOT).

[[ -n ${HASEEN_COMMON_SH:-} ]] && return 0
HASEEN_COMMON_SH=1

DRY_RUN=${DRY_RUN:-false}
ASSUME_YES=${ASSUME_YES:-false}

# Where the installed tree lives: share/haseen next to bin/. Works for the repo
# checkout, /usr/local (installer) and /usr (package) alike.
if [[ -z ${HASEEN_PATH:-} ]]; then
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

# root_only_node PATH — PATH (as the inspected system sees it) is owned by
# root and writable by neither its group nor others; prints why not.
root_only_node() {
    local st
    st="$(stat -c '%u %a' -- "${HASEEN_SYSROOT%/}$1" 2>/dev/null)" || {
        echo "$1 does not exist"
        return 1
    }
    ((${st% *} == 0)) || {
        echo "$1 is owned by uid ${st% *}, not root"
        return 1
    }
    if ((8#${st#* } & 8#022)); then
        echo "$1 is writable by its group or by others"
        return 1
    fi
}

# root_trusted_exec PATH... — every PATH is a file only root can change. Each
# is resolved one directory entry at a time, as namei(1) walks it, following
# every symbolic link (inside HASEEN_SYSROOT when set): every directory an
# entry is read from, and the file itself, must pass root_only_node. A pacman
# hook runs its Exec as root, so an Exec that a user could replace, or point
# somewhere else, is root for that user: a haseen run from a checkout fails at
# the checkout's first directory. Prints why not, with the path as the
# inspected system sees it, and returns 1.
root_trusted_exec() {
    local path rest comp cur target hops
    for path in "$@"; do
        [[ $path == /* ]] || {
            echo "$path is not an absolute path"
            return 1
        }
        rest="$path" cur="" hops=0
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
            # Whoever can write this directory decides what the entry is.
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
        root_only_node "$cur" || return 1
        [[ -f ${HASEEN_SYSROOT%/}$cur ]] || {
            echo "$cur is not a regular file"
            return 1
        }
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
