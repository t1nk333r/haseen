# shellcheck shell=bash
# haseen:covers bin/haseen-toggle-{fullscreen-desktop,monitor-workspaces,workspace-layout}
# haseen:covers share/haseen/default/hypr/{binds,init,monitor-workspaces,qconsole,workspace-modes}.lua
# haseen:covers share/haseen/lib/keybinds-scan.lua share/haseen/lib/settings.sh
# haseen:covers share/haseen/omarchy/bin/omarchy-hyprland-workspace-layout-*
# haseen:covers share/haseen/omarchy/bin/omarchy-toggle-fullscreen-desktop
# haseen:covers share/haseen/shell/plugins/haseen.workspaces/**
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Workspaces, the console and the binds from Omarchy 4.5 (plan 105):
# per-monitor workspaces (default/hypr/monitor-workspaces.lua) run against a
# small model of Hyprland adapted from Omarchy's own test
# (test/shell.d/hyprland-monitor-workspaces-test.sh@v4.5.0-rc1, MIT, Copyright
# (c) David Heinemeier Hansson); the floating workspace mode and the console
# against fakes of the hl calls they make; the new keys through the keybind
# sheet's scan of the real config; the commands against stubbed hyprctl and
# qs; the bar's per-monitor list under the Qt JS engine.

if ! command -v lua >/dev/null; then
    _fail "lua is not installed: the Hyprland config cannot be loaded"
    return 0
fi

# --- per-monitor workspaces: the model ---------------------------------------
sandbox mw
MW_FAKE="$SANDBOX/fake.lua"
cat >"$MW_FAKE" <<'LUA'
-- Monitors, workspaces and windows, with the parts of Hyprland's behaviour the
-- module leans on: workspaces are created on the focused monitor, moving a
-- visible workspace away leaves its monitor on another one or a fresh number,
-- focusing a workspace visible elsewhere on the current monitor swaps the two,
-- and an empty workspace nobody shows goes away. Adapted from Omarchy's test
-- (MIT, Copyright (c) David Heinemeier Hansson); haseen's `haseen` table in
-- place of Omarchy's `o`.

-- Neighbours map a monitor to the one in each direction, l, r, u or d.
world = { monitors = {}, workspaces = {}, windows = {}, neighbours = {}, focused = nil, active_window = nil, swaps = 0,
  handlers = {}, subscriptions = 0, binds = {}, unbinds = 0 }

haseen = {
  paths = { state_home = os.getenv("XDG_STATE_HOME") },
  bind_expressions = {},
  shell_quote = function(value) return "'" .. value .. "'" end,
  rebind = function(keys, description, action)
    world.unbinds = world.unbinds + 1
    world.binds[keys] = { description = description, action = action }
  end,
}

local monitor_object, workspace_object

function monitor_named(name)
  for _, monitor in ipairs(world.monitors) do
    if monitor.name == name then return monitor end
  end
end

local function workspace_numbered(id)
  for _, workspace in ipairs(world.workspaces) do
    if workspace.id == id then return workspace end
  end
end

