# shellcheck shell=bash
# Plan 098: three third-party plugins became first-party haseen plugins
# (owner, 2026-10-20), each under a haseen.* id:
#   io.github.juliusmork-sys.monitor-settings-extender -> haseen.monitor-settings
#   omaconnect (registry id omarchy.omaconnect)         -> haseen.omaconnect
#   io.github.ilyazar.syncthing                         -> haseen.syncthing
# A shell.json that uses an old id gets the new one in its place: in every bar
# section (left, center, right, overflow, pinned) and in `services`, once
# (where the new id is already listed the old one is just dropped), and its
# plugins.<old> entry moves to plugins.<new>, keeping `enabled` and only the
# settings the new manifest declares (an entry already under the new id
# wins). The Omarchy originals ran their service beside a listed bar widget;
# a native service runs only from `services`, so a listed OmaConnect or
# Syncthing widget gets its service added there.
# The old plugin directories are never touched (CLAUDE.md), and another
# plugin's own settings that name an old id (a t1nk33r.nook drawer item) are
# left as they are and only reported: the original still loads there.
# Safe to re-run: once no old id is listed there is nothing to do.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"
merged="$(shell_merged_json)"

# old id -> new id, and the new ids that bring a service.
map='{"io.github.juliusmork-sys.monitor-settings-extender":"haseen.monitor-settings",
      "omaconnect":"haseen.omaconnect","omarchy.omaconnect":"haseen.omaconnect",
      "io.github.ilyazar.syncthing":"haseen.syncthing"}'
services='["haseen.omaconnect","haseen.syncthing"]'
keys='{}'
for id in haseen.monitor-settings haseen.omaconnect haseen.syncthing; do
    keys="$(jq -c --arg id "$id" --slurpfile m "$HASEEN_PATH/shell/plugins/$id/manifest.json" \
        '. + {($id): ($m[0].settings // {} | keys - ["debugIpc"])}' <<<"$keys")"
done

# What the user file lists or configures under an old id.
uses="$(jq -c --argjson map "$map" '
    [(.bar // {} | (.left, .center, .right, .overflow, .pinned) | arrays | .[]), (.services | arrays | .[]),
     (.plugins // {} | keys[])] | map(select($map[.] != null)) | unique' <<<"$user")"
if [[ $uses == "[]" ]]; then
    nested="$(jq -r --argjson map "$map" '[.plugins // {} | to_entries[] | select(.value | [.. | strings] | any($map[.] != null)) | .key] | join(", ")' <<<"$user")"
    [[ -z $nested ]] || info "plan 098: $nested still names an old plugin id in its own settings; left as it is"
    exit 0
fi

jq --argjson map "$map" --argjson services "$services" --argjson keys "$keys" --argjson m "$merged" '
    def repoint: if type == "array"
        then reduce .[] as $id ([]; ($map[$id] // $id) as $n | if index([$n]) then . else . + [$n] end)
        else . end;
    # Ids a bar section listed, old or new, before the change.
    ([$m.bar // {} | (.left, .center, .right) | arrays | .[]] | map($map[.] // .)) as $barIds
    | .bar |= (if type == "object" then
        reduce ("left", "center", "right", "overflow", "pinned") as $s (.; if has($s) then .[$s] |= repoint else . end)
      else . end)
    | if has("services") then .services |= repoint else . end
    | ($services | map(select(. as $n | $barIds | index([$n])))) as $needed
    | if ($needed | length) > 0 then
        ((.services // $m.services // []) | repoint) as $have
        | .services = ($have + ($needed - $have))
      else . end
    | reduce ($map | to_entries[]) as $e (.;
        if (.plugins // {} | has($e.key)) then
          (.plugins[$e.key] | if type == "object" then . else {} end) as $old
          | ({} + (if ($old | has("enabled")) then {enabled: $old.enabled} else {} end)
               + (if ($old.settings | type) == "object"
                  then {settings: ($old.settings | with_entries(select(.key as $k | $keys[$e.value] | index([$k]))))}
                  else {} end)) as $moved
          | .plugins[$e.value] = ($moved * (.plugins[$e.value] // {}))
          | if (.plugins[$e.value].settings // null) == {} then del(.plugins[$e.value].settings) else . end
          | del(.plugins[$e.key])
        else . end)' <<<"$user" | shell_config_write

info "plan 098: $(jq -r --argjson map "$map" 'map(. + " is now " + $map[.]) | join("; ")' <<<"$uses")"
nested="$(shell_user_json | jq -r --argjson map "$map" '[.plugins // {} | to_entries[] | select(.value | [.. | strings] | any($map[.] != null)) | .key] | join(", ")')"
[[ -z $nested ]] || info "plan 098: $nested still names an old plugin id in its own settings; left as it is (the original still loads there)"
