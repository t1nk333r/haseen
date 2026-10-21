# shellcheck shell=bash
# Plan 093: haseen's answers to Omarchy's commands come first in the session.
# The desktop layer's uwsm fragment (~/.config/uwsm/env.d/10-haseen) now puts
# haseen's omarchy/bin at the front of PATH: an Omarchy-seeded
# ~/.config/uwsm/env, which uwsm sources first, prepends Omarchy's own bin,
# and Hyprland's exec_cmd then ran Omarchy's shell restart. The fragment is
# haseen's, rewritten on every desktop apply; this rewrites it once, from the
# layer's own generator, for a HOME the layer already wrote. It takes effect
# at the next login.
# Safe to re-run: a fragment with the line (not commented out) is left
# alone, and a HOME without the fragment (no desktop layer) has nothing to
# upgrade. A fragment without the layer's marker is the user's (replaced or
# rewritten by hand): it is left alone too, and haseen doctor reports any
# Omarchy command that comes first.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"
# shellcheck source=../layers/desktop/layer.sh
source "$HASEEN_PATH/layers/desktop/layer.sh"

fragment="$(desktop_config_home)/uwsm/env.d/10-haseen"
[[ -f $fragment ]] || exit 0
grep -q '^[[:space:]]*[^#[:space:]].*HASEEN_PATH/omarchy/bin' "$fragment" && exit 0
if ! grep -qF "$DESKTOP_MARKER" "$fragment"; then
    info "${fragment/#$HOME/\~} has no '$DESKTOP_MARKER' line, so it is yours: left alone. If Omarchy's commands come before haseen's in your session, haseen doctor says so."
    exit 0
fi
desktop_session_env | write_user_file_if_changed "$fragment"
info "haseen's answers to Omarchy's commands come first on PATH from your next login"
