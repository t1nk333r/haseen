# shellcheck shell=bash
# terminal.sh — run interactive haseen commands in a floating terminal.
# Sourced, never executed.
#
# The menu and key binds start commands with no TTY. Commands that need one
# (fzf pickers, password and passphrase prompts, pacman progress) call
#
#     in_floating_terminal "$@"      # first thing, with the script's own args
#
# which re-execs the script inside $TERMINAL (foot when unset) with app-id
# haseen.floating; a window rule floats and centres that app-id. The terminal
# stays open after the command ends so its output can be read.
#
# It returns (and the script continues inline) when stdin is already a TTY,
# when the arguments contain --dry-run or --help (a printed plan needs no
# terminal), or when HASEEN_INLINE=1 (tests drive prompts through pipes).
#
# floating_terminal_exec CMD ARGS... is the same launcher for any command.

[[ -n ${HASEEN_TERMINAL_SH:-} ]] && return 0
HASEEN_TERMINAL_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

HASEEN_FLOAT_APP_ID=haseen.floating

# floating_terminal_argv CMD ARGS... — set FLOAT_ARGV to the terminal command
# line that runs CMD and waits for Enter afterwards. Each terminal names its
# Wayland app-id flag differently; unknown terminals get only -e.
floating_terminal_argv() {
    local term="${TERMINAL:-foot}" hold
    have "$term" || term=foot
    have "$term" || die "no terminal found: set \$TERMINAL or install foot"
    # The wrapped command's exit code is shown, then Enter closes the window.
    # 130 is Ctrl-C: the user already chose to leave.
    # shellcheck disable=SC2016  # expands in the terminal's bash, not here
    hold='"$@"; rc=$?; ((rc == 130)) && exit 130; printf "\n[%s] press Enter to close " "$( ((rc == 0)) && echo done || echo "failed: exit $rc")"; read -r _; exit "$rc"'
    case "${term##*/}" in
    foot) FLOAT_ARGV=("$term" "--app-id=$HASEEN_FLOAT_APP_ID" --title=haseen) ;;
    kitty | ghostty) FLOAT_ARGV=("$term" "--class=$HASEEN_FLOAT_APP_ID" --title=haseen) ;;
    alacritty) FLOAT_ARGV=("$term" --class "$HASEEN_FLOAT_APP_ID" --title haseen) ;;
    wezterm) FLOAT_ARGV=("$term" start --class "$HASEEN_FLOAT_APP_ID") ;;
    *) FLOAT_ARGV=("$term") ;;
    esac
    FLOAT_ARGV+=(-e bash -c "$hold" bash "$@")
}

# floating_terminal_exec CMD ARGS... — replace this process with a floating
# terminal running CMD. Dry-run prints the command line instead.
floating_terminal_exec() {
    floating_terminal_argv "$@"
    if $DRY_RUN; then
        echo "DRYRUN: ${FLOAT_ARGV[*]}"
        return 0
    fi
    exec "${FLOAT_ARGV[@]}"
}

# in_floating_terminal "$@" — see the header. Never returns when it re-execs.
in_floating_terminal() {
    [[ -t 0 || ${HASEEN_INLINE:-} == 1 ]] && return 0
    local a
    for a in "$@"; do
        case "$a" in --dry-run | -h | --help) return 0 ;; esac
    done
    $DRY_RUN && return 0
    floating_terminal_exec "$(readlink -f "$0")" "$@"
}
