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

# write_root_file DEST [MODE] — write stdin as privileged file DEST. Parent
# directories are created. Dry-run prints the content indented so the plan
# shows exactly what would land.
write_root_file() {
    local dest="$1" mode="${2:-0644}"
    if $DRY_RUN; then
        echo "DRYRUN: write $dest (mode $mode):"
        sed 's/^/    | /'
    else
        # install -d creates missing parents at 0755 & ~umask, and sudo ORs
        # the caller's umask in: pin 022 so a 077 owner cannot make shared
        # root state directories (e.g. /var/lib/haseen) untraversable.
        (umask 022; sudo install -d -m 0755 "$(dirname "$dest")")
        sudo tee "$dest" >/dev/null
        sudo chmod "$mode" "$dest"
    fi
}

append_root_file() {
    local dest="$1"
    if $DRY_RUN; then
        echo "DRYRUN: append to $dest:"
        sed 's/^/    | /'
    else
        sudo tee -a "$dest" >/dev/null
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

# seed_user_file SRC DEST — copy SRC to DEST only if DEST does not exist.
# User files are seeded once and then belong to the user; re-runs never
# overwrite them.
seed_user_file() {
    local src="$1" dest="$2"
    [[ -e $dest ]] && return 0
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
