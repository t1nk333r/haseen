# shellcheck shell=bash
# haseen's aliases. Sourced by default/shell/init.sh, which is sourced by one
# line in ~/.bashrc (and ~/.zshrc). haseen owns this file: it is replaced on
# upgrade, so put your own aliases in your rc, not here.
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# default/bash/aliases. Changes: every alias is behind a `command -v` guard, so
# a machine without the tool keeps the real `ls` instead of an alias that
# fails on every prompt; `cd` is not replaced by zoxide (init.sh explains why);
# the agent/rails/docker one-letter aliases are left to the user's own rc; an
# alias the user's rc already defines is kept (the include is the rc's last
# line, so haseen's would otherwise replace it).

# _haseen_alias NAME VALUE — define NAME unless the user already has it.
function _haseen_alias {
    # shellcheck disable=SC2139  # expanding now is the point: NAME=VALUE
    alias "$1" >/dev/null 2>&1 || alias "$1=$2"
}

# eza is a drop-in `ls` with git state. --group-directories-first and --icons
# are Omarchy's defaults; --icons=auto keeps a plain terminal readable.
if command -v eza >/dev/null 2>&1; then
    _haseen_alias ls 'eza -lh --group-directories-first --icons=auto'
    _haseen_alias lsa 'ls -a'
    _haseen_alias lt 'eza --tree --level=2 --long --icons --git'
    _haseen_alias lta 'lt -a'
fi
unset -f _haseen_alias
