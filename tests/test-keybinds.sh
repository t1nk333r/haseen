# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
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
assert_eq "modifiers read the way binds.lua writes them" '["SUPER","SHIFT"]' "$(jq -c '.[] | select(.description == "Added at runtime") | .mods' <<<"$sheet")"

# A bind that exists only in the compositor still shows; it just has no section.
assert_eq "a bind the config never declared is listed" "Other" "$(jq -r '.[] | select(.description == "Added at runtime") | .category' <<<"$sheet")"

submap="$(jq -c '.[] | select(.submap == "resize")' <<<"$sheet")"
assert_eq "a submap bind is grouped by its submap" "Submap: resize" "$(jq -r .category <<<"$submap")"
assert_eq "a bind without a description falls back to its dispatcher" "resizeactive 10 0" "$(jq -r .action <<<"$submap")"
assert_eq "a Lua bind no config declares has no readable action" "" "$(jq -r '.[] | select(.description == "Launcher") | .action' <<<"$sheet")"

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

# --- the shipped layout -------------------------------------------------------
# share/haseen/default/hypr/binds.lua is the owner's layout (waydots
# ~/.config/hypr/bindings.lua). Loading it under a stub `hl` makes every bind,
# its description and its action readable without a compositor.
sandbox keybinds-layout
export HASEEN_PATH="$REPO/share/haseen"

if command -v lua >/dev/null; then
    stub_lua="$SANDBOX/hl-stub.lua"
    cat >"$stub_lua" <<'LUA'
-- Records what the config does instead of configuring a compositor.
BINDS = {}
DISPATCHED = {}
local function proxy(name)
  return setmetatable({}, {
    __index = function(_, k) return proxy(name .. "." .. k) end,
    __call = function(_, ...) return { dsp = name, args = { ... } } end,
  })
