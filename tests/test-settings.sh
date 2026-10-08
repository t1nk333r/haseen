# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# The settings index: every setting is listed once with its real value, its
# store and the command that owns it, and `settings set` routes to that command
# instead of writing state itself.
sandbox settings

# xdg-settings would read the machine's own default browser; keep the sandbox
# hermetic so the browser row is the sandbox's, not the developer's.
stub xdg-settings 'exit 1'

capture haseen settings list
assert_status "settings list succeeds on a fresh home" 0 "$STATUS"
assert_contains "the header names the owning command" "$OUTPUT" "CHANGE-WITH"

# --- every row is complete ---------------------------------------------------
# The rows are tab separated and bash collapses runs of whitespace delimiters,
# so an empty field would silently shift every later column.
rows="$(haseen settings list --json)"
assert_eq "no row has an empty field" "" \
    "$(jq -r '.[] | select(.key == "" or .value == "" or .store == "" or .path == "" or .setter == "") | .key' <<<"$rows")"
assert_eq "keys are unique" "" \
    "$(jq -r '[.[].key] | group_by(.) | map(select(length > 1) | .[0]) | .[]' <<<"$rows")"
assert_eq "every store is one of the six" "" \
    "$(jq -r '.[] | select(.store | IN("shell.json","config","flag","hypr-toggle","state","env") | not) | .key' <<<"$rows")"
assert_eq "every row says what settings set passes its owner" "" \
    "$(jq -r '.[] | select(.takes | IN("value","on-off","inverted","none") | not) | .key' <<<"$rows")"
assert_eq "every setter is a haseen command" "" \
    "$(jq -r '.[] | select(.setter | startswith("haseen ") | not) | .key' <<<"$rows")"

# --- values are read from the real stores ------------------------------------
assert_eq "a fresh home has no theme" "(none)" "$(jq -r '.[] | select(.key == "theme") | .value' <<<"$rows")"
assert_eq "the default bar position comes from the shipped shell.json" "top" \
    "$(jq -r '.[] | select(.key == "bar.position") | .value' <<<"$rows")"
assert_eq "do-not-disturb is off" "off" "$(jq -r '.[] | select(.key == "dnd") | .value' <<<"$rows")"
assert_eq "gaps are on" "on" "$(jq -r '.[] | select(.key == "gaps") | .value' <<<"$rows")"
# Plugin settings the user never wrote come from each plugin's manifest.
value_of() { jq -r --arg k "$1" '.[] | select(.key == $k) | .value' <<<"$rows"; }
assert_eq "plugin defaults: battery warning, critical action, idle on battery" "20 none {}" \
    "$(value_of haseen.battery.warnAt) $(value_of haseen.battery.criticalAction) $(value_of haseen.idle.onBattery)"
assert_eq "plugin defaults: clipboard preview on, screensaver ttfx, lock-key OSD off" "true ttfx false" \
    "$(value_of haseen.clipboard.preview) $(value_of haseen.screensaver.style) $(value_of haseen.osd.lockKeys)"
assert_eq "a setting without a default reads as unset" "(unset)" "$(value_of haseen.clock.showDayName)"

mkdir -p "$HOME/.local/state/haseen/flags" "$HOME/.local/state/haseen/toggles/hypr" "$HOME/.config/haseen"
touch "$HOME/.local/state/haseen/flags/dnd"
# The Hyprland toggles are stored inverted: the file turns the default off.
touch "$HOME/.local/state/haseen/toggles/hypr/no-gaps.lua"
echo '{"bar":{"position":"bottom"},"frame":{"radius":20,"enabled":false},"plugins":{"haseen.battery":{"settings":{"warnAt":25}},"haseen.clipboard":{"settings":{"preview":false}},"haseen.idle":{"settings":{"onBattery":{"suspendAfter":600}}}}}' >"$HOME/.config/haseen/shell.json"
rows="$(haseen settings list --json)"
assert_eq "a flag file reads as on" "on" "$(jq -r '.[] | select(.key == "dnd") | .value' <<<"$rows")"
assert_eq "the inverted hypr toggle reads as the user sees it" "off" \
    "$(jq -r '.[] | select(.key == "gaps") | .value' <<<"$rows")"
assert_eq "the user's shell.json wins over the default" "bottom" \
    "$(jq -r '.[] | select(.key == "bar.position") | .value' <<<"$rows")"
assert_eq "frame.radius shows the user's value" "20" \
    "$(jq -r '.[] | select(.key == "frame.radius") | .value' <<<"$rows")"
assert_eq "false in the user's file is a value, not a fall-through" "false false" \
    "$(value_of frame.enabled) $(value_of haseen.clipboard.preview)"
assert_eq "a plugin setting the user wrote wins over the manifest" "25" "$(value_of haseen.battery.warnAt)"
assert_eq "an object setting prints as compact JSON" '{"suspendAfter":600}' "$(value_of haseen.idle.onBattery)"

