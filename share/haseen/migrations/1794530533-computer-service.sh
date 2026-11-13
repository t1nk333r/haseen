# shellcheck shell=bash
# Plan 165: haseen.computer's service (the Your computer panel's history,
# kept in the background) is on by default, last in `services`. A user
# shell.json with its own `services` array hides the new default (arrays
# replace), so append the service there unless it is already listed, as plan
# 163 did for haseen.stage. A shell.json without its own list already gets
# the default; without the service the panel still works, with a history
# that starts when it opens. `plugins."haseen.computer".enabled: false` turns
# both off. Safe to re-run: once it is listed there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
jq -e '.services | type == "array"' <<<"$user" >/dev/null || exit 0
jq -e '.services | index("haseen.computer") != null' <<<"$user" >/dev/null && exit 0

jq '.services += ["haseen.computer"]' <<<"$user" | shell_config_write
info "haseen.computer: the Your computer panel now keeps its 90 s history while it is closed"
