# shellcheck shell=bash
# Plan 096: four of the owner's forks became built-in plugins with haseen.*
# ids (owner, 2026-10-20): t1nk33r.typist -> haseen.typist, t1nk33r.settings
# -> haseen.settings, t1nk33r.browser-picker -> haseen.browser-picker,
# t1nk33r.vpn -> haseen.vpn. A shell.json that uses an old id is re-pointed
# at the new one:
#   - bar sections (left, center, right, overflow, pinned): the old id becomes
#     the new one in place, or goes when the new one is already there;
#   - services: the same for haseen.browser-picker and haseen.vpn, which have
#     a service; haseen.typist and haseen.settings have none (panel and bar
#     widget only), so their old entry is dropped there;
#   - plugins.<old>: moves to plugins.<new>, keeping `enabled` and only the
#     settings the new manifest declares; an entry the user already gave the
#     new id wins key by key.
# For a HOME that used an old id, the forks' own data is copied (never moved)
# where the new plugins read it, unless something is already there:
# ~/.config/omarchy/t1nk33r.typist.json -> ~/.config/haseen/typist.json;
# ~/.config/omarchy/browser-picker.json -> its rules to
# ~/.config/haseen/browser-picker.json and its settings into shell.json where
# none are set; ~/.local/state/omarchy/browser-picker.json (rankings) ->
# ~/.local/state/haseen/browser-picker.json.
# The old plugin directories are never read, changed or removed (CLAUDE.md),
# and the default browser is not changed: `haseen setup default browser
# browser-picker` makes the new picker the default.
# Safe to re-run: once no old id is left there is nothing to do. DRY_RUN=true
# (or --dry-run by hand) prints every write instead.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"
parse_common_flags "$@"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"

# old -> {id, service, settings}: the new id, whether it has a service kind,
# and the settings its manifest declares (debugIpc is a test hook, not carried).
map="$(
    for pair in typist:typist settings:settings browser-picker:browser-picker vpn:vpn; do
        new="haseen.${pair#*:}"
        jq -c --arg old "t1nk33r.${pair%%:*}" --arg new "$new" '{($old): {
            id: $new,
            service: ((.kinds | index("service")) != null),
            settings: ((.settings // {}) | keys - ["debugIpc"])}}' \
            "$HASEEN_PATH/shell/plugins/$new/manifest.json"
    done | jq -s 'add'
)"

used="$(jq -r --argjson map "$map" '
    [($map | keys[]) as $o | select(
        ([.bar.left, .bar.center, .bar.right, .bar.overflow, .bar.pinned, .services]
            | map(if type == "array" then . else [] end) | add | index($o) != null)
        or (.plugins // {} | has($o))) | $o] | join(" ")' <<<"$user")"
[[ -n $used ]] || exit 0

# repoint ARRAY KEEP: the old ids replaced in place by the new ones (dropped
# when KEEP says the new id does not belong in this array), then duplicates
# removed, first occurrence kept.
updated="$(jq --argjson map "$map" '
    def repoint($service_only):
        if type != "array" then .
        else map(if $map[.] then (if $service_only and ($map[.].service | not) then empty else $map[.].id end) else . end)
            | reduce .[] as $x ([]; if index([$x]) then . else . + [$x] end)
        end;
    (if .bar then reduce ("left", "center", "right", "overflow", "pinned") as $s (.;
        if .bar | has($s) then .bar[$s] |= repoint(false) else . end) else . end)
    | (if has("services") then .services |= repoint(true) else . end)
    | (if .plugins then
        reduce ($map | to_entries[]) as $e (.;
            if .plugins | has($e.key) then
                ((.plugins[$e.key] // {}) | if type == "object" then . else {} end) as $old
                | ($old | with_entries(select(.key == "enabled"))
                    + (if ($old.settings | type) == "object"
                       then {settings: ($old.settings | with_entries(select(.key as $k | $e.value.settings | index($k))))}
                       else {} end)) as $carried
                | .plugins[$e.value.id] = ($carried * (.plugins[$e.value.id] // {}))
                | del(.plugins[$e.key])
            else . end)
      else . end)
' <<<"$user")"

old_config="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy"
old_state="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy"

# typist: the snippets file as it was, if it is the fork's shape.
if [[ " $used " == *" t1nk33r.typist "* && -r $old_config/t1nk33r.typist.json && ! -e $HASEEN_USER_CONFIG/typist.json ]] &&
    jq -e 'type == "object" and ((.snippets // []) | type == "array")' "$old_config/t1nk33r.typist.json" >/dev/null 2>&1; then
    seed_user_file "$old_config/t1nk33r.typist.json" "$HASEEN_USER_CONFIG/typist.json"
    info "haseen.typist: snippets copied from $old_config/t1nk33r.typist.json"
fi

if [[ " $used " == *" t1nk33r.browser-picker "* ]]; then
    old="$old_config/browser-picker.json"
    if [[ -r $old && ! -e $HASEEN_USER_CONFIG/browser-picker.json ]] && jq -e 'type == "object"' "$old" >/dev/null 2>&1; then
        jq '{version: 1, rules: ((.rules // []) | if type == "array" then . else [] end)}' "$old" |
            write_user_file "$HASEEN_USER_CONFIG/browser-picker.json"
        # The fork kept its four settings in that file; haseen keeps them in
        # shell.json, where a value already set wins.
        updated="$(jq --slurpfile f "$old" '
            ($f[0].settings // {} | if type == "object" then . else {} end
                | with_entries(select(.key as $k | ["autoOpenRules", "learnRules", "promptAfter", "genericFirst"] | index($k)))) as $s
            | if ($s | length) > 0
              then .plugins["haseen.browser-picker"].settings = ($s * (.plugins["haseen.browser-picker"].settings // {}))
              else . end' <<<"$updated")"
        info "haseen.browser-picker: rules copied from $old"
    fi
    if [[ -r $old_state/browser-picker.json && ! -e $HASEEN_USER_STATE/browser-picker.json ]] &&
        jq -e 'type == "object"' "$old_state/browser-picker.json" >/dev/null 2>&1; then
        seed_user_file "$old_state/browser-picker.json" "$HASEEN_USER_STATE/browser-picker.json"
    fi
fi

if [[ $updated != "$user" ]]; then
    printf '%s\n' "$updated" | shell_config_write
fi
for o in $used; do
    info "$o is now $(jq -r --arg o "$o" '.[$o].id' <<<"$map") (built in; the old plugin directory is left as it was)"
done
