# shellcheck shell=bash
# Plan 163: the haseen.stage service (Stage Manager on the left edge) is on
# by default, last in `services`. A user shell.json with its own `services`
# array hides the new default (arrays replace), so append the service there
# unless it is already listed, as plan 075 did for haseen.battery. A
# shell.json without its own list already gets the default;
# `plugins."haseen.stage".enabled: false` still turns it off.
# Safe to re-run: once it is listed there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
jq -e '.services | type == "array"' <<<"$user" >/dev/null || exit 0
jq -e '.services | index("haseen.stage") != null' <<<"$user" >/dev/null && exit 0

jq '.services += ["haseen.stage"]' <<<"$user" | shell_config_write
info "haseen.stage: push the pointer against a screen's left edge for the other workspaces (plugins.\"haseen.stage\".settings: edge, dwell, maxWindows, tilt)"