# --- set routes to the owning command ----------------------------------------
capture haseen settings set nightlight --dry-run
assert_status "setting a flag succeeds" 0 "$STATUS"
assert_dry_pure "settings set" "$OUTPUT"
assert_contains "the flag's own command does the write" "$OUTPUT" \
    "$HOME/.local/state/haseen/flags/nightlight"

capture haseen settings set haseen.screensaver.style native --dry-run
assert_status "a plugin setting with its own command routes there" 0 "$STATUS"
assert_dry_pure "settings set screensaver style" "$OUTPUT"
assert_contains "the value reaches haseen screensaver style" "$OUTPUT" "native"

capture haseen settings set theme tokyo-night --dry-run
assert_status "setting the theme succeeds" 0 "$STATUS"
assert_contains "the value reaches haseen theme set" "$OUTPUT" "tokyo-night"

capture haseen settings set bogus value
assert_status "an unknown key fails" 1 "$STATUS"
assert_contains "the error names the index" "$OUTPUT" "haseen settings list"

capture haseen settings set
assert_status "no key is a usage error" 2 "$STATUS"
capture haseen settings list --help
assert_status "--help exits 0" 0 "$STATUS"
assert_contains "--help explains the stores" "$OUTPUT" "hypr-toggle"

# --- the index covers what the commands actually mutate ----------------------
# A toggle that nothing lists is a setting the user cannot discover.
for t in dnd idle screensaver nightlight gaps animations one-window-ratio; do
    assert_eq "the index lists the $t toggle" "$t" \
        "$(jq -r --arg t "$t" '.[] | select(.key == $t) | .key' <<<"$rows")"
done

# --- set then list round-trips, in the user's terms -------------------------
# `settings set KEY on` must leave `settings list` reporting on, whatever the
# owning command calls on. The toggles run for real against the sandbox; the
# compositor and the shell are stubs that accept anything.
stub hyprctl 'exit 0'
stub notify-send 'exit 0'
stub qs 'exit 0'
stub quickshell 'exit 0'
stub pkill 'exit 0'
stub systemctl 'exit 0'
rm -rf "$HOME/.local/state/haseen/flags" "$HOME/.local/state/haseen/toggles"
for t in dnd idle screensaver nightlight gaps animations one-window-ratio; do
    for v in off on off; do
        capture haseen settings set "$t" "$v"
        assert_status "settings set $t $v succeeds" 0 "$STATUS"
        assert_eq "settings set $t $v, then list says $v" "$v" \
            "$(haseen settings list --json | jq -r --arg t "$t" '.[] | select(.key == $t) | .value')"
    done
done
capture haseen settings set gaps off --dry-run
assert_contains "gaps off writes the no-gaps toggle" "$OUTPUT" "DRYRUN: write $HOME/.local/state/haseen/toggles/hypr/no-gaps.lua"
capture haseen settings set gaps maybe --dry-run
assert_status "a value that is not on or off is refused for a toggle" 2 "$STATUS"
assert_contains "and the error says what it takes" "$OUTPUT" "gaps takes on or off"

# --- editor-owned keys take no value ----------------------------------------
for k in bar.height frame.radius haseen.clipboard.preview recording; do
    capture haseen settings set "$k" 12 --dry-run
    assert_status "settings set $k with a value is refused" 2 "$STATUS"
    assert_contains "settings set $k says it takes no value" "$OUTPUT" "$k takes no value"
    assert_not_contains "settings set $k does not fall into the owner's usage" "$OUTPUT" "Usage: haseen config edit"
done
capture haseen settings set frame.radius --dry-run
assert_status "an editor-owned key with no value still opens its file" 0 "$STATUS"

# --- a broken shell.json is reported, not passed off as the defaults --------
printf '{"frame":{"enabled":false},' >"$HOME/.config/haseen/shell.json"
capture haseen settings list
assert_status "a broken shell.json still lists" 0 "$STATUS"
assert_contains "the broken file is named" "$OUTPUT" "$HOME/.config/haseen/shell.json does not parse"

# --- control characters in a value cannot shift a row -----------------------
printf '{"frame":{"thickness":"7\\tx"}}\n' >"$HOME/.config/haseen/shell.json"
rows="$(haseen settings list --json)"
assert_eq "a tab in a value stays in the value" '"7\tx"' "$(value_of frame.thickness)"
assert_eq "and the row's setter is still its own" "haseen config edit $HOME/.config/haseen/shell.json" \
    "$(jq -r '.[] | select(.key == "frame.thickness") | .setter' <<<"$rows")"
capture haseen settings set frame.thickness --dry-run
assert_status "and settings set still routes it" 0 "$STATUS"
rm -f "$HOME/.config/haseen/shell.json"
