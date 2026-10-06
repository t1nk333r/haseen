# shellcheck shell=bash
# The keybind sheet reads the running compositor, and takes only its categories
# from the Lua sources. The shipped binds.lua puts the three menus on
# Omarchy's keys and binds no key twice.
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

# --- the shipped bindings ----------------------------------------------------
# init.lua runs under a stub hl that prints every bind as
# "MODS+KEY<TAB>description<TAB>command", modifiers sorted and upper-cased the
# way Hyprland matches them, so a reordered or re-cased combo still collides
# and keys built in loops (workspaces, directions) are counted too.
sandbox keybinds-shipped
stub_lua="$SANDBOX/hl-stub.lua"
cat >"$stub_lua" <<'EOF'
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...) return { dsp = name, args = { ... } } end,
  })
end
local function norm(keys)
  local parts = {}
  for p in keys:gmatch("[^+]+") do parts[#parts + 1] = p:match("^%s*(.-)%s*$"):upper() end
  local key = table.remove(parts)
  table.sort(parts)
  parts[#parts + 1] = key
  return table.concat(parts, "+")
end
hl = setmetatable({
  dsp = proxy("dsp"),
  bind = function(keys, d, opts)
    local what = d.dsp == "dsp.exec_cmd" and d.args[1] or d.dsp
    print(norm(keys) .. "\t" .. tostring(opts and opts.description) .. "\t" .. what)
  end,
}, { __index = function() return function() end end })
EOF
capture lua -e "dofile('$stub_lua')" "$REPO/share/haseen/default/hypr/init.lua"
assert_status "the shipped config loads" 0 "$STATUS"
shipped="$OUTPUT"
# bound KEYS — "description<TAB>command" of the normalised combo KEYS.
bound() { awk -F'\t' -v k="$1" '$1 == k { print $2 "\t" $3 }' <<<"$shipped"; }

assert_eq "SUPER + SPACE opens the menu" $'Menu\thaseen menu' "$(bound SUPER+SPACE)"
assert_eq "SUPER + SHIFT + SPACE opens the app launcher" $'Launcher\thaseen shell ipc launcher toggle' "$(bound SHIFT+SUPER+SPACE)"
assert_eq "SUPER + ESCAPE opens the system menu" $'System menu\thaseen menu system' "$(bound SUPER+ESCAPE)"
assert_eq "the bar toggle moved to SUPER + ALT + SPACE" $'Toggle bar\thaseen bar toggle' "$(bound ALT+SUPER+SPACE)"
assert_eq "closing a panel moved to SUPER + CTRL + ESCAPE" $'Close panel\thaseen shell ipc panel close' "$(bound CTRL+SUPER+ESCAPE)"
assert_eq "the system menu has one key" "SUPER+ESCAPE" "$(awk -F'\t' '$3 == "haseen menu system" { print $1 }' <<<"$shipped")"
assert_eq "the shipped config binds keys" true "$( (($(wc -l <<<"$shipped") > 60)) && echo true || echo false)"
assert_eq "no key is bound twice" "" "$(cut -f1 <<<"$shipped" | sort | uniq -d)"
assert_eq "every bind has a description" "" "$(awk -F'\t' '$2 == "nil" || $2 == ""' <<<"$shipped")"

# --- a user bind on a key haseen binds replaces it ---------------------------
# Hyprland stacks binds: a user's (or an Omarchy import's) SUPER + Q on top of
# haseen's would close two windows. haseen.rebind unbinds first.
cat >"$SANDBOX/hl-stack.lua" <<'LUA'
local binds = {}
local function norm(keys)
  local parts = {}
  for p in keys:gmatch("[^+]+") do parts[#parts + 1] = p:match("^%s*(.-)%s*$"):upper() end
  local key = table.remove(parts); table.sort(parts); parts[#parts + 1] = key
  return table.concat(parts, "+")
end
local function proxy(name)
  return setmetatable({}, { __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...) return { dsp = name } end })
end
hl = setmetatable({
  dsp = proxy("dsp"),
  bind = function(keys) local k = norm(keys); binds[k] = (binds[k] or 0) + 1 end,
  unbind = function(keys) binds[norm(keys)] = nil end,
}, { __index = function() return function() end end })
function REPORT() for k, n in pairs(binds) do if n > 1 then print(k) end end end
LUA
capture lua -e "dofile('$SANDBOX/hl-stack.lua')" -e "dofile('$REPO/share/haseen/default/hypr/init.lua')
haseen.rebind('SUPER + Q', 'Close window', hl.dsp.window.close())
haseen.rebind('SUPER + A', 'Exposé', hl.dsp.event('x'))
REPORT()"
assert_status "rebind runs on top of the shipped config" 0 "$STATUS"
assert_eq "a rebound key fires one action, not two" "" "$OUTPUT"
