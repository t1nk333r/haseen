# shellcheck shell=bash
# The keybind sheet reads the running compositor, and takes only its categories
# from the Lua sources.
sandbox keybinds

tree="$SANDBOX/tree"
mkdir -p "$tree/default/hypr"
cp -r "$REPO/share/haseen/lib" "$tree/lib"
export HASEEN_PATH="$tree"

cat >"$tree/default/hypr/binds.lua" <<'LUA'
-- Shell ----------------------------------------------------------------
b("SUPER + SPACE", "Launcher", ipc("launcher", "toggle"))
b("SUPER + SLASH", "Keybindings", ipc("keybinds", "toggle"))

-- Capture --------------------------------------------------------------
b("PRINT", "Screenshot region", "haseen capture screenshot")
LUA

binds='[
 {"locked":false,"repeat":true,"has_description":true,"modmask":64,"submap":"","key":"SPACE","keycode":0,"description":"Launcher","dispatcher":"__lua","arg":"3"},
 {"locked":false,"repeat":false,"has_description":true,"modmask":0,"submap":"","key":"PRINT","keycode":0,"description":"Screenshot region","dispatcher":"__lua","arg":"4"},
 {"locked":true,"repeat":true,"has_description":true,"modmask":65,"submap":"","key":"F12","keycode":0,"description":"Added at runtime","dispatcher":"__lua","arg":"9"},
 {"locked":false,"repeat":false,"has_description":false,"modmask":68,"submap":"resize","key":"L","keycode":0,"description":"","dispatcher":"resizeactive","arg":"10 0"}
]'
printf '%s\n' "$binds" >"$SANDBOX/binds.json"
stub hyprctl 'case "$*" in
    "binds -j") cat "$HASEEN_BINDS_FIXTURE" ;;
    "reload") echo "ok" ;;
esac'
export HASEEN_BINDS_FIXTURE="$SANDBOX/binds.json"

capture haseen keybinds --json
assert_status "the live binds are read" 0 "$STATUS"
sheet="$OUTPUT"
assert_eq "every live bind is listed" 4 "$(jq length <<<"$sheet")"

launcher="$(jq -c '.[] | select(.description == "Launcher")' <<<"$sheet")"
assert_eq "the modifier mask becomes names" '["SUPER"]' "$(jq -c .mods <<<"$launcher")"
assert_eq "the combo reads like the config" "SUPER + SPACE" "$(jq -r .combo <<<"$launcher")"
assert_eq "the category is the section it was written under" "Shell" "$(jq -r .category <<<"$launcher")"

assert_eq "a second section is its own category" "Capture" "$(jq -r '.[] | select(.description == "Screenshot region") | .category' <<<"$sheet")"
assert_eq "several modifiers are decoded in order" '["SHIFT","SUPER"]' "$(jq -c '.[] | select(.description == "Added at runtime") | .mods' <<<"$sheet")"

# A bind that exists only in the compositor still shows; it just has no section.
assert_eq "a bind the config never declared is listed" "Other" "$(jq -r '.[] | select(.description == "Added at runtime") | .category' <<<"$sheet")"

submap="$(jq -c '.[] | select(.submap == "resize")' <<<"$sheet")"
assert_eq "a submap bind is grouped by its submap" "Submap: resize" "$(jq -r .category <<<"$submap")"
assert_eq "a bind without a description falls back to its dispatcher" "resizeactive 10 0" "$(jq -r .action <<<"$submap")"
assert_eq "a Lua bind has no readable action" "" "$(jq -r '.[] | select(.description == "Launcher") | .action' <<<"$sheet")"

capture haseen keybinds
assert_contains "the terminal sheet groups by category" "$OUTPUT" "Shell"
assert_contains "the terminal sheet shows combo and description" "$OUTPUT" "SUPER + SPACE"
assert_contains "a bind without a description shows its action" "$OUTPUT" "resizeactive 10 0"

# The user's own Lua file wins the category for a description it rebound.
mkdir -p "$XDG_CONFIG_HOME/hypr"
cat >"$XDG_CONFIG_HOME/hypr/bindings.lua" <<'LUA'
-- Mine ----------------------------------------------------------------
b("SUPER + SPACE", "Launcher", "something else")
LUA
capture haseen keybinds --json
assert_eq "a user section overrides the default one" "Mine" "$(jq -r '.[] | select(.description == "Launcher") | .category' <<<"$OUTPUT")"

stub hyprctl 'exit 1'
capture haseen keybinds
assert_status "a compositor that does not answer is an error" 1 "$STATUS"
assert_contains "the error names what failed" "$OUTPUT" "Hyprland is not answering"
