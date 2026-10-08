# shellcheck shell=bash
# Plan 075: the haseen.battery service (low-battery warnings) is on by
# default, last in `services`. A user shell.json with its own `services`
# array hides the new default (arrays replace), so append the service there
# unless it is already listed. A shell.json without its own list already gets
# the default; `plugins."haseen.battery".enabled: false` still turns it off.
# Safe to re-run: once it is listed there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
jq -e '.services | type == "array"' <<<"$user" >/dev/null || exit 0
jq -e '.services | index("haseen.battery") != null' <<<"$user" >/dev/null && exit 0

jq '.services += ["haseen.battery"]' <<<"$user" | shell_config_write
info "haseen.battery: low-battery warnings on (plugins.\"haseen.battery\".settings: warnAt, criticalAt, criticalAction)"
