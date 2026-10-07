# shellcheck shell=bash
# Plan 070: haseen.logo (the mark that opens the menu) is on by default, first
# in bar.left. A user shell.json that sets its own bar sections hides the new
# default, so put the logo at the start of bar.left there, unless it is
# already somewhere in the bar (left, center, right or the overflow panel).
# A shell.json without its own sections already gets the default. Safe to
# re-run: once the logo is in the bar there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
merged="$(shell_merged_json)"
jq -e '[.bar.left, .bar.center, .bar.right, .bar.overflow] | map(if type == "array" then . else [] end) | add | index("haseen.logo") != null' <<<"$merged" >/dev/null && exit 0

jq --argjson m "$merged" '.bar.left = ["haseen.logo"] + ($m.bar.left | if type == "array" then . else [] end)' <<<"$user" |
    shell_config_write
info "haseen.logo: first in the bar's left section (click it for the menu)"
