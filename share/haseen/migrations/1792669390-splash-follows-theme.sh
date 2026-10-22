# shellcheck shell=bash
# Plan 110: the boot splash follows the theme. Where haseen's splash is
# already installed and shown (`haseen plymouth set` ran, Theme=haseen),
# turn following on as `haseen plymouth set` now does: the root service, its
# polkit rule and the user's timer, which fires once 2 minutes later and
# rebuilds the boot image when it does not carry the current theme yet.
# Nothing without plymouth or haseen's splash; nothing when following is on
# already. A machine that checks its boot files, or a tree root does not own,
# is told why and left as it is: the migration has done what it can, and
# `haseen plymouth follow on` is there later. Safe to re-run.

# shellcheck source=../lib/plymouth.sh
source "$HASEEN_PATH/lib/plymouth.sh"

plymouth_theme_ours || exit 0
if plymouth_follow_on && [[ $(plymouth_follow_root_state) == installed ]]; then
    exit 0
fi

info "the boot splash follows the theme from now on (plan 110): turning it on"
rc=0
plymouth_follow_enable || rc=$?
case $rc in
0) info "the boot image is rebuilt about 2 minutes after a theme or mark change" ;;
3 | 4) info "left as it is; haseen plymouth set rebuilds the splash by hand" ;;
*) die "following was not turned on; the migration retries (haseen plymouth follow on)" ;;
esac
