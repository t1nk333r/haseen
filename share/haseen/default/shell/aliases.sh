# shellcheck shell=bash
# haseen's aliases. Sourced by default/shell/init.sh, which is sourced by one
# line in ~/.bashrc (and ~/.zshrc). haseen owns this file: it is replaced on
# upgrade, so put your own aliases in your rc, not here.
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# default/bash/aliases. Changes: every alias is behind a `command -v` guard, so
# a machine without the tool keeps the real `ls` instead of an alias that
# fails on every prompt; `cd` is not replaced by zoxide (init.sh explains why);
# the agent/rails/docker one-letter aliases are left to the user's own rc.

# eza is a drop-in `ls` with git state. --group-directories-first and --icons
# are Omarchy's defaults; --icons=auto keeps a plain terminal readable.
if command -v eza >/dev/null 2>&1; then
    alias ls='eza -lh --group-directories-first --icons=auto'
    alias lsa='ls -a'
    alias lt='eza --tree --level=2 --long --icons --git'
    alias lta='lt -a'
fi
