# shellcheck shell=bash
# haseen's shell fragment — the single entry point. `haseen seed user` appends
# one line to ~/.bashrc (and ~/.zshrc if it exists) that sources this file.
# haseen owns everything under default/shell/ and replaces it on upgrade; your
# rc stays yours.
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# default/bash/{rc,init,shell}.
#
# Changes from upstream:
#   - bash and zsh are both supported, so the file names the shell it is in
#     once and passes it to `zoxide init`, `mise activate` and fzf;
#   - every tool is behind `command -v`: a machine without eza, zoxide, mise,
#     fzf or bat loses that feature and prints nothing, instead of an error on
#     every prompt;
#   - `cd` is NOT replaced by zoxide. Omarchy aliases cd to a jump function;
#     silently landing in another directory because a path was mistyped is a
#     bad default for a shell that also runs the owner's scripts. `z` and `zi`
#     are there when you want them;
#   - starship, try and the completions file are not wired: haseen ships none
#     of them.

# Where we live, so the siblings can be sourced without the rc knowing paths.
if [ -n "${ZSH_VERSION:-}" ]; then
    _haseen_shell=zsh
    # %x is the file being sourced; $0 is that only with FUNCTION_ARGZERO set
    # (not under `emulate sh`). zsh-only syntax, so bash never parses it.
    eval '_haseen_self="${(%):-%x}"'
else
    _haseen_shell=bash
    _haseen_self="${BASH_SOURCE[0]}"
fi

# This file is sourced from an interactive rc, so bash expands the user's
# aliases while it reads it: Omarchy's `alias cd=zd` prints and may land
# elsewhere. `builtin` and a quoted `\.` reach the real commands.
HASEEN_SHELL_DIR="$(CDPATH='' builtin cd -- "$(dirname -- "$_haseen_self")" >/dev/null && builtin pwd -P)"
unset _haseen_self

# shellcheck source=share/haseen/default/shell/aliases.sh
\. "$HASEEN_SHELL_DIR/aliases.sh"
# shellcheck source=share/haseen/default/shell/functions.sh
\. "$HASEEN_SHELL_DIR/functions.sh"

# VAPT layer PATH, only while the layer owns this link (layers/vapt/
# environment.sh creates and removes it). A plain test and source: nothing runs.
_haseen_vapt="${XDG_CONFIG_HOME:-$HOME/.config}/haseen/vapt/shell.sh"
# shellcheck source=share/haseen/default/vapt/shell.sh
[ -r "$_haseen_vapt" ] && \. "$_haseen_vapt"
unset _haseen_vapt

# zoxide: `z partial-name` jumps, `zi` picks interactively.
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init "$_haseen_shell")"
fi

# mise: this is what puts the runtimes `haseen install <development entry>`
# manages on PATH. lib/catalog.sh counts on this line existing.
if command -v mise >/dev/null 2>&1; then
    eval "$(mise activate "$_haseen_shell")"
    # mise swaps shims per directory, so a hashed path goes stale.
    [ "$_haseen_shell" = bash ] && set +h
fi

# fzf: Ctrl-R history, Ctrl-T files, Alt-C directories. Only interactive
# shells can bind keys.
if command -v fzf >/dev/null 2>&1; then
    case $- in
    *i*)
        if [ -f "/usr/share/fzf/key-bindings.$_haseen_shell" ]; then
            # shellcheck disable=SC1090  # the distro's file, named per shell
            . "/usr/share/fzf/key-bindings.$_haseen_shell"
            # shellcheck disable=SC1090
            [ -f "/usr/share/fzf/completion.$_haseen_shell" ] &&
                . "/usr/share/fzf/completion.$_haseen_shell"
        else
            # fzf 0.48+ generates them itself when the distro ships no files.
            eval "$(fzf "--$_haseen_shell" 2>/dev/null)" || true
        fi
        ;;
    esac
fi

# bat as the man pager: colour and search inside man pages. -c makes groff
# emit the overstrike bat's man syntax expects.
if command -v bat >/dev/null 2>&1; then
    export MANPAGER="sh -c 'col -bx | bat -l man -p'"
    export MANROFFOPT="-c"
fi

unset _haseen_shell
