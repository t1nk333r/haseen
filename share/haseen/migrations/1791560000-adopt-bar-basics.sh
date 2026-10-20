# shellcheck shell=bash
# Plan 095: four of the owner's plugins became first-party haseen plugins
# (owner, 2026-10-20): t1nk33r.active-window -> haseen.active-window,
# t1nk33r.power -> haseen.power, t1nk33r.updates -> haseen.updates,
# t1nk33r.nook -> haseen.nook. A user shell.json that still names an old id
# is re-pointed at the new one:
#
# - bar sections, bar.overflow and bar.pinned: the old id becomes the new one
#   in place (dropped where the new one is already listed);
# - services: the old id is dropped; none of the four new plugins has a
#   service kind (the old nook's service only served Omarchy's host);
# - plugins.<old>: moves to plugins.<new>. `enabled` is kept, and set true
#   when the old id was in a bar section without one, since the new plugins
#   ship off. Settings are mapped: active-window keeps maxChars and maxWidth;
#   power keeps showPercentage (as a boolean); updates keeps interval,
#   alwaysShow and splitAur, tooltipLines becomes listLines (the panel's
#   list replaced the tooltip) and onClick is dropped (the widget always runs
#   `haseen update`). Values already under plugins.<new> win.
# - The nook: haseen.nook opens the bar's own overflow panel, so the widgets
#   in the old nook's `items` move there (bar.overflow, in the nook's order),
#   each into the section `widgetOrigins` recorded for it, else the nook's,
#   else the right one, after the nook; an item's own keys fill in
#   plugins.<id>.settings. Items already in a bar section stay where they are.
#   A nook that sat inside bar.overflow (a drawer in the drawer) is removed:
#   its widgets join that drawer. Its trigger, duration, items and
#   widgetOrigins are dropped. A nook that was not shown (in no section, or
#   disabled) moves no widgets.
#
# The old plugin directories are never touched (CLAUDE.md): nothing reads
# them once no id names them. Safe to re-run: with no old id left there is
# nothing to do. Written atomically under the shell.json lock.

# shellcheck source=../shell/lib/plugin.sh
source "$HASEEN_PATH/shell/lib/plugin.sh"

[[ -e $SHELL_USER_CONFIG ]] || exit 0
shell_config_lock
user="$(shell_user_json)"

