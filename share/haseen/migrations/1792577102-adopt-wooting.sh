# shellcheck shell=bash
# Plan 099: the owner's t1nk33r.wooting plugin became the built-in
# haseen.wooting (owner, 2026-10-21). A shell.json that uses the old id is
# re-pointed at the new one:
#   - bar sections (left, center, right, overflow, pinned): the old id becomes
#     the new one in place, or goes when the new one is already there; other
#     entries, strings or not, stay as they are;
#   - services: haseen.wooting has no service (bar widget and panel only), so
#     an old entry there is dropped;
#   - plugins.<old>: moves to plugins.<new>, keeping `enabled` and only the
#     settings the new manifest declares; an entry the user already gave the
#     new id wins key by key.
# The plugin's directory, its udev rule and its user unit are never read,
# changed or removed here: `haseen setup wooting on` takes the rule and the
# unit over, and this says so when the plugin's unit is installed.
# Safe to re-run: once the old id is gone there is nothing to do. DRY_RUN=true
# (or --dry-run by hand) prints the write instead.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"
# shellcheck source=../lib/wooting.sh
source "$HASEEN_PATH/lib/wooting.sh"
parse_common_flags "$@"

OLD=t1nk33r.wooting
NEW=haseen.wooting

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"

used="$(jq -r --arg o "$OLD" '
    ([.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned, .services]
        | map(if type == "array" then . else [] end) | add | index($o) != null)
    or (.plugins // {} | has($o))' <<<"$user")"
[[ $used == true ]] || exit 0

settings="$(jq -c '(.settings // {}) | keys' "$HASEEN_PATH/shell/plugins/$NEW/manifest.json")"

# repoint KEEP: the old id replaced in place by the new one (dropped when KEEP
# is false), then duplicates removed, first occurrence kept. A non-string
# entry (an object a hand edit left) is never looked up as an id.
updated="$(jq --arg o "$OLD" --arg n "$NEW" --argjson keys "$settings" '
    def repoint($keep):
        if type != "array" then .
        else map(if type == "string" and . == $o then (if $keep then $n else empty end) else . end)
            | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
        end;
    (if .bar then reduce ("left", "center", "right", "overflow", "pinned") as $s (.;
        if .bar | has($s) then .bar[$s] |= repoint(true) else . end) else . end)
    | (if has("services") then .services |= repoint(false) else . end)
    | (if (.plugins // {}) | has($o) then
        ((.plugins[$o] // {}) | if type == "object" then . else {} end) as $old
        | ($old | with_entries(select(.key == "enabled"))
            + (if ($old.settings | type) == "object"
               then {settings: ($old.settings | with_entries(select(.key as $k | $keys | index($k))))}
               else {} end)) as $carried
        | .plugins[$n] = ($carried * ((.plugins[$n] // {}) | if type == "object" then . else {} end))
        | del(.plugins[$o])
      else . end)
' <<<"$user")"

if [[ $updated != "$user" ]]; then
    printf '%s\n' "$updated" | shell_config_write
fi
info "$OLD is now $NEW (built in; the old plugin directory is left as it was)"
if [[ $(wooting_owner "$(wooting_unit_path)" unit) == plugin ]]; then
    info "the plugin's own wootingd.service still runs its build of the daemon: haseen setup wooting on takes it over"
fi