end
local function show(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys = {}
  for k in pairs(value) do keys[#keys + 1] = k end
  table.sort(keys)
  local out = {}
  for _, k in ipairs(keys) do out[#out + 1] = k .. "=" .. tostring(value[k]) end
  return "{" .. table.concat(out, ",") .. "}"
end
-- render DISPATCHER -> "<kind>\t<what>": cmd (a shell command), dsp (a
-- Hyprland dispatcher) or lua (a Lua action the bind runs itself).
local function render(d)
  if type(d) == "function" then return "lua\tfunction" end
  if d.dsp == "dsp.exec_cmd" then return "cmd\t" .. tostring(d.args[1]) end
  local out = {}
  for _, a in ipairs(d.args or {}) do out[#out + 1] = show(a) end
  return "dsp\t" .. d.dsp .. "(" .. table.concat(out, " ") .. ")"
end
local function flat(prefix, t)
  for k, v in pairs(t) do
    local key = prefix == "" and k or (prefix .. "." .. k)
    if type(v) == "table" and not v.colors then flat(key, v) else print("CONFIG\t" .. key .. "=" .. tostring(v)) end
  end
end
hl = setmetatable({
  dsp = proxy("dsp"),
  config = function(t) flat("", t) end,
  bind = function(keys, d, opts)
    local desc = (opts or {}).description or ""
    BINDS[#BINDS + 1] = { keys = keys, desc = desc, d = d }
    print("BIND\t" .. keys .. "\t" .. desc .. "\t" .. render(d))
  end,
  unbind = function(keys) print("UNBIND\t" .. keys) end,
  on = function() end,
  dispatch = function(d) DISPATCHED[#DISPATCHED + 1] = render(d) end,
}, { __index = function() return function() end end })
LUA

    probe="$SANDBOX/probe.lua"
    cat >"$probe" <<'LUA'
dofile(os.getenv("STUB_LUA"))
dofile(os.getenv("HASEEN_INIT"))
print("COUNT\t" .. #BINDS)

-- Press a bind with a fake active window on a 1920x1080 monitor at scale 1.25
-- (so 1536x864 of layout pixels) whose top 24 are reserved by a bar.
local monitor = { x = 0, y = 0, width = 1920, height = 1080, scale = 1.25,
  reserved = { left = 0.0, top = 24.0, right = 0.0, bottom = 0.0 } }
local window = { address = "0xDEAD", floating = false, monitor = monitor,
  at = { x = 12, y = 36 }, size = { x = 1512, y = 816 } }
hl.get_active_window = function() return window end
hl.get_active_monitor = function() return monitor end
local function press(label, keys)
  DISPATCHED = {}
  for _, r in ipairs(BINDS) do
    if r.keys == keys then
      r.d()
      for _, d in ipairs(DISPATCHED) do print("PRESS\t" .. label .. "\t" .. d) end
      return
    end
  end
  print("PRESS\t" .. label .. "\tno bind on " .. keys)
end
local HYPER = "SUPER + SHIFT + ALT + CTRL + "
press("snap-left", HYPER .. "H")
press("snap-left-again", HYPER .. "H")
press("snap-right", HYPER .. "L")
press("snap-big", HYPER .. "G")
press("alt-tab", "ALT + TAB")
LUA

    # hyprmod's file and a persisted toggle both set the same key, so the load
    # order is visible in the output.
    mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_STATE_HOME/haseen/toggles/hypr"
    printf '%s\n' 'hl.config({ general = { gaps_in = 0 } })' >"$XDG_STATE_HOME/haseen/toggles/hypr/gaps.lua"
    printf '%s\n' 'hl.config({ general = { gaps_in = 7 } })' >"$XDG_CONFIG_HOME/hypr/hyprland-gui.lua"

    capture env STUB_LUA="$stub_lua" HASEEN_INIT="$HASEEN_PATH/default/hypr/init.lua" lua "$probe"
    assert_status "the Hyprland defaults load" 0 "$STATUS"
    layout="$OUTPUT"

    bind_field() { awk -F'\t' -v k="$2" -v f="$3" '$1 == "BIND" && $2 == k { print $f }' <<<"$1"; }
    desc_of() { bind_field "$layout" "$1" 3; }
    action_of() { bind_field "$layout" "$1" 5; }

    assert_eq "every bind carries a description for the sheet" "" \
        "$(awk -F'\t' '$1 == "BIND" && $3 == "" { print $2 }' <<<"$layout")"
    assert_eq "no key is bound twice" "" \
        "$(awk -F'\t' '$1 == "BIND" { print $2 }' <<<"$layout" | sort | uniq -d)"
    assert_eq "every bind is a command, a dispatcher or a Lua action" "" \
        "$(awk -F'\t' '$1 == "BIND" && $4 != "cmd" && $4 != "dsp" && $4 != "lua" { print $2 " " $4 }' <<<"$layout")"

    # Every command a bind runs has to exist. `haseen a b c` resolves the way
    # bin/haseen does, longest prefix first; the rest are the few external
    # tools the desktop layer installs, and `test`, the shell builtin a guarded
    # bind (`test -e … && haseen …`) starts with. Each side of `&&` is checked.
    external=" test uwsm uwsm-app wpctl brightnessctl playerctl "
    missing=""
    while IFS= read -r command; do
        [[ -n $command ]] || continue
        read -r -a words <<<"$command"
        if [[ ${words[0]} != haseen ]]; then
            [[ $external == *" ${words[0]} "* ]] || missing+="$command"$'\n'
            continue
        fi
        route=()
        for word in "${words[@]:1}"; do
            [[ $word =~ ^[a-z0-9][a-z0-9-]*$ ]] || break
            route+=("$word")
        done
        found=false
        for ((n = ${#route[@]}; n >= 0; n--)); do
            if ((n == 0)); then name=haseen; else name="haseen$(printf -- '-%s' "${route[@]:0:n}")"; fi
            [[ -x $REPO/bin/$name ]] && {
                found=true
                break
            }
        done
        $found || missing+="$command"$'\n'
    done < <(awk -F'\t' '$1 == "BIND" && $4 == "cmd" { n = split($5, part, / *&& */); for (i = 1; i <= n; i++) print part[i] }' <<<"$layout" | sort -u)
    assert_eq "every bound command exists in bin/ or is a required tool" "" "${missing%$'\n'}"

    # The owner's layout (waydots ~/.config/hypr/bindings.lua).
    assert_eq "SUPER + Q closes the window" "dsp.window.close()" "$(action_of 'SUPER + Q')"
    assert_eq "Omarchy's SUPER + W still closes too" "dsp.window.close()" "$(action_of 'SUPER + W')"
    assert_eq "the split toggle moved to ALT + J" "dsp.layout(togglesplit)" "$(action_of 'ALT + J')"
    assert_eq "the workspace layout toggle is on ALT + L" "haseen toggle workspace-layout" "$(action_of 'ALT + L')"
    assert_eq "the clipboard moved to ALT + V" "haseen shell ipc panel toggle 'haseen.clipboard'" "$(action_of 'ALT + V')"
    assert_eq "the keybind sheet is on SUPER + F1" "haseen shell ipc keybinds toggle" "$(action_of 'SUPER + F1')"
    assert_eq "SUPER + SLASH is free again" "" "$(action_of 'SUPER + SLASH')"
    assert_eq "SUPER + CTRL + V is free again" "" "$(action_of 'SUPER + CTRL + V')"
    assert_eq "OCR is on SUPER + CTRL + PRINT" "haseen search screen text" "$(action_of 'SUPER + CTRL + PRINT')"
    assert_eq "circle-to-search is on SUPER + SHIFT + PRINT" "haseen search screen image" \
        "$(action_of 'SUPER + SHIFT + PRINT')"

    for pair in "H l left" "J d down" "K u up" "L r right"; do
        read -r key dir name <<<"$pair"
        assert_eq "SUPER + $key moves focus $name" "dsp.focus({direction=$dir})" "$(action_of "SUPER + $key")"
        assert_eq "SUPER + SHIFT + $key moves the window $name" "dsp.window.move({direction=$dir})" \
            "$(action_of "SUPER + SHIFT + $key")"
    done
    assert_eq "the arrows still focus" "dsp.focus({direction=l})" "$(action_of 'SUPER + LEFT')"
    assert_eq "the arrows still swap" "dsp.window.swap({direction=l})" "$(action_of 'SUPER + SHIFT + LEFT')"

    assert_eq "SUPER + SHIFT + <n> moves silently" "Move window silently to workspace 1" \
        "$(desc_of 'SUPER + SHIFT + code:10')"
    assert_eq "it uses the keycode, so the Arabic number row works" "dsp.window.move({follow=false,workspace=1})" \
        "$(action_of 'SUPER + SHIFT + code:10')"
    assert_eq "adding ALT follows the window over" "dsp.window.move({workspace=10})" \
        "$(action_of 'SUPER + SHIFT + ALT + code:19')"

    # ALT + TAB cycles and raises, in one bind rather than two on the same key.
    assert_eq "ALT + TAB runs a Lua action" "function" "$(action_of 'ALT + TAB')"
    assert_eq "ALT + TAB cycles then raises" \
        "dsp.window.cycle_next()|dsp.window.bring_to_top()" \
        "$(awk -F'\t' '$1 == "PRESS" && $2 == "alt-tab" { printf "%s%s", sep, $4; sep = "|" }' <<<"$layout")"

    # The HYPER (CapsLock via keyd) snap layer: pure dispatchers, no helper.
    assert_eq "the snap layer has its eleven keys" 11 \
        "$(awk -F'\t' '$1 == "BIND" && $2 ~ /^SUPER \+ SHIFT \+ ALT \+ CTRL \+ / { n++ } END { print n + 0 }' <<<"$layout")"
    assert_eq "HYPER + H is snap left" "Snap left" "$(desc_of 'SUPER + SHIFT + ALT + CTRL + H')"
    snap_presses() { awk -F'\t' -v l="$1" '$1 == "PRESS" && $2 == l { printf "%s%s", sep, $4; sep = "|" }' <<<"$layout"; }
    # 1920x1080 at scale 1.25 is 1536x864; the bar reserves the top 24.
    assert_eq "snap left floats, halves and parks at the usable edge" \
        "dsp.window.float({action=on})|dsp.window.resize({exact=true,x=768,y=840})|dsp.window.move({exact=true,x=0,y=24})" \
        "$(snap_presses snap-left)"
    assert_eq "the same snap again puts a tiled window back" \
        "dsp.window.float({action=off})" "$(snap_presses snap-left-again)"
    assert_eq "snap right starts at the middle of the usable area" \
        "dsp.window.float({action=on})|dsp.window.resize({exact=true,x=768,y=840})|dsp.window.move({exact=true,x=768,y=24})" \
        "$(snap_presses snap-right)"
    assert_eq "snap 80% is centred in the usable area" \
        "dsp.window.float({action=on})|dsp.window.resize({exact=true,x=1228,y=672})|dsp.window.move({exact=true,x=154,y=108})" \
        "$(snap_presses snap-big)"

    # hyprmod loads last of haseen's includes, so its GUI wins over the
    # toggles `haseen toggle …` and `haseen hw …` persisted.
    # `|| true`: a missing line has to fail the assertion below, not abort.
    toggle_line="$(grep -n 'general.gaps_in=0$' <<<"$layout" | cut -d: -f1 || true)"
    hyprmod_line="$(grep -n 'general.gaps_in=7$' <<<"$layout" | cut -d: -f1 || true)"
    assert_eq "hyprland-gui.lua loads after the haseen toggles" "true" \
        "$([[ -n $toggle_line && -n $hyprmod_line && $hyprmod_line -gt $toggle_line ]] && echo true || echo false)"

    # A session without hyprmod installed has no such file and must not care.
    rm -f "$XDG_CONFIG_HOME/hypr/hyprland-gui.lua"
    capture env STUB_LUA="$stub_lua" HASEEN_INIT="$HASEEN_PATH/default/hypr/init.lua" lua "$probe"
    assert_status "no hyprmod installed: the config still loads" 0 "$STATUS"
    assert_not_contains "no hyprmod installed: the toggle stands" "$OUTPUT" "general.gaps_in=7"
    assert_eq "the bind count does not depend on hyprmod" \
        "$(grep -c '^BIND' <<<"$layout" || true)" "$(grep -c '^BIND' <<<"$OUTPUT" || true)"
else
    echo "  SKIP lua is not installed: binds.lua was not loaded" >&2
fi

# The sheet's categories come from the `-- Section ---` comments in the real
# binds.lua, so a description there reaches `haseen keybinds` grouped.
live='[
 {"locked":false,"repeat":false,"has_description":true,"modmask":64,"submap":"","key":"Q","keycode":0,"description":"Close window","dispatcher":"__lua","arg":"1"},
 {"locked":false,"repeat":false,"has_description":true,"modmask":77,"submap":"","key":"H","keycode":0,"description":"Snap left","dispatcher":"__lua","arg":"2"},
 {"locked":false,"repeat":false,"has_description":true,"modmask":64,"submap":"","key":"F1","keycode":0,"description":"Keybindings","dispatcher":"__lua","arg":"3"}
]'
printf '%s\n' "$live" >"$SANDBOX/live.json"
export HASEEN_BINDS_FIXTURE="$SANDBOX/live.json"
stub hyprctl 'case "$*" in
    "binds -j") cat "$HASEEN_BINDS_FIXTURE" ;;
esac'
capture haseen keybinds --json
assert_status "the sheet reads the shipped sections" 0 "$STATUS"
assert_eq "a window bind is grouped under Windows" "Windows" \
    "$(jq -r '.[] | select(.description == "Close window") | .category' <<<"$OUTPUT")"
assert_eq "a snap bind is grouped under Snap layer" "Snap layer" \
    "$(jq -r '.[] | select(.description == "Snap left") | .category' <<<"$OUTPUT")"
assert_eq "the keybind sheet's own bind is grouped under Shell" "Shell" \
    "$(jq -r '.[] | select(.description == "Keybindings") | .category' <<<"$OUTPUT")"

# --- readable keys and replayable Lua binds (plan 071) -------------------------
# Hyprland 0.56 reports every Lua bind as `__lua` with a function id, a
# code:N bind with an empty key, and mouse buttons by number. The keys come
# back from the keymap (xkbcli) and the Lua config, run under a stub hl.
sandbox keybinds-resolve
tree="$SANDBOX/tree"
mkdir -p "$tree/default/hypr" "$XDG_CONFIG_HOME/hypr"
cp -r "$REPO/share/haseen/lib" "$tree/lib"
export HASEEN_PATH="$tree"
cat >"$XDG_CONFIG_HOME/hypr/hyprland.lua" <<'LUA'
local function b(keys, description, dispatcher, options)
  local opts = options or {}
  opts.description = description
  if type(dispatcher) == "string" then dispatcher = hl.dsp.exec_cmd(dispatcher) end
  return hl.bind(keys, dispatcher, opts)
end
b("SUPER + SLASH", "Keybindings", "haseen shell ipc keybinds toggle")
-- Workspaces -------------------------------------------------------------
for ws = 1, 1 do
  b("SUPER + code:" .. tostring(ws + 9), "Workspace " .. ws, hl.dsp.focus({ workspace = tostring(ws) }))
end
-- Other things -----------------------------------------------------------
b("SUPER + SHIFT + code:20", "Zoom out", "uwsm-app -- zoom out")
b("SUPER + code:38", "Keymap key", "a-key")
b("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
b("SUPER + comma", "Notifications", "haseen notification history")
b("SUPER + U", "Copy", function() end)
b("CTRL + Q", "Quit", "quit-all")
hl.unbind("CTRL + Q")
LUA
cat >"$SANDBOX/binds.json" <<'JSON'
[
 {"has_description":true,"modmask":64,"submap":"","key":"SLASH","keycode":0,"description":"Keybindings","dispatcher":"__lua","arg":"1","repeat":false,"locked":false},
 {"has_description":true,"modmask":64,"submap":"","key":"","keycode":0,"description":"Workspace 1","dispatcher":"__lua","arg":"2","repeat":false,"locked":false},
 {"has_description":true,"modmask":65,"submap":"","key":"SUPER + SHIFT + code:20","keycode":0,"description":"Zoom out","dispatcher":"__lua","arg":"3","repeat":false,"locked":false},
 {"has_description":true,"modmask":64,"submap":"","key":"","keycode":38,"description":"Keymap key","dispatcher":"__lua","arg":"4","repeat":false,"locked":false},
 {"has_description":true,"modmask":64,"submap":"","key":"mouse:272","keycode":0,"description":"Move window","dispatcher":"__lua","arg":"5","repeat":false,"locked":false},
 {"has_description":true,"modmask":64,"submap":"","key":"comma","keycode":0,"description":"Notifications","dispatcher":"__lua","arg":"6","repeat":false,"locked":false},
 {"has_description":true,"modmask":64,"submap":"","key":"U","keycode":0,"description":"Copy","dispatcher":"__lua","arg":"7","repeat":false,"locked":false},
 {"has_description":false,"modmask":64,"submap":"","key":"2","keycode":0,"description":"","dispatcher":"workspace","arg":"2","repeat":false,"locked":false},
 {"has_description":false,"modmask":0,"submap":"","key":"F9","keycode":0,"description":"","dispatcher":"__lua","arg":"8","repeat":false,"locked":false}
]
JSON
stub hyprctl 'case "$1" in
    binds) cat "'"$SANDBOX"'/binds.json" ;;
    dispatch) echo "$*" >>"'"$SANDBOX"'/dispatch.log"; echo ok ;;
esac'
# A keymap where code 38 is "a" (as on a US layout); code 20 is left to the
# number-row fallback.
stub xkbcli 'cat <<EOF
xkb_keymap {
xkb_keycodes "evdev" {
    minimum = 8;
    <AE01> = 10;
    <AC01> = 38;
};
xkb_symbols "pc+us" {
    key <AE01> { [ 1, exclam ] };
    key <AC01> { [ a, A ] };
};
};
EOF'
capture haseen keybinds --json
assert_status "binds resolve" 0 "$STATUS"
sheet="$OUTPUT"
bind() { jq -r --arg d "$1" '.[] | select(.description == $d) | "\(.combo)|\(.dispatcher)|\(.arg)"' <<<"$sheet"; }
assert_eq "a code:N key Hyprland leaves empty comes from the Lua config" 'SUPER + 1|lua|hl.dsp.focus({ workspace = "1" })' "$(bind "Workspace 1")"
assert_eq "a reported 'MODS + code:N' key loses its modifiers and is named" 'SUPER + SHIFT + MINUS|exec|uwsm-app -- zoom out' "$(bind "Zoom out")"
assert_eq "a keycode is named from the keymap" 'SUPER + A|exec|a-key' "$(bind "Keymap key")"
assert_eq "mouse buttons are named" 'SUPER + LEFT MOUSE BUTTON|lua|hl.dsp.window.drag()' "$(bind "Move window")"
assert_eq "lower-case key names read in capitals" 'SUPER + COMMA|exec|haseen notification history' "$(bind "Notifications")"
assert_eq "a bind made in a loop gets the section above the loop" "Workspaces" \
    "$(jq -r '.[] | select(.description == "Workspace 1") | .category' <<<"$sheet")"
assert_eq "a bind gets the section it was written under" "Other things" \
    "$(jq -r '.[] | select(.description == "Copy") | .category' <<<"$sheet")"
assert_eq "a Lua function bind is listed without a dispatcher" 'SUPER + U||' "$(bind "Copy")"
assert_eq "a native bind keeps its dispatcher" 'SUPER + 2|workspace|2' "$(jq -r '.[] | select(.dispatcher == "workspace") | "\(.combo)|\(.dispatcher)|\(.arg)"' <<<"$sheet")"
assert_eq "an undescribed Lua bind is left out" "" "$(jq -r '.[] | select(.key == "F9") | .combo' <<<"$sheet")"
assert_eq "the action reads without the uwsm wrapper" "zoom out" "$(jq -r '.[] | select(.description == "Zoom out") | .action' <<<"$sheet")"
capture haseen keybinds
assert_contains "the sheet shows resolved keys" "$OUTPUT" "SUPER + LEFT MOUSE BUTTON"
assert_not_contains "the sheet shows no raw keycode" "$OUTPUT" "code:"
assert_eq "the sheet never ends a combo on a bare modifier" "" "$(grep -E '\+ {2,}' <<<"$OUTPUT" || true)"

# --- haseen keybinds list: Omarchy's searchable list -------------------------
capture haseen keybinds list --print
assert_status "--print lists" 0 "$STATUS"
assert_eq "--print: the Keybindings bind leads, then the rest" \
    "SUPER + SLASH                       → Keybindings" "$(head -1 <<<"$OUTPUT")"
assert_contains "--print: KEYS → description, padded to 35" "$OUTPUT" "SUPER + 1                           → Workspace 1"
assert_contains "--print: a bind without description shows its action" "$OUTPUT" "SUPER + 2                           → workspace 2"
assert_eq "--print: plain text, one row per bind" 8 "$(wc -l <<<"$OUTPUT")"
assert_not_contains "--print: no dispatch metadata" "$OUTPUT" "hl.dsp"

# The picker: what it is given, and what Enter on a row does. (Called as
# haseen-keybinds-list: `haseen` puts bin/ ahead of the stubbed picker.)
pick() { stub haseen-menu-select 'printf "%s\n" "$*" >"'"$SANDBOX"'/picker.args"; tee "'"$SANDBOX"'/picker.in" | '"$1"; }
pick 'grep -m1 "Workspace 1"'
rm -f "$SANDBOX/dispatch.log"
capture haseen-keybinds-list
assert_status "Enter on a Lua bind" 0 "$STATUS"
assert_eq "the list is Omarchy's size" "Keybindings --width 800 --height 500" "$(cat "$SANDBOX/picker.args")"
assert_eq "the list gets every row" 8 "$(wc -l <"$SANDBOX/picker.in")"
assert_eq "a Lua bind replays its dispatcher expression" 'dispatch hl.dsp.focus({ workspace = "1" })' "$(cat "$SANDBOX/dispatch.log")"

pick 'grep -m1 "Zoom out"'
rm -f "$SANDBOX/dispatch.log"
capture haseen-keybinds-list
assert_eq "an exec bind runs its command through hl.dsp.exec_cmd" 'dispatch hl.dsp.exec_cmd("uwsm-app -- zoom out")' "$(cat "$SANDBOX/dispatch.log")"

pick 'grep -m1 "workspace 2"'
rm -f "$SANDBOX/dispatch.log"
capture haseen-keybinds-list
assert_eq "a native bind runs its dispatcher" 'dispatch workspace 2' "$(cat "$SANDBOX/dispatch.log")"

pick 'grep -m1 "Copy"'
rm -f "$SANDBOX/dispatch.log"
capture haseen-keybinds-list
assert_status "a Lua function bind cannot be replayed" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "cannot be replayed"
assert_eq "nothing is dispatched for it" "" "$(cat "$SANDBOX/dispatch.log" 2>/dev/null)"

pick 'grep -m1 "Workspace 1"'
capture haseen-keybinds-list --dry-run
assert_eq "--dry-run prints the dispatch" 'DRYRUN: hyprctl dispatch hl.dsp.focus({ workspace = "1" })' "$OUTPUT"
assert_eq "--dry-run dispatches nothing" "" "$(cat "$SANDBOX/dispatch.log" 2>/dev/null)"

pick 'exit 1'
capture haseen-keybinds-list
assert_status "closing the list is not an error" 0 "$STATUS"
assert_eq "closing the list dispatches nothing" "" "$(cat "$SANDBOX/dispatch.log" 2>/dev/null)"

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
    -- A Lua function is a valid dispatcher (Hyprland runs it on the key).
    local what = type(d) == "function" and "lua:function" or (d.dsp == "dsp.exec_cmd" and d.args[1] or d.dsp)
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
# The style pickers sit on Omarchy's keys (default/hypr/bindings/utilities.lua):
# SUPER + CTRL + SPACE opened only "next background" before, so the background
# picker panel had no key at all.
assert_eq "SUPER + CTRL + SHIFT + SPACE opens the theme picker" \
    $'Theme picker\thaseen shell ipc panel toggle \'haseen.themepicker\'' "$(bound CTRL+SHIFT+SUPER+SPACE)"
assert_eq "SUPER + CTRL + SPACE opens the background picker" \
    $'Background picker\thaseen shell ipc panel toggle \'haseen.background\'' "$(bound CTRL+SUPER+SPACE)"
assert_eq "the next background moved to SUPER + CTRL + ALT + SPACE" \
    $'Next background\thaseen theme bg next' "$(bound ALT+CTRL+SUPER+SPACE)"
assert_eq "SUPER + CTRL + M opens the context menu (plan 062)" \
    $'Context menu\thaseen menu trigger.context' "$(bound CTRL+SUPER+M)"
# Every panel a key toggles is a shipped panel plugin.
for id in $(grep -o "panel toggle '[^']*'" <<<"$shipped" | cut -d"'" -f2 | sort -u); do
    assert_eq "bound panel $id is a shipped panel plugin" "panel" \
        "$(jq -r '.kinds[] | select(. == "panel")' "$REPO/share/haseen/shell/plugins/$id/manifest.json" 2>/dev/null)"
done
assert_eq "the system menu has one key" "SUPER+ESCAPE" "$(awk -F'\t' '$3 == "haseen menu system" { print $1 }' <<<"$shipped")"
assert_eq "the shipped config binds keys" true "$( (($(wc -l <<<"$shipped") > 60)) && echo true || echo false)"
assert_eq "no key is bound twice" "" "$(cut -f1 <<<"$shipped" | sort | uniq -d)"
# Omarchy's universal clipboard chords: the owner's muscle memory for paste.
for k in C V X; do
    assert_eq "SUPER + $k is a universal clipboard key" "lua:function" "$(bound SUPER+$k | cut -f2)"
done
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
