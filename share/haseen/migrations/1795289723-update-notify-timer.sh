# shellcheck shell=bash
# Plan 182: haseen-update-notify.timer (one notification when haseen or
# package updates are waiting; owner, 2026-11-21) is on by default. The shell
# layer enables it on a new machine; this enables it where the shell layer
# was applied before the timer existed. Without haseen's shell there is no
# notification daemon of haseen's, so nothing is done.
# Safe to re-run: an enabled timer is left as it is. Without a user manager
# to talk to (su, an ssh session without XDG_RUNTIME_DIR) it says how to turn
# it on instead of failing, which would stop every update's migrations.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

units="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
[[ -L $units/graphical-session.target.wants/haseen-shell.service ]] || exit 0
[[ -L $units/timers.target.wants/haseen-update-notify.timer ]] && exit 0

if ! systemctl --user show-environment >/dev/null 2>&1; then
    warn "haseen-update-notify.timer was not enabled (no user manager here); to turn the update notice on: systemctl --user enable --now haseen-update-notify.timer"
    exit 0
fi
run systemctl --user enable --now haseen-update-notify.timer
run mkdir -p "$HASEEN_USER_STATE"
run touch "$HASEEN_USER_STATE/update-notify-enabled"
info "haseen-update-notify.timer: a notification tells you when haseen or package updates are waiting; 'haseen update' installs them (to stop it: systemctl --user disable --now haseen-update-notify.timer)"
