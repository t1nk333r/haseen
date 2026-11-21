# shellcheck shell=bash
# Plan 182: haseen-update-notify.timer (one notification when haseen or
# package updates are waiting; owner, 2026-11-21) is on by default. The shell
# layer enables it on a new machine; this enables it where the shell layer
# was applied before the timer existed. Without haseen's shell there is no
# notification daemon of haseen's, so nothing is done.
# Safe to re-run: an enabled timer is left as it is.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
[[ -L $units/graphical-session.target.wants/haseen-shell.service ]] || exit 0
[[ -L $units/timers.target.wants/haseen-update-notify.timer ]] && exit 0

run systemctl --user enable --now haseen-update-notify.timer
info "haseen-update-notify.timer: a notification tells you when haseen or package updates are waiting; 'haseen update' installs them (to stop it: systemctl --user disable --now haseen-update-notify.timer)"
