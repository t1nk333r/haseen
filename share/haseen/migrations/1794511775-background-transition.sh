# shellcheck shell=bash
# Plan 161: haseen.background's transition service is on by default (owner,
# 2026-11-12, "Wallpaper transition"), last in `services`. A user shell.json
# with its own `services` array hides the new default (arrays replace), so
# append the service there unless it is already listed. A shell.json without
# its own list already gets the default. `plugins."haseen.background"
# .settings.transition: "none"` turns the effect off.
# Safe to re-run: once it is listed there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
jq -e '.services | type == "array"' <<<"$user" >/dev/null || exit 0
jq -e '.services | index("haseen.background") != null' <<<"$user" >/dev/null && exit 0

jq '.services += ["haseen.background"]' <<<"$user" | shell_config_write
info "haseen.background: wallpaper transition on (plugins.\"haseen.background\".settings: transition, transitionDuration)"
