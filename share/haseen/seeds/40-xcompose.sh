# shellcheck shell=bash
# XCompose. Sourced by bin/haseen-seed-user.
#
# haseen:seed $COMPOSE|includes haseen's compose sequences
#
# Adapted from Omarchy (MIT, Copyright (c) David Heinemeier Hansson):
# default/xcompose and install/user/xcompose.sh.
#
# Generated rather than copied: it carries the absolute path of the installed
# tree, which differs between the checkout, /usr/local and /usr.
seed_main() {
    [[ -e $COMPOSE ]] && return 0
    write_user_file "$COMPOSE" <<EOF
# Your compose sequences. haseen writes this file once and never again.
# The Compose key is CapsLock (hypr input option compose:caps).

# The sequences of your locale.
include "%L"

# haseen's emoji, Arabic punctuation and typography sequences.
include "$DEFAULTS/xcompose/compose"
EOF
}