local function create(id, monitor)
  local workspace = { id = id, monitor = monitor }
  world.workspaces[#world.workspaces + 1] = workspace
  return workspace
end

local function activate(workspace)
  monitor_named(workspace.monitor).active = workspace.id
end

local function windows_on(id)
  local count = 0
  for _, window in pairs(world.windows) do
    if window.workspace == id then count = count + 1 end
  end
  return count
end

local function cleanup()
  local kept = {}
  for _, workspace in ipairs(world.workspaces) do
    local monitor = monitor_named(workspace.monitor)
    if windows_on(workspace.id) > 0 or (monitor and monitor.active == workspace.id) then
      kept[#kept + 1] = workspace
    end
  end
  world.workspaces = kept
end

local function lowest_free()
  local id = 1
  while workspace_numbered(id) do id = id + 1 end
  return id
end

local function move_workspace(workspace, target)
  local old = monitor_named(workspace.monitor)
  if old and old.active == workspace.id then
    local fallback
    for _, other in ipairs(world.workspaces) do
      if other.monitor == old.name and other.id ~= workspace.id then fallback = other break end
    end
    fallback = fallback or create(lowest_free(), old.name)
    old.active = fallback.id
    if world.focused == old.name then
      target.active = workspace.id
      world.focused = target.name
    end
  end
  workspace.monitor = target.name
end

function workspace_object(workspace)
  if not workspace then return nil end
  return setmetatable({}, { __index = function(_, key)
    if key == "id" then return workspace.id end
    if key == "name" then return tostring(workspace.id) end
    if key == "special" then return false end
    if key == "windows" then return windows_on(workspace.id) end
    if key == "monitor" then return monitor_object(monitor_named(workspace.monitor)) end
  end })
end

function monitor_object(monitor)
  if not monitor then return nil end
  return setmetatable({
    set_workspace = function(_, spec)
      local workspace = workspace_numbered(tonumber(spec.workspace))
      if workspace and workspace.monitor == monitor.name then
        monitor.active = workspace.id
        world.focused = monitor.name
      end
    end,
  }, { __index = function(_, key)
    if key == "focused" then return world.focused == monitor.name end
    if key == "active_workspace" then return workspace_object(workspace_numbered(monitor.active)) end
    if key == "is_mirror" then return false end
    return monitor[key]
  end })
end

local function resolve(id)
  local workspace = workspace_numbered(id)
  return workspace or create(id, world.focused)
end

hl = {
  on = function(name, handler)
    world.handlers[name] = handler
    world.subscriptions = world.subscriptions + 1
  end,
  dispatch = function(dispatcher) return dispatcher() end,
  get_monitors = function()
    local list = {}
    for _, monitor in ipairs(world.monitors) do list[#list + 1] = monitor_object(monitor) end
    table.sort(list, function(left, right) return left.id < right.id end)
    return list
  end,
  get_monitor = function(selector)
    local neighbours = world.neighbours[world.focused] or {}
    if selector:match("^[lrud]$") then return monitor_object(monitor_named(neighbours[selector])) end
    return monitor_object(monitor_named(selector))
  end,
  get_active_monitor = function() return monitor_object(monitor_named(world.focused)) end,
  get_active_workspace = function() return workspace_object(workspace_numbered(monitor_named(world.focused).active)) end,
  get_workspace = function(id) return workspace_object(workspace_numbered(tonumber(id))) end,
  get_workspaces = function()
    local list = {}
    for _, workspace in ipairs(world.workspaces) do list[#list + 1] = workspace_object(workspace) end
    return list
  end,
  get_active_window = function()
    return world.active_window and { address = world.active_window } or nil
  end,
  get_window = function(selector)
    local address = selector:match("^address:(.+)$")
    return world.windows[address] and { address = address } or nil
  end,
  dsp = {
    focus = function(spec)
      return function()
        if spec.monitor then
          world.focused = spec.monitor
        elseif spec.window then
          local window = world.windows[spec.window:match("^address:(.+)$")]
          world.active_window = spec.window:match("^address:(.+)$")
          world.focused = workspace_numbered(window.workspace).monitor
        elseif spec.workspace then
          local workspace = resolve(tonumber(spec.workspace))
          activate(workspace)
          world.focused = workspace.monitor
        end
        cleanup()
      end
    end,
    workspace = {
      move = function(spec)
        return function()
          local target = monitor_named(spec.monitor)
          if not target then error("Monitor not found") end
          local id = spec.workspace and tonumber(spec.workspace) or monitor_named(world.focused).active
          move_workspace(workspace_numbered(id), target)
          cleanup()
        end
      end,
      change_id = function(spec)
        return function()
          local workspace = workspace_numbered(tonumber(spec.workspace))
          local old = workspace.id
          workspace.id = spec.id
          for _, monitor in ipairs(world.monitors) do
            if monitor.active == old then monitor.active = spec.id end
          end
          for _, window in pairs(world.windows) do
            if window.workspace == old then window.workspace = spec.id end
          end
        end
      end,
    },
    window = {
      move = function(spec)
        return function()
          if spec.monitor then
            local target = monitor_named(spec.monitor)
            if not target then error("Invalid monitor / monitor doesn't exist") end
            world.windows[world.active_window].workspace = target.active
            world.focused = target.name
            cleanup()
            return
          end
          local workspace = resolve(tonumber(spec.workspace))
          world.windows[spec.window:match("^address:(.+)$")].workspace = workspace.id
          if spec.follow then
            activate(workspace)
            world.focused = workspace.monitor
          end
          cleanup()
        end
      end,
    },
  },
}

-- A fresh config load, as a reload or the next session gives, with the
-- toggle on; load_disabled is the load without it.
function load_disabled()
  world.handlers, world.subscriptions, world.binds = {}, 0, {}
  return dofile(os.getenv("HASEEN_PATH") .. "/default/hypr/monitor-workspaces.lua")
end

function load_module()
  local m = load_disabled()
  m.enable()
  return m
end

function plug(name, id, description, active)
  world.monitors[#world.monitors + 1] = { name = name, id = id, description = description, active = active }
  if not workspace_numbered(active) then create(active, name) end
end

function unplug(name)
  local kept = {}
  for _, monitor in ipairs(world.monitors) do
    if monitor.name ~= name then kept[#kept + 1] = monitor end
  end
  world.monitors = kept
  -- Hyprland moves the workspaces to a monitor that is still there.
  for _, workspace in ipairs(world.workspaces) do
    if workspace.monitor == name then workspace.monitor = world.monitors[1].name end
  end
  if world.focused == name then world.focused = world.monitors[1].name end
end

function window(address, id)
  if not workspace_numbered(id) then create(id, world.focused) end
  world.windows[address] = { workspace = id }
end

function on(id)
  local workspace = workspace_numbered(id)
  return workspace and workspace.monitor
end

function shows(name)
  return monitor_named(name).active
end

function state_file(name)
  local file = io.open(os.getenv("XDG_STATE_HOME") .. "/haseen/" .. (name or "monitor-workspaces"))
  local content = file and file:read("a") or ""
  if file then file:close() end
  return content
end

function check(condition, message)
  if not condition then error(message, 2) end
end
LUA

# mw NAME LABEL LUA — run LUA in a fresh state home against the model; the
# scenario passes when every check() holds.
mw() {
    local state="$SANDBOX/state-$1"
    rm -rf "$state"
    mkdir -p "$state/haseen"
    capture env XDG_STATE_HOME="$state" lua -e "dofile('$MW_FAKE')" -e "$3"
    assert_status "per-monitor: $2" 0 "$STATUS"
    [[ $STATUS == 0 ]] || printf '    %s\n' "$OUTPUT" >&2
}

mw off "nothing runs until the toggle turns it on" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 2)
world.focused = "eDP-1"
local m = load_disabled()
check(world.subscriptions == 0, "events subscribed without the toggle: " .. world.subscriptions)
check(next(world.binds) == nil, "keys rebound without the toggle")
check(state_file() == "", "the state file was written without the toggle")
check(shows("DP-1") == 2, "a monitor was moved without the toggle")
check(haseen.workspaces == m, "the module is reachable as haseen.workspaces")
'

mw keys "SUPER + <n> act on the focused monitor, SUPER + SHIFT moves silently" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 11)
world.focused = "DP-1"
local m = load_module()
world.handlers["hyprland.start"]()
check(world.subscriptions == 5, "five events, not " .. world.subscriptions)
m.enable()
check(world.subscriptions == 5, "a second enable subscribed again")

local key = world.binds["SUPER + code:12"]
check(key and key.description == "Workspace 3", "SUPER + 3 is rebound")
check(haseen.bind_expressions[key.action] == "haseen.workspaces.focus(3)", "the sheet replays SUPER + 3")
local silent = world.binds["SUPER + SHIFT + code:12"]
check(silent.description == "Move window silently to workspace 3", "SUPER + SHIFT + 3 is the owner'"'"'s silent move")
check(haseen.bind_expressions[silent.action] == "haseen.workspaces.move_window(3, false)", "and it stays behind")
local follow = world.binds["SUPER + SHIFT + ALT + code:19"]
check(haseen.bind_expressions[follow.action] == "haseen.workspaces.move_window(10)", "ALT added follows")
check(world.binds["SUPER + SHIFT + ALT + LEFT"].description == "Move workspace to left monitor", "moving a workspace joins the block")
check(world.binds["SUPER + TAB"] ~= nil and world.binds["SUPER + mouse_down"] ~= nil, "walking stays on the monitor")

key.action()
check(shows("DP-1") == 13 and on(13) == "DP-1" and shows("eDP-1") == 1, "SUPER + 3 opens the focused monitor'"'"'s third workspace")
window("0xa", 13)
world.active_window = "0xa"
silent = world.binds["SUPER + SHIFT + code:13"].action
silent()
check(world.windows["0xa"].workspace == 14 and on(14) == "DP-1" and shows("DP-1") == 13, "a silent move stays behind")
hl.dispatch(m.move_window(5))
check(world.windows["0xa"].workspace == 15 and shows("DP-1") == 15, "a move follows the window")
hl.dispatch(m.focus(2, "eDP-1"))
check(shows("eDP-1") == 2 and world.focused == "eDP-1", "a named monitor goes to its own workspace")
check(haseen.bind_expressions[m.focus(2, "DP-1")] == "haseen.workspaces.focus(2, \"DP-1\")", "the bar names its monitor")
'

mw blocks "the laptop panel gets 1-10 and each other monitor the next free block" '
plug("DP-1", 0, "LG ULTRAGEAR 111", 1)
plug("DP-2", 1, "XENEON EDGE 222", 2)
plug("eDP-1", 2, "Samsung Panel", 3)
world.focused = "DP-1"
local m = load_module()
world.handlers["hyprland.start"]()
check(m.workspace_id(hl.get_monitor("eDP-1"), 1) == 1, "the laptop panel owns the first block")
check(m.workspace_id(hl.get_monitor("DP-1"), 1) == 11, "the next monitor owns the second")
check(m.workspace_id(hl.get_monitor("DP-2"), 10) == 30, "the third monitor owns the third")
check(state_file():find("1\tDP-1\tLG ULTRAGEAR 111\n", 1, true), "the blocks are saved for the bar: " .. state_file())

-- The next session: the XENEON alone, on a renamed connector.
world.monitors, world.workspaces = {}, {}
plug("DP-7", 0, "XENEON EDGE 222", 1)
world.focused = "DP-7"
m = load_module()
world.handlers["hyprland.start"]()
check(m.workspace_id(hl.get_monitor("DP-7"), 1) == 21, "a monitor alone on a renamed connector got " .. m.workspace_id(hl.get_monitor("DP-7"), 1))
check(shows("DP-7") == 21, "one monitor that was third starts on 21, its own first: " .. shows("DP-7"))
check(state_file():find("0\t\tSamsung Panel\n", 1, true), "an unplugged monitor keeps its block: " .. state_file())
'

mw reclaim "a workspace an unplug left elsewhere comes home on its key, without a swap" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 11)
world.focused = "DP-1"
local m = load_module()
world.handlers["hyprland.start"]()
window("0xa", 13)
world.workspaces[#world.workspaces].monitor = "eDP-1"
monitor_named("eDP-1").active = 13
hl.dispatch(m.focus(3))
check(world.swaps == 0, "the workspaces were swapped")
check(shows("DP-1") == 13 and on(13) == "DP-1", "SUPER + 3 brings the workspace home")
check(shows("eDP-1") >= 1 and shows("eDP-1") <= 10, "the laptop falls back to one of its own, not " .. shows("eDP-1"))
'

mw hotplug "an unplugged monitor's workspaces come back with it, whatever the connector" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 11)
world.focused = "eDP-1"
local m = load_module()
world.handlers["hyprland.start"]()
window("0xa", 1)
world.focused = "DP-1"
window("0xb", 12)
monitor_named("DP-1").active = 12
world.focused = "eDP-1"
world.active_window = "0xa"

unplug("DP-1")
world.handlers["monitor.removed"]({ name = "DP-1" })
check(world.windows["0xb"].workspace == 2 and on(2) == "eDP-1", "it joins the other monitor after its own, not " .. world.windows["0xb"].workspace)
check(state_file("monitor-workspaces-merged"):find("2\t12\tLG\n", 1, true), "where it came from is kept: " .. state_file("monitor-workspaces-merged"))

hl.dispatch(hl.dsp.focus({ workspace = "2" }))
load_module()
world.handlers["config.reloaded"]()
check(shows("eDP-1") == 2 and world.windows["0xb"].workspace == 2, "a reload leaves it be")

plug("DP-3", 3, "LG", 3)
world.handlers["monitor.added"]({ name = "DP-3" })
check(world.windows["0xb"].workspace == 12 and on(12) == "DP-3", "it goes home under its old number, not " .. world.windows["0xb"].workspace)
check(shows("DP-3") >= 11 and shows("DP-3") <= 20, "the returning monitor shows its own, not " .. shows("DP-3"))
check(on(3) == nil, "the number Hyprland gave it is left to go away")
'

mw merge "workspaces join after the monitor's own, in order, until theirs returns" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 11)
plug("DP-2", 2, "XENEON", 21)
world.focused = "eDP-1"
local m = load_module()
world.handlers["hyprland.start"]()
window("0xa", 1)
window("0xb", 5)
world.focused = "DP-1"
window("0xc", 11)
window("0xd", 12)
window("0xe", 13)
world.focused = "eDP-1"
unplug("DP-1")
world.handlers["monitor.removed"]({ name = "DP-1" })
check(world.windows["0xc"].workspace == 6 and world.windows["0xd"].workspace == 7 and world.windows["0xe"].workspace == 8,
  "the workspaces follow the laptop'"'"'s own, in order")

hl.dispatch(hl.dsp.focus({ workspace = "8" }))
world.neighbours = { ["eDP-1"] = { u = "DP-2" } }
hl.dispatch(m.move_to_monitor("u"))
check(world.windows["0xe"].workspace == 28 and on(28) == "DP-2", "moved by hand, it joined the block above")
local moved = world.windows["0xe"].workspace

plug("DP-3", 3, "LG", 3)
world.handlers["monitor.added"]({ name = "DP-3" })
check(world.windows["0xc"].workspace == 11 and on(11) == "DP-3", "the remembered workspace went home")
check(world.windows["0xe"].workspace == moved and on(moved) == "DP-2", "the one moved by hand stayed")

-- A new session starts with nothing to bring back.
load_module()
world.handlers["hyprland.start"]()
check(state_file("monitor-workspaces-merged") == "", "a new session forgot where workspaces came from")
'

mw single "one monitor in block 0 keeps 1-10; a workspace above 10 joins it" '
plug("HDMI-A-1", 0, "Dell", 1)
world.focused = "HDMI-A-1"
window("0xa", 1)
window("0xb", 12)
local m = load_module()
world.handlers["config.reloaded"]()
check(m.workspace_id(hl.get_monitor("HDMI-A-1"), 3) == 3, "SUPER + 3 is workspace 3, as with global numbers")
check(world.windows["0xb"].workspace == 2, "workspace 12 was renumbered into the block: " .. world.windows["0xb"].workspace)
'

mw window_to_monitor "a window moves to the monitor in a direction, and nowhere when there is none" '
plug("eDP-1", 0, "Panel", 1)
plug("DP-1", 1, "LG", 11)
world.neighbours = { ["eDP-1"] = { u = "DP-1" }, ["DP-1"] = { d = "eDP-1" } }
world.focused = "eDP-1"
local m = load_disabled()
window("0xa", 1)
world.active_window = "0xa"
hl.dispatch(m.move_window_to_monitor("u"))
check(world.windows["0xa"].workspace == 11, "the window lands on the workspace the monitor above shows")
check(world.focused == "DP-1", "focus goes with the window")
check(haseen.bind_expressions[m.move_window_to_monitor("d")] == "haseen.workspaces.move_window_to_monitor(\"d\")", "the sheet replays it")
hl.dispatch(m.move_window_to_monitor("u"))
check(world.windows["0xa"].workspace == 11 and world.focused == "DP-1", "a move toward no monitor did something")
'

# --- the floating workspace mode ---------------------------------------------
sandbox modes
MODES_FAKE="$SANDBOX/modes.lua"
cat >"$MODES_FAKE" <<'LUA'
-- Windows on workspaces, with what the floating mode dispatches applied to
-- them: float, tag, resize, center, move. Timers run at once.
world = { windows = {}, active = 1, follow_mouse = 1, handlers = {}, subscriptions = 0, rules = {}, configs = 0 }
haseen = {}
local monitor = { width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }

local function has(window, tag)
  for _, t in ipairs(window.tags) do
    if t == tag then return true end
  end
  return false
end

function win(address, ws, extra)
  local w = { address = address, workspace = { id = ws }, floating = false, fullscreen = 0, pinned = false, tags = {}, monitor = monitor }
  for k, v in pairs(extra or {}) do w[k] = v end
  world.windows[#world.windows + 1] = w
  return w
end

hl = {
  on = function(name, fn)
    world.handlers[name] = world.handlers[name] or {}
    table.insert(world.handlers[name], fn)
    world.subscriptions = world.subscriptions + 1
  end,
  dispatch = function(d) d() end,
  timer = function(fn) fn() end,
  get_windows = function(filter)
    local out = {}
    for _, w in ipairs(world.windows) do
      if not (filter and filter.tag) or has(w, filter.tag) then out[#out + 1] = w end
    end
    return out
  end,
  get_workspace_windows = function(ws)
    local out = {}
    for _, w in ipairs(world.windows) do
      if tostring(w.workspace.id) == tostring(ws) then out[#out + 1] = w end
    end
    return out
  end,
  get_active_workspace = function() return { id = world.active } end,
  get_config = function(key) if key == "input.follow_mouse" then return world.follow_mouse end end,
  config = function(t)
    world.configs = world.configs + 1
    if t.input and t.input.follow_mouse ~= nil then world.follow_mouse = t.input.follow_mouse end
  end,
  workspace_rule = function(r) world.rules[r.workspace] = r.layout end,
  dsp = { window = {
    float = function(s) return function() s.window.floating = s.action == "on" end end,
    tag = function(s) return function()
      local name = s.tag:sub(2)
      if s.tag:sub(1, 1) == "+" then
        if not has(s.window, name) then table.insert(s.window.tags, name) end
      else
        for i, t in ipairs(s.window.tags) do if t == name then table.remove(s.window.tags, i) break end end
      end
    end end,
    resize = function(s) return function() s.window.size = { s.x, s.y } end end,
    center = function(s) return function() s.window.centered = true end end,
    move = function(s) return function() s.window.nudged = { s.x, s.y } end end,
  } },
}

function fire(name, ...)
  for _, fn in ipairs(world.handlers[name] or {}) do fn(...) end
end

function load_modes()
  world.handlers, world.subscriptions = {}, 0
  return dofile(os.getenv("HASEEN_PATH") .. "/default/hypr/workspace-modes.lua")
end

function check(condition, message)
  if not condition then error(message, 2) end
end
LUA

modes() {
    capture lua -e "dofile('$MODES_FAKE')" -e "$2"
    assert_status "floating mode: $1" 0 "$STATUS"
    [[ $STATUS == 0 ]] || printf '    %s\n' "$OUTPUT" >&2
}

modes "tiled layouts subscribe to nothing and set the workspace rule" '
local m = load_modes()
haseen.workspace_mode({ workspace = "2", mode = "scrolling" })
check(world.rules["2"] == "scrolling", "scrolling is a workspace rule")
check(world.subscriptions == 0, "a tiled mode subscribed to " .. world.subscriptions .. " events")
m.apply()
check(world.subscriptions == 0, "apply subscribed with nothing floating")
check(world.configs == 0, "input was touched with nothing floating")
'

modes "floating floats the workspace's tiled windows, and only those it floated tile again" '
local m = load_modes()
local tiled = win("0xa", 3)
local dialog = win("0xb", 3, { floating = true })
local full = win("0xc", 3, { fullscreen = 2 })
local other = win("0xd", 4)
haseen.workspace_mode({ workspace = "3", mode = "floating" })
check(m.mode(3) == "floating", "the mode is kept")
check(world.rules["3"] == nil, "floating is not a layout Hyprland knows")
check(tiled.floating and tiled.tags[1] == "haseen-mode-floated", "the tiled window floats, claimed")
check(tiled.size[1] == 1100 and tiled.size[2] == 714 and tiled.centered, "at a comfortable size in the middle: " .. tiled.size[1] .. "x" .. tiled.size[2])
check(#dialog.tags == 0, "a window floating on its own account is not claimed")
check(not full.floating, "a fullscreen window is left as it is")
check(not other.floating, "another workspace is left alone")

haseen.workspace_mode({ workspace = "3", mode = "dwindle" })
check(not tiled.floating and #tiled.tags == 0, "dwindle tiles what the mode floated")
check(dialog.floating, "and leaves the dialog floating")
check(world.rules["3"] == "dwindle", "with dwindle as its rule")
'

modes "windows coming and going follow the mode; a pinned one is left be" '
local m = load_modes()
haseen.workspace_mode({ workspace = "3", mode = "floating" })
local new = win("0xa", 3)
fire("window.open", new)
check(new.floating and new.tags[1] == "haseen-mode-floated", "a window opening there floats")
new.workspace = { id = 4 }
fire("window.move_to_workspace", new, { id = 4 })
check(not new.floating and #new.tags == 0, "carried out to a tiled workspace, it tiles")
local pinned = win("0xb", 3)
fire("window.open", pinned)
pinned.pinned = true
haseen.workspace_mode({ workspace = "3", mode = "dwindle" })
check(pinned.floating, "a pinned window is not tiled (that would unpin it)")
local special = win("0xc", -98)
fire("window.open", special)
check(not special.floating, "a special or named workspace keeps what a window arrived with")
'

modes "a floating workspace focuses on click, and gives the user's hover setting back" '
local m = load_modes()
world.follow_mouse = 2
world.active = 3
haseen.workspace_mode({ workspace = "3", mode = "floating" })
check(world.follow_mouse == 0, "follow_mouse is 0 on a floating workspace")
world.active = 4
fire("workspace.active")
check(world.follow_mouse == 2, "the value read on the way in comes back: " .. world.follow_mouse)
world.active = 3
fire("monitor.focused")
check(world.follow_mouse == 0, "back on the floating workspace")
'

modes "a reload with the mode gone tiles what it floated; a bad spec fails" '
local m = load_modes()
local w = win("0xa", 3)
haseen.workspace_mode({ workspace = "3", mode = "floating" })
check(w.floating, "floated")
m = load_modes()
m.apply()
check(not w.floating and #w.tags == 0, "the window the old mode floated tiles again after a reload")
check(not pcall(haseen.workspace_mode, { workspace = "-98", mode = "floating" }), "a negative id is refused")
check(not pcall(haseen.workspace_mode, { workspace = "3", mode = "glassy" }), "an unknown mode is refused")
'

# --- the console ---------------------------------------------------------------
sandbox console
CONSOLE_FAKE="$SANDBOX/console.lua"
cat >"$CONSOLE_FAKE" <<'LUA'
world = { rules = {}, config = {}, animations = {}, handlers = {}, refreshes = 0, visible = false, windows = {} }
local monitor = { width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 30, bottom = 0, left = 0, right = 0 } }
world.monitor = monitor
haseen = { launch = function(c) return "uwsm-app -- " .. c end }
hl = {
  config = function(t) if t.decoration then world.config.dim_special = t.decoration.dim_special end end,
  workspace_rule = function(r) world.rule = r; world.rules[#world.rules + 1] = r end,
  animation = function(a) world.animations[a.leaf] = a end,
  on = function(name, fn) world.handlers[name] = fn end,
  get_workspace = function(name) return { name = name, visible = world.visible, monitor = world.visible and world.monitor or nil } end,
  get_workspace_windows = function() return world.windows end,
  get_active_monitor = function() return world.monitor end,
  exec_scheduled_prop_refresh_immediately = function() world.refreshes = world.refreshes + 1 end,
}
function check(condition, message)
  if not condition then error(message, 2) end
end
function load_console()
  dofile(os.getenv("HASEEN_PATH") .. "/default/hypr/qconsole.lua")
end
LUA

console() {
    capture lua -e "dofile('$CONSOLE_FAKE')" -e "$2"
    assert_status "console: $1" 0 "$STATUS"
    [[ $STATUS == 0 ]] || printf '    %s\n' "$OUTPUT" >&2
}

console "its own special workspace, a terminal on first open, dimmed and dropping down" '
load_console()
local r = world.rule
check(r.workspace == "special:console", "the console is special:console, not the scratchpad: " .. r.workspace)
check(r.on_created_empty == "[workspace special:console silent] uwsm-app -- \"${TERMINAL:-foot}\"", "the first open starts the terminal: " .. r.on_created_empty)
check(r.no_border and r.gaps_in == 0, "no border, no inner gaps")
check(world.config.dim_special == 0.6, "the workspace underneath is dimmed")
check(world.animations.specialWorkspaceIn.style == "slide top", "it drops down")
check(world.animations.specialWorkspaceOut.style == "slide bottom", "and retracts up")
'

console "half the usable height, boxed 2:1 alone, full width with a second app" '
load_console()
-- 1920x1080 with a 30 px bar: 1050 usable, 525 tall, 1050 wide alone.
local g = world.rule.gaps_out
check(g.top == 0 and g.bottom == 525 and g.left == 435 and g.right == 435, "alone: " .. g.left .. "/" .. g.bottom)
world.windows = { { floating = false }, { floating = false } }
world.visible = true
world.handlers["window.open"]()
g = world.rule.gaps_out
check(g.left == 0 and g.right == 0 and g.bottom == 525, "two apps get the full width: " .. g.left)
check(world.refreshes == 1, "the new gaps land in the same pass")
local before = #world.rules
world.handlers["monitor.focused"]()
check(#world.rules == before, "a hop that changes nothing writes no rule")
world.visible = false
world.windows = {}
world.handlers["window.open"]()
check(#world.rules == before, "a hidden console is not refitted for every window")
'

console "a monitor that cannot be read is skipped at load" '
hl.get_active_monitor = function() return {} end
load_console()
local g = world.rule.gaps_out
check(g.left == 0 and g.bottom == 0, "the whole work area until a monitor can be read")
'

# --- the keys in the real config ------------------------------------------------
# The keybind sheet's scan (lib/keybinds-scan.lua) runs the seeded config the
# way `haseen keybinds` does: modmask, description, key, kind, action, section.
sandbox keys
mkdir -p "$XDG_CONFIG_HOME/hypr" "$XDG_STATE_HOME/haseen/toggles/hypr"
cp "$HASEEN_PATH/default/hypr/user/hyprland.lua" "$XDG_CONFIG_HOME/hypr/hyprland.lua"
scan() { capture timeout 30 lua "$HASEEN_PATH/lib/keybinds-scan.lua" "$XDG_CONFIG_HOME/hypr/hyprland.lua"; }
row() { awk -F'\t' -v m="$1" -v k="$2" '$1 == m && toupper($3) == toupper(k) { print $2 "|" $4 "|" $5 "|" $6 }' <<<"$OUTPUT"; }
SUPER=64 SHIFT=1 CTRL=4 ALT=8

scan
assert_status "the config scans" 0 "$STATUS"
assert_eq "no key is bound twice" "" "$(cut -f1,3 <<<"$OUTPUT" | tr '[:lower:]' '[:upper:]' | sort | uniq -d)"
assert_eq "SUPER + GRAVE opens the console" 'Console|lua|hl.dsp.workspace.toggle_special("console")|Workspaces' \
    "$(row $SUPER code:49)"
assert_eq "SUPER + SHIFT + GRAVE sends a window to it" \
    'Move window to console|lua|hl.dsp.window.move({ follow = false, workspace = "special:console" })|Workspaces' \
    "$(row $((SUPER + SHIFT)) code:49)"
assert_eq "SUPER + CTRL + ALT + F is the full-screen desktop" \
    'Full-screen desktop|exec|haseen toggle fullscreen-desktop|Windows' "$(row $((SUPER + CTRL + ALT)) F)"
assert_eq "SUPER + CTRL + ALT + C takes the screenshot" \
    'Screenshot|exec|haseen capture screenshot|Capture' "$(row $((SUPER + CTRL + ALT)) C)"
assert_eq "PRINT still takes it too" 'Screenshot|exec|haseen capture screenshot|Capture' "$(row 0 PRINT)"
for pair in "LEFT l left" "RIGHT r right" "UP u up" "DOWN d down"; do
    read -r key dir name <<<"$pair"
    assert_eq "SUPER + SHIFT + CTRL + $key moves the window to the $name monitor" \
        "Move window to $name monitor|lua|haseen.workspaces.move_window_to_monitor(\"$dir\")|Workspaces" \
        "$(row $((SUPER + SHIFT + CTRL)) "$key")"
done
assert_eq "without the toggle SUPER + 3 is global workspace 3" \
    'Workspace 3|lua|hl.dsp.focus({ workspace = "3" })|Workspaces' "$(row $SUPER code:12)"
assert_eq "the scratchpad keeps SUPER + S" \
    'Scratchpad|lua|hl.dsp.workspace.toggle_special("scratchpad")|Workspaces' "$(row $SUPER S)"
assert_eq "the HYPER layer keeps its eleven keys" 11 \
    "$(awk -F'\t' -v m=$((SUPER + SHIFT + ALT + CTRL)) '$1 == m { n++ } END { print n + 0 }' <<<"$OUTPUT")"
global_count="$(wc -l <<<"$OUTPUT")"

printf '%s\n' '-- haseen toggle' 'if haseen.workspaces then haseen.workspaces.enable() end' \
    >"$XDG_STATE_HOME/haseen/toggles/hypr/monitor-workspaces.lua"
printf '%s\n' 'haseen.workspace_mode({ workspace = "3", mode = "floating" })' \
    >"$XDG_STATE_HOME/haseen/toggles/hypr/workspace-layout-3.lua"
scan
assert_status "with the toggle and a floating workspace the scan still ends" 0 "$STATUS"
assert_eq "the same keys, each once" "$global_count" "$(wc -l <<<"$OUTPUT")"
assert_eq "no key is bound twice with the toggle" "" "$(cut -f1,3 <<<"$OUTPUT" | tr '[:lower:]' '[:upper:]' | sort | uniq -d)"
assert_eq "SUPER + 3 goes to the focused monitor's third, in Workspaces" \
    'Workspace 3|lua|haseen.workspaces.focus(3)|Workspaces' "$(row $SUPER code:12)"
assert_eq "SUPER + SHIFT + 3 still moves silently" \
    'Move window silently to workspace 3|lua|haseen.workspaces.move_window(3, false)|Workspaces' "$(row $((SUPER + SHIFT)) code:12)"
assert_eq "SUPER + SHIFT + ALT + 0 follows the window" \
    'Move window to workspace 10|lua|haseen.workspaces.move_window(10)|Workspaces' "$(row $((SUPER + SHIFT + ALT)) code:19)"
assert_eq "SUPER + TAB stays on the monitor" \
    'Next workspace|lua|hl.dsp.focus({ workspace = "m+1" })|Workspaces' "$(row $SUPER TAB)"
assert_eq "the HYPER layer is untouched by the toggle" 11 \
    "$(awk -F'\t' -v m=$((SUPER + SHIFT + ALT + CTRL)) '$1 == m { n++ } END { print n + 0 }' <<<"$OUTPUT")"

# The user's own bindings.lua loads after the toggle, so its key still wins.
printf '%s\n' 'haseen.rebind("SUPER + code:12", "Mine", "true")' >"$XDG_CONFIG_HOME/hypr/bindings.lua"
scan
assert_eq "a user bind on the same key wins over the toggle" 'Mine|exec|true|' "$(row $SUPER code:12)"

# --- haseen toggle monitor-workspaces ---------------------------------------------
sandbox cli-mw
LOG="$SANDBOX/calls"
: >"$LOG"
T="$HOME/.local/state/haseen/toggles/hypr"
capture haseen toggle monitor-workspaces status
assert_eq "per-monitor workspaces are off by default" "off" "$OUTPUT"
capture haseen toggle monitor-workspaces on --dry-run
assert_status "on --dry-run" 0 "$STATUS"
assert_dry_pure "monitor-workspaces on" "$OUTPUT"
assert_contains "on plans the toggle file" "$OUTPUT" "DRYRUN: write $T/monitor-workspaces.lua:"
assert_contains "that turns the module on" "$OUTPUT" "haseen.workspaces.enable()"
assert_contains "and a reload" "$OUTPUT" "DRYRUN: hyprctl reload"
assert_eq "a dry run writes nothing" no "$([[ -e $T/monitor-workspaces.lua ]] && echo yes || echo no)"
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"; echo ok'
stub notify-send 'exit 0'
capture haseen toggle monitor-workspaces
assert_status "toggle from off turns it on" 0 "$STATUS"
assert_contains "the file calls enable" "$(cat "$T/monitor-workspaces.lua" 2>/dev/null)" "haseen.workspaces.enable()"
assert_eq "Hyprland reloads" "hyprctl reload" "$(cat "$LOG")"
assert_eq "status says on" "on" "$(haseen toggle monitor-workspaces status)"
capture haseen settings list --json
assert_eq "the settings index lists it" "on" "$(jq -r '.[] | select(.key == "monitor-workspaces") | .value' <<<"$OUTPUT")"
capture haseen toggle monitor-workspaces off
assert_eq "off removes the file" no "$([[ -e $T/monitor-workspaces.lua ]] && echo yes || echo no)"
assert_eq "and reloads again" 2 "$(grep -c 'hyprctl reload' "$LOG")"
capture haseen toggle monitor-workspaces sideways
assert_status "an unknown action is a usage error" 2 "$STATUS"

# --- haseen toggle fullscreen-desktop -----------------------------------------------
sandbox cli-full
LOG="$SANDBOX/calls"
: >"$LOG"
T="$HOME/.local/state/haseen/toggles/hypr"
BAR="$SANDBOX/bar-hidden"
echo false >"$BAR"
# The shell answers the bar's state and flips it; hyprctl and notify-send log.
stub qs 'case "$*" in
*"ipc call bar status"*) h=$(cat "'"$BAR"'"); [ "$h" = none ] || echo "{\"hidden\":$h}" ;;
*"ipc call bar toggle"*) echo "bar toggle" >>"'"$LOG"'"; echo shown ;;
*) echo "STUB-CALLED: qs $*" >&2; exit 97 ;;
esac'
capture haseen toggle fullscreen-desktop --dry-run
assert_status "fullscreen --dry-run" 0 "$STATUS"
assert_dry_pure "fullscreen-desktop" "$OUTPUT"
assert_contains "a shown bar is hidden" "$OUTPUT" "haseen-shell-ipc bar toggle"
assert_contains "and the gaps go" "$OUTPUT" "DRYRUN: write $T/no-gaps.lua:"
assert_eq "a dry run changes nothing" "" "$(cat "$LOG")"
stub hyprctl 'echo "hyprctl $1" >>"'"$LOG"'"; echo ok'
stub notify-send 'exit 0'
capture haseen toggle fullscreen-desktop
assert_eq "toggle from a normal desktop: bar hidden, gaps gone" "bar toggle|hyprctl eval" "$(paste -sd'|' "$LOG")"
assert_eq "the gaps toggle is on" yes "$([[ -e $T/no-gaps.lua ]] && echo yes || echo no)"
assert_contains "it says so" "$OUTPUT" "Full-screen desktop on"
echo true >"$BAR"
: >"$LOG"
capture haseen toggle fullscreen-desktop
assert_eq "toggle with both off brings both back" "bar toggle|hyprctl reload" "$(paste -sd'|' "$LOG")"
assert_eq "the gaps toggle is off" no "$([[ -e $T/no-gaps.lua ]] && echo yes || echo no)"
: >"$LOG"
capture haseen toggle fullscreen-desktop
assert_eq "a lone hidden bar is pulled into line: only the gaps change" "hyprctl eval" "$(paste -sd'|' "$LOG")"
echo none >"$BAR"
: >"$LOG"
capture haseen toggle fullscreen-desktop off
assert_contains "a bar that does not answer is left alone" "$OUTPUT" "only the gaps change"
assert_eq "and the gaps still come back" "hyprctl reload" "$(paste -sd'|' "$LOG")"
capture haseen toggle fullscreen-desktop sideways
assert_status "an unknown action is a usage error" 2 "$STATUS"

# --- haseen toggle workspace-layout ------------------------------------------------
sandbox cli-layout
LOG="$SANDBOX/calls"
: >"$LOG"
T="$HOME/.local/state/haseen/toggles/hypr"
TILED="$SANDBOX/tiled"
WSID="$SANDBOX/wsid"
EVAL="$SANDBOX/eval-status"
echo dwindle >"$TILED"
echo 3 >"$WSID"
echo 0 >"$EVAL"
stub hyprctl 'case "$1" in
activeworkspace) echo "{\"id\":$(cat "'"$WSID"'"),\"tiledLayout\":\"$(cat "'"$TILED"'")\"}" ;;
workspaces) echo "[{\"id\":5,\"tiledLayout\":\"scrolling\"}]" ;;
eval) echo "hyprctl eval $2" >>"'"$LOG"'"; exit "$(cat "'"$EVAL"'")" ;;
*) echo "STUB-CALLED: hyprctl $*" >&2; exit 97 ;;
esac'
stub notify-send 'exit 0'
file="$T/workspace-layout-3.lua"
capture haseen toggle workspace-layout --dry-run
assert_dry_pure "workspace-layout" "$OUTPUT"
assert_contains "dwindle steps to scrolling" "$OUTPUT" 'DRYRUN: hyprctl eval haseen.workspace_mode({ workspace = "3", mode = "scrolling" })'
assert_eq "a dry run applies nothing" "" "$(cat "$LOG")"
haseen toggle workspace-layout >/dev/null
assert_eq "scrolling is applied" 'hyprctl eval haseen.workspace_mode({ workspace = "3", mode = "scrolling" })' "$(cat "$LOG")"
assert_eq "and saved" 'haseen.workspace_mode({ workspace = "3", mode = "scrolling" })' "$(cat "$file")"
echo scrolling >"$TILED"
haseen toggle workspace-layout >/dev/null
assert_contains "scrolling steps to floating" "$(cat "$file")" 'mode = "floating"'
assert_eq "current reads the saved floating mode" floating "$(haseen toggle workspace-layout current)"
assert_eq "a workspace without one reads Hyprland's layout" scrolling "$(haseen toggle workspace-layout current 5)"
haseen toggle workspace-layout >/dev/null
assert_eq "floating steps back to dwindle, the default, saved as nothing" no "$([[ -e $file ]] && echo yes || echo no)"
assert_contains "and applied" "$(tail -n1 "$LOG")" 'mode = "dwindle"'
echo dwindle >"$TILED"
haseen toggle workspace-layout back >/dev/null
assert_contains "back from dwindle is floating" "$(cat "$file")" 'mode = "floating"'
haseen toggle workspace-layout back >/dev/null
assert_contains "back from floating is scrolling" "$(cat "$file")" 'mode = "scrolling"'
printf '%s\n' 'hl.workspace_rule({ workspace = "3", layout = "scrolling" })' >"$file"
echo scrolling >"$TILED"
assert_eq "a file from before plan 105 still reads as its layout" scrolling "$(haseen toggle workspace-layout current)"
echo 1 >"$EVAL"
rm -f "$file"
capture haseen toggle workspace-layout floating
assert_status "a layout Hyprland refuses fails" 1 "$STATUS"
assert_eq "and is not saved" no "$([[ -e $file ]] && echo yes || echo no)"
echo 0 >"$EVAL"
echo -98 >"$WSID"
: >"$LOG"
capture haseen toggle workspace-layout
assert_status "a named workspace is refused" 1 "$STATUS"
assert_eq "nothing reaches Hyprland for it" "" "$(cat "$LOG")"
assert_eq "nothing is saved for it" no "$(compgen -G "$T/*-98*" >/dev/null && echo yes || echo no)"

# Omarchy's answers go through the same command.
OMA="$HASEEN_PATH/omarchy/bin"
echo 3 >"$WSID"
echo dwindle >"$TILED"
printf '%s\n' 'haseen.workspace_mode({ workspace = "3", mode = "floating" })' >"$file"
assert_eq "omarchy's current reports floating" floating "$("$OMA/omarchy-hyprland-workspace-layout-current")"
: >"$LOG"
"$OMA/omarchy-hyprland-workspace-layout-toggle" back >/dev/null
assert_contains "omarchy's back steps back: floating to scrolling" "$(cat "$LOG")" 'mode = "scrolling"'
echo scrolling >"$TILED"
"$OMA/omarchy-hyprland-workspace-layout-toggle" >/dev/null
assert_contains "omarchy's toggle steps on" "$(cat "$file")" 'mode = "floating"'
stub hyprctl 'case "$*" in "getoption general.layout -j") echo "{\"str\":\"dwindle\"}" ;; *) exit 97 ;; esac'
capture "$OMA/omarchy-hyprland-workspace-layout-default" floating
assert_status "a floating default is refused" 1 "$STATUS"
assert_contains "with the per-workspace way" "$OUTPUT" "haseen toggle workspace-layout floating"
capture "$OMA/omarchy-toggle-fullscreen-desktop" sideways
assert_status "omarchy's fullscreen takes only toggle, on and off" 1 "$STATUS"

# --- the bar: per-monitor rows under the Qt JS engine --------------------------------
sandbox bar
WIDGET="$HASEEN_PATH/shell/plugins/haseen.workspaces"
body="$(cat "$WIDGET/Widget.qml")"
assert_not_contains "the widget never polls" "$body" "Timer {"
assert_contains "it watches the toggle Hyprland loads" "$body" '"/toggles/hypr/monitor-workspaces.lua"'
assert_contains "and the blocks Hyprland writes" "$body" '"/monitor-workspaces"'
assert_contains "the toggle is read again on a config reload" "$body" 'name === "configreloaded"'
assert_contains "it keeps Omarchy's MIT notice" "$(cat "$WIDGET/Workspaces.js")" "MIT, Copyright (c) David"
QML=/usr/lib/qt6/bin/qml
cat >"$SANDBOX/Units.qml" <<EOF
import QtQuick
import "file://$WIDGET/Workspaces.js" as W

Window {
    property int failures: 0
    function eq(name, expected, actual) {
        const e = JSON.stringify(expected), a = JSON.stringify(actual);
        if (e === a)
            console.warn("UNIT-PASS " + name);
        else {
            failures++;
            console.warn("UNIT-FAIL " + name + " expected " + e + " got " + a);
        }
    }
    Component.onCompleted: {
        try {
            const blocks = W.readBlocks("0\teDP-1\tSamsung Panel\n1\t\tLG 111\n2\tDP-3\tXENEON\nbad line\n");
            eq("blocks by connector, unplugged ones skipped", { "eDP-1": 0, "DP-3": 2 }, blocks);
            eq("the bar's block from the file", 2, W.monitorBlock(blocks, "DP-3", 1));
            eq("before the file, the block it shows", 1, W.monitorBlock({}, "DP-1", 13));
            eq("before anything, the first", 0, W.monitorBlock({}, "DP-1", -1));
            const ws = [{ id: 23, monitor: "DP-3" }, { id: 27, monitor: "DP-3" }, { id: 3, monitor: "eDP-1" }, { id: 14, monitor: "DP-3" }, { id: 12, monitor: "DP-3" }, { id: -98, monitor: "DP-3" }];
            eq("own first five, the rest of the block that exists, then guests", [21, 22, 23, 24, 25, 27, 12, 14], W.monitorWorkspaceIds(ws, 5, "DP-3", 2));
            eq("another monitor's workspace is not a guest", false, W.monitorWorkspaceIds(ws, 5, "DP-3", 2).includes(3));
            eq("persistent 0 shows only what exists", [23, 27, 12, 14], W.monitorWorkspaceIds(ws, 0, "DP-3", 2));
            eq("slot label", "7", W.slotLabel(27));
            eq("the tenth slot is the 0 key", "0", W.slotLabel(30));
            eq("own focus names the monitor", 'haseen.workspaces.focus(3, "DP-3")', W.monitorFocusCommand(23, 2, "DP-3", true));
            eq("a guest is focused as it is", 'hl.dsp.focus({ workspace = "12" })', W.monitorFocusCommand(12, 2, "DP-3", true));
            eq("legacy config", "workspace 23", W.monitorFocusCommand(23, 2, "DP-3", false));
            eq("wheel down walks on", 24, W.stepInRow([21, 22, 23, 24], 23, -1));
            eq("wheel up walks back", 22, W.stepInRow([21, 22, 23, 24], 23, 1));
            eq("held at the end", -1, W.stepInRow([21, 22, 23, 24], 24, -3));
            eq("not in the row", -1, W.stepInRow([21, 22], 5, 1));
            eq("global numbers unchanged", [1, 2, 3, 4, 5, 7], W.workspaceIds([{ id: 7, monitor: "eDP-1" }, { id: 12, monitor: "eDP-1" }], 5, "eDP-1", false));
        } catch (e) {
            failures++;
            console.warn("UNIT-FAIL exception " + e);
        }
        Qt.exit(failures > 0 ? 1 : 0);
    }
}
EOF
if [[ -x $QML ]]; then
    set +e
    units="$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 NO_AT_BRIDGE=1 timeout 60 "$QML" "$SANDBOX/Units.qml" 2>&1)"
    rc=$?
    set -e
    assert_status "the bar's units run" 0 "$rc"
    while read -r line; do
        assert_eq "js: ${line#*UNIT-FAIL }" "" "fail"
    done < <(grep 'UNIT-FAIL' <<<"$units" || true)
    assert_eq "js unit count" 17 "$(grep -c 'UNIT-PASS' <<<"$units")"
else
    _fail "qml runner missing: $QML"
fi

# --- the bar in the real engine: the toggle and the blocks are watched -------------
QS_BIN=${QS_BIN:-/usr/bin/qs}
if [[ ! -x $QS_BIN ]]; then
    echo "  skip: Quickshell not installed; the widget's file watches were not run" >&2
else
    sandbox bar-engine
    runtime="$(mktemp -d "${TMPDIR:-/tmp}/haseen-ws.XXXXXX")"
    chmod 700 "$runtime"
    state="$XDG_STATE_HOME/haseen"
    mkdir -p "$state/toggles/hypr"
    printf '%s\n' 'haseen.workspaces.enable()' >"$state/toggles/hypr/monitor-workspaces.lua"
    printf '0\teDP-1\tPanel\n2\tDP-3\tXENEON\n' >"$state/monitor-workspaces"
    harness="$SANDBOX/shell"
    mkdir -p "$harness"
    for module in Haseen Compat Ui Commons; do
        ln -s "$HASEEN_PATH/shell/$module" "$harness/$module"
    done
    ln -s "$HASEEN_PATH/shell/plugins" "$harness/plugins"
    cat >"$harness/shell.qml" <<'QML'
import QtQuick
import Quickshell
ShellRoot {
    id: probe
    property int phase: 0
    property var result: ({})
    readonly property string toggle: Quickshell.env("XDG_STATE_HOME") + "/haseen/toggles/hypr/monitor-workspaces.lua"
    Loader {
        id: loader
        source: Quickshell.shellDir + "/plugins/haseen.workspaces/Widget.qml"
    }
    // The harness's own clock, not the widget's: the widget has no Timer.
    Timer {
        interval: 20
        repeat: true
        running: true
        onTriggered: {
            const w = loader.item;
            if (!w)
                return;
            if (probe.phase === 0 && w.perMonitor && w.blocks["DP-3"] === 2) {
                probe.result.on = { blocks: w.blocks };
                Quickshell.execDetached(["rm", "-f", probe.toggle]);
                probe.phase = 1;
            } else if (probe.phase === 1 && !w.perMonitor) {
                probe.result.off = true;
                Quickshell.execDetached(["sh", "-c", "echo 'haseen.workspaces.enable()' >\"$1\"", "sh", probe.toggle]);
                probe.phase = 2;
            } else if (probe.phase === 2 && w.perMonitor) {
                probe.result.again = true;
                console.log("RESULT " + JSON.stringify(probe.result));
                Qt.quit();
            }
        }
    }
}
QML
    capture env -u DISPLAY -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DBUS_SESSION_BUS_ADDRESS \
        XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME='' QT_QUICK_BACKEND=software \
        QT_NO_XDG_DESKTOP_PORTAL=1 timeout 60 dbus-run-session --config-file="$REPO/tools/smoke-session.conf" -- "$QS_BIN" -p "$harness"
    rm -rf "$runtime"
    assert_status "the widget runs in the real engine" 0 "$STATUS"
    result="$(sed -n 's/^.*RESULT //p' <<<"$OUTPUT")"
    assert_eq "it reads the toggle and the blocks, then follows the toggle off and on" \
        '{"on":{"blocks":{"eDP-1":0,"DP-3":2}},"off":true,"again":true}' "$result"
fi