# shellcheck disable=SC2016 # a jq program, not shell
adopt='
def ids: if type == "array" then . else [] end;
def obj: if type == "object" then . else {} end;
def sections: ["left", "center", "right"];
def idre: "^[a-z0-9-]+(\\.[a-z0-9-]+)+$";
def without($id): map(select(. != $id));
# Each id once, the first kept: the order of everything else is untouched.
def once: reduce .[] as $x ([]; if ($x | type) == "string" and index([$x]) != null then . else . + [$x] end);
def settingsfor($old):
  (.settings // {} | obj) as $s
  | if $old == "t1nk33r.active-window" then $s | with_entries(select(.key == "maxChars" or .key == "maxWidth"))
    elif $old == "t1nk33r.power" then
      if $s | has("showPercentage") then {showPercentage: ($s.showPercentage != false and ($s.showPercentage | tostring | ascii_downcase) != "false")} else {} end
    elif $old == "t1nk33r.updates" then
      ($s | with_entries(select(.key == "interval" or .key == "alwaysShow" or .key == "splitAur")))
      + (if $s | has("tooltipLines") then {listLines: $s.tooltipLines} else {} end)
    else {} end;

# --- the nook: its widgets move into the bar overflow panel ---
"t1nk33r.nook" as $nook
| (.bar // {} | obj) as $bar
| ([sections[] as $s | select(($bar[$s] | ids | index([$nook])) != null) | $s] | first // null) as $home
| (($bar.overflow | ids | index([$nook])) != null) as $nested
| (.plugins[$nook] // {} | obj) as $entry
| ($entry.settings // {} | obj) as $ns
| ($ns.widgetOrigins // {} | obj) as $origins
| ([sections[] as $s | $bar[$s] | ids | .[]]) as $listed
| ((($home != null) or $nested) and $entry.enabled != false) as $shown
| (if $shown then
     [($ns.items // [] | ids)[]
      | if type == "string" then {id: .} elif type == "object" then . else empty end
      | select((.id | type) == "string" and (.id | test(idre)) and .id != $nook)]
     | reduce .[] as $i ([]; if any(.[]; .id == $i.id) then . else . + [$i] end)
   else [] end) as $items
| ([$items[] | select(.id as $id | $listed | index([$id]) == null)
    | . + {target: (($origins[.id] // {} | obj).section as $o
                    | if ($o | type) == "string" and (sections | index([$o])) != null then $o else ($home // "right") end)}]) as $moved
| ([$moved[].id]) as $movedIds
| reduce sections[] as $s (.;
    ([$moved[] | select(.target == $s) | .id]) as $add
    | if ($add | length) == 0 then .
      elif $s == $home then .bar[$s] = [(.bar[$s] | ids)[] | if . == $nook then (., $add[]) else . end]
      else .bar[$s] = ((.bar[$s] | ids) + $add) end)
| if ($movedIds | length) > 0 then
    (.bar.overflow | ids) as $ov
    | ([$movedIds[] as $id | select($ov | index([$id]) == null) | $id]) as $add
    | .bar.overflow = (if $nested then [$ov[] | if . == $nook then $add[] else . end] else $ov + $add end)
  else . end
| reduce $items[] as $i (.;
    ($i | del(.id, .target)) as $own
    | if ($own | length) == 0 then .
      else .plugins[$i.id] = ((.plugins[$i.id] // {} | obj) | .settings = ($own + (.settings // {} | obj))) end)
| if $nested then
    reduce (sections + ["overflow", "pinned"])[] as $s (.; if .bar[$s] | type == "array" then .bar[$s] |= without($nook) else . end)
    | if .services | type == "array" then .services |= without($nook) else . end
    | del(.plugins[$nook])
  else . end

# --- every old id: re-point it at the new one ---
| reduce ($map | to_entries[]) as $p (.;
    $p.key as $old | $p.value as $new
    | ([sections[] as $s | .bar[$s] | ids | .[]] | index([$old]) != null) as $wasListed
    | if (.plugins | type) == "object" and (.plugins | has($old)) then
        (.plugins[$old] | obj) as $o
        | (.plugins[$new] // {} | obj) as $n
        | ($o | settingsfor($old)) as $mapped
        | ($n
           + (if $n | has("enabled") then {}
              elif $o | has("enabled") then {enabled: $o.enabled}
              elif $wasListed then {enabled: true} else {} end)
           + (if ($mapped | length) > 0 or ($n | has("settings")) then {settings: ($mapped + ($n.settings // {} | obj))} else {} end)) as $merged
        | del(.plugins[$old])
        | if ($merged | length) > 0 then .plugins[$new] = $merged else . end
      elif $wasListed and ((.plugins[$new] // {} | obj) | has("enabled") | not) then
        .plugins[$new] = ((.plugins[$new] // {} | obj) + {enabled: true})
      else . end
    | reduce (sections + ["overflow", "pinned"])[] as $s (.;
        if .bar[$s] | type == "array" then .bar[$s] |= (map(if . == $old then $new else . end) | once) else . end)
    | if .services | type == "array" then .services |= without($old) else . end)
# The nook never sits in the panel it opens (Overflow.fit leaves it out).
| if .bar.overflow | type == "array" then .bar.overflow |= without("haseen.nook") else . end
# An id once across the sections, where it comes first (left, center, right).
| reduce ($map | to_entries[].value) as $new (.;
    reduce sections[] as $s (.;
      if (.bar[$s] | ids | index([$new])) != null
      then reduce (sections | .[(index([$s]) + 1):][]) as $later (.;
        if .bar[$later] | type == "array" then .bar[$later] |= without($new) else . end)
      else . end))
'

map='{"t1nk33r.active-window":"haseen.active-window","t1nk33r.power":"haseen.power","t1nk33r.updates":"haseen.updates","t1nk33r.nook":"haseen.nook"}'

# Nothing names an old id: nothing to do (this is also the re-run).
jq -e --argjson map "$map" '
    ([(.bar // {} | if type == "object" then . else {} end) | (.left, .center, .right, .overflow, .pinned) | arrays | .[]]
     + ((.services // []) | if type == "array" then . else [] end)
     + ((.plugins // {}) | if type == "object" then keys else [] end))
    | any(.[]; type == "string" and (. as $id | $map | has($id)))' <<<"$user" >/dev/null || exit 0

updated="$(jq --argjson map "$map" "$adopt" <<<"$user")"
[[ $updated != "$(jq . <<<"$user")" ]] || exit 0

if jq -e '.plugins["t1nk33r.updates"].settings | objects | has("onClick")' <<<"$user" >/dev/null; then
    info "haseen.updates: the old onClick setting is dropped; a click runs haseen update"
fi
moved="$(jq -r --argjson before "$user" --argjson map "$map" '
    [(.bar.overflow // [])[] | select(. as $id | (($before.bar.overflow // []) | index([$id]) == null) and ([$map[]] | index([$id]) == null))]
    | join(", ")' <<<"$updated")"
[[ -z $moved ]] || info "haseen.nook: the nook's widgets are in the bar's overflow panel now: $moved"
printf '%s\n' "$updated" | shell_config_write
info "t1nk33r.{active-window,power,updates,nook} are haseen.{active-window,power,updates,nook} now (plan 095)"
