# shellcheck shell=bash
# Plan 097: the owner's t1nk33r.todoist and t1nk33r.omarr are built in now, as
# haseen.todoist and haseen.omarr. A shell.json that uses an old id gets the
# new one in its place:
#   - bar.left/center/right/overflow/pinned: the old id becomes the new one
#     where it stood (once, if the new one was already there);
#   - services: the old id becomes the new one; and since a native plugin's
#     service runs only from `services` (an Omarchy plugin's started from its
#     bar slot), a new id that took over a bar slot is added there too: to the
#     user's own list, else to the default list written out with it;
#   - plugins.<old>: moved to plugins.<new>, its `enabled` and `settings`
#     kept (the settings' `id`, which Omarchy's writer adds, dropped); an
#     entry the new id already has wins key by key.
# The old plugin directories and their state directories are not touched: the
# token and the API keys stay where they are, and the new plugins read them
# there (UPSTREAM.md in each). Safe to re-run: once no old id is left there is
# nothing to do. Through shell_config_write: atomic, and --dry-run aware.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
merged="$(shell_merged_json)"
renames='{"t1nk33r.todoist":"haseen.todoist","t1nk33r.omarr":"haseen.omarr"}'

uses_old='
    def ids: [(.bar // {} | objects | (.left, .center, .right, .overflow, .pinned) | arrays | .[]),
              (.services | arrays | .[]),
              (.plugins | objects | keys[])];
    [ids[] | select(type == "string" and ($r[.] != null))] | length > 0'
jq -e --argjson r "$renames" "$uses_old" <<<"$user" >/dev/null || exit 0

updated="$(jq --argjson r "$renames" --argjson m "$merged" '
    # The old ids replaced in place, and each id once (its first place).
    def rename: map(if type == "string" and $r[.] != null then $r[.] else . end)
        | reduce .[] as $x ([]; if ($x | type) == "string" and index([$x]) != null then . else . + [$x] end);
    . as $u
    | ([($u.bar // {} | objects | (.left, .center, .right, .overflow) | arrays | .[]) | select(type == "string" and $r[.] != null) | $r[.]] | unique) as $slotted
    | reduce ("left", "center", "right", "overflow", "pinned") as $s (.;
        if (.bar | type) == "object" and (.bar[$s] | type) == "array" then .bar[$s] |= rename else . end)
    | (if (.services | type) == "array" then .services |= rename else . end)
    | (if ($slotted | length) > 0 then
           .services = ((if (.services | type) == "array" then .services else ($m.services // []) end) as $list
               | $list + [$slotted[] | select(. as $id | $list | index($id) == null)])
       else . end)
    | (if (.plugins | type) == "object" then
           reduce ($r | to_entries[]) as $e (.;
               if .plugins | has($e.key) then
                   (.plugins[$e.key] | if type == "object" then . else {} end
                       | if (.settings | type) == "object" then .settings |= del(.id) else . end) as $old
                   | .plugins[$e.value] = ($old * (.plugins[$e.value] // {} | if type == "object" then . else {} end))
                   | del(.plugins[$e.key])
               else . end)
       else . end)
' <<<"$user")"

[[ $updated == "$(jq . <<<"$user")" ]] && exit 0
printf '%s\n' "$updated" | shell_config_write
info "haseen.todoist and haseen.omarr: t1nk33r.todoist and t1nk33r.omarr are built in now; shell.json uses the new ids (the old plugin directories are untouched)"
