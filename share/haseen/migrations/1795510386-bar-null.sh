# shellcheck shell=bash
# Plan 186: migration 1791560300-adopt-integrations (plan 098) wrote
# `"bar": null` into a shell.json that named an old plugin id but kept the
# default bar (no `bar` of its own). Both merges let that null win over the
# default bar (shell_merged_json's `. * $u`, Config.qml's deepMerge), so the
# bar showed no widgets at all, and that migration is recorded as applied.
# This removes a `bar` that is exactly null; nothing else in the file
# changes, and a bar the user set themselves (an object, even an empty one)
# stays. No haseen command writes a null bar, and the shell has never read
# one as anything but an empty bar.
# Safe to re-run: once there is no null bar there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
jq -e 'has("bar") and .bar == null' <<<"$user" >/dev/null || exit 0
jq 'del(.bar)' <<<"$user" | shell_config_write
info "plan 186: $SHELL_USER_CONFIG had \"bar\": null, which hid every bar widget; removed, so the default bar shows again"
