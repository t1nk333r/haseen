-- The console (plan 105): a terminal on its own special workspace that drops
-- down over whatever workspace you are on, SUPER + GRAVE (binds.lua, through
-- haseen.console.toggle). The workspace exists only once it is first opened,
-- and its terminal is started then, so nothing runs until the console is
-- wanted.
--
-- Adapted from Omarchy default/hypr/qconsole.lua (#7409, #7420, #9140, and
-- d377569ed; MIT, Copyright (c) David Heinemeier Hansson). Changes: a special
-- workspace of its own, so SUPER + S's scratchpad keeps the whole screen; the
-- first open starts $TERMINAL, not an AI agent; a monitor that cannot be read
-- yet (a stub, or one going away) is skipped rather than raised; the dim and
-- the slide are the console's only (owner, 2026-10-22: "Console only"), where
-- Omarchy sets them for every special workspace.

local CONSOLE = "special:console"

-- How much of the usable screen the console covers, measured from the top.
local share = 0.5

-- A console holding a single window is boxed into a centered panel this many
-- times wider than it is tall, rather than stretched the width of the screen.
-- A second app on the console gets the full width back: two windows splitting
-- a half-width column is worse than the band this replaced.
local box = 2

-- The terminal the first open starts, as SUPER + RETURN starts one. The exec
-- rule pins the workspace itself, so the window lands in the console whatever
-- Hyprland's initial workspace tracking says.
local seed = "[workspace " .. CONSOLE .. " silent] " .. haseen.launch('"${TERMINAL:-foot}"')

-- Hyprland's lists are plain tables; a stub's may be anything.
local function list(value)
  return type(value) == "table" and value or {}
end

-- How much the workspace underneath is dimmed while the console shows, and how
-- the console drops down and retracts. "slide top" names the edge the offset
-- is measured from, not where the workspace goes: it drops into view, and
-- "slide bottom" retracts it back up the way a Quake console does. The
-- slides are Omarchy's (default/hypr/qconsole.lua@v4.5.0-rc1:195-196), on
-- the curves looknfeel.lua defines.
local DIM = 0.6
local IN, OUT = "specialWorkspaceIn", "specialWorkspaceOut"
local SLIDE = {
  [IN] = { leaf = IN, enabled = true, speed = 3, bezier = "easeOutQuint", style = "slide top" },
  [OUT] = { leaf = OUT, enabled = true, speed = 2, bezier = "easeInOutCubic", style = "slide bottom" },
}

-- The panel is always flush with the top and always centered, so two numbers
-- describe it: the gap down each side and the gap underneath.
--
-- Refitting replaces the rule in place rather than stacking a new one, but it
-- still schedules a monitor and window state refresh, and monitor.focused fires
-- on every hop between screens. Most of those hops do not change the gaps, so
-- only write the rule when it actually moves.
local beside, below = nil, nil

local function cover(side, bottom)
  if beside == side and below == bottom then
    return false
  end
  beside, below = side, bottom

  hl.workspace_rule({
    workspace = CONSOLE,
    gaps_in = 0,
    gaps_out = { top = 0, right = side, bottom = bottom, left = side },

    -- Nothing to highlight in a console that is only ever focused when it is
    -- open, and the active border reads as a stray frame around a panel that
    -- is already set apart by the dimming behind it.
    no_border = true,

    on_created_empty = seed,
  })

  return true
end

-- One window reads as a console and gets the panel. A second app has turned the
-- console into a workspace, and a workspace wants the whole width. Only tiled
-- windows count: the gaps are what size the panel, and a floating window on top
-- of the console is not laid out by them.
local function alone()
  local tiled = 0
  for _, window in ipairs(list(hl.get_workspace_windows(CONSOLE))) do
    if not window.floating then
      tiled = tiled + 1
    end
  end
  return tiled <= 1
end

-- Sizing the console with a window rule would freeze it at whatever the screen
-- measured when it first opened, because Hyprland resolves those expressions
-- once, as the window maps. Rescaling the monitor afterwards would leave a
-- console that is no longer half of anything. Gaps are re-applied by the layout
-- instead, so the console is sized by the area left around it, and that area is
-- recomputed whenever the monitor it opens on changes.
local function fit(monitor)
  -- A monitor handle whose output has gone away answers nil to every field, and
  -- layout changes are exactly when that happens, so this also covers reading
  -- width, height and reserved below.
  if not monitor or type(monitor.scale) ~= "number" or monitor.scale <= 0 then
    return false
  end

  -- Width and height are the panel's own pixels, so a monitor turned on its
  -- side still reports them the way the panel is built. The odd transforms are
  -- the quarter turns, and those are the ones that swap the work area.
  local width, height = monitor.width, monitor.height
  if (monitor.transform or 0) % 2 == 1 then
    width, height = height, width
  end

  -- Monitor dimensions are in physical pixels; gaps are logical, so the scale
  -- has to come out before the reserved area (already logical) comes off.
  local reserved = monitor.reserved or {}
  height = height / monitor.scale - (reserved.top or 0) - (reserved.bottom or 0)
  width = width / monitor.scale - (reserved.left or 0) - (reserved.right or 0)

  local tall = math.floor(height * share)
  local wide = width
  if alone() then
    wide = math.min(width, tall * box)
  end

  return cover(math.floor((width - wide) / 2), math.floor(height - tall))
end

-- The console keeps the geometry of the output it is open on: a follow_mouse hop
-- onto another screen must not resize a console that is already showing. While
-- it is hidden there is nothing to size but the output that will show it next.
local function console_monitor()
  local ws = hl.get_workspace(CONSOLE)
  local mon = ws and ws.visible and ws.monitor

  if mon and type(mon.scale) == "number" and mon.scale > 0 then
    return mon
  end

  return hl.get_active_monitor()
end

local function refit(monitor)
  if fit(monitor or console_monitor()) then
    -- Land the new gaps in this pass rather than a frame later, so the console
    -- does not visibly resize itself once it has already dropped down.
    hl.exec_scheduled_prop_refresh_immediately()
  end
end

-- Until a monitor can be read, cover the whole work area rather than leaving
-- the console unruled, so it is never seeded without its placement. A reload
-- runs this again with the console already on screen, so it starts from the
-- output the console is on rather than whichever one the pointer is over.
cover(0, 0)
pcall(function()
  fit(console_monitor())
end)

hl.on("monitor.layout_changed", function()
  refit()
end)

hl.on("monitor.focused", function()
  refit()
end)

-- The dim and the slide ---------------------------------------------------------
--
-- Hyprland has one dim (decoration.dim_special) and one pair of animation
-- leaves (specialWorkspaceIn/Out) for every special workspace: set at load,
-- the scratchpad (SUPER + S) and the screensaver's workspaces would dim and
-- slide too. The owner chose the console only (2026-10-22), so the console
-- borrows them and hands them back, read from Hyprland 0.56.2's source:
--
--   * the dim is read once, as a special workspace opens, into the monitor's
--     fade (Monitor.cpp, setSpecialWorkspaceVisualState): set just before the
--     console opens, it is the user's again as soon as it has;
--   * a slide reads its leaf when it starts (the style) and on every frame
--     until it lands (speed and on/off; hyprutils AnimatedVariable.cpp), so a
--     leaf goes back only once its animation has run, or at once when another
--     special workspace shows (it then leaves the way the user set, and the
--     console stops sliding);
--   * a reload resets every leaf and setting to the config's (ConfigManager.cpp,
--     reload), so nothing borrowed outlives one.

local set_animation = haseen.set_animation or hl.animation

-- How long a leaf's animation runs: Hyprland's speed is in tenths of a second
-- (hyprutils AnimatedVariable.cpp, getPercent), plus a few frames of slack.
local function runs_ms(spec)
  if spec.enabled == false then
    return 0
  end
  return math.floor((tonumber(spec.speed) or 0) * 100) + 50
end

-- What the config gave LEAF, as Hyprland inherits it: its own spec, else its
-- nearest ancestor's, else Hyprland's own default for global
-- (AnimationTree.cpp). init.lua records every hl.animation call.
local PARENT = { [IN] = "specialWorkspace", [OUT] = "specialWorkspace", specialWorkspace = "workspaces", workspaces = "global" }

local function configured(leaf)
  local seen = type(haseen.animations) == "table" and haseen.animations or {}
  local node = leaf
  while node and not seen[node] do
    node = PARENT[node]
  end
  local spec = {}
  for key, value in pairs(node and seen[node] or { enabled = true, speed = 8, bezier = "default" }) do
    spec[key] = value
  end
  spec.leaf = leaf
  return spec
end

-- lent[leaf]: the leaf holds the console's slide. turn[leaf] counts every
-- change, so a timer set for an earlier one does nothing.
local lent, turn = {}, {}

local function bump(leaf)
  turn[leaf] = (turn[leaf] or 0) + 1
  return turn[leaf]
end

local function borrow(leaf)
  bump(leaf)
  if not lent[leaf] then
    lent[leaf] = pcall(set_animation, SLIDE[leaf])
  end
end

local function give_back(leaf)
  bump(leaf)
  if lent[leaf] then
    lent[leaf] = nil
    pcall(set_animation, configured(leaf))
  end
end

-- Run fn(leaf) once ms have passed, unless the leaf changes first.
local function after(leaf, ms, fn)
  local mine = bump(leaf)
  if ms <= 0 then
    fn(leaf)
    return
  end
  hl.timer(function()
    if turn[leaf] == mine then
      fn(leaf)
    end
  end, { timeout = ms, type = "oneshot" })
end

local function set_dim(value)
  hl.config({ decoration = { dim_special = value } })
end

-- Whether the console shows, and whether any other special workspace does.
local function specials()
  local shown, other = false, false
  for _, monitor in ipairs(list(hl.get_monitors())) do
    local special = monitor.active_special_workspace
    if special then
      if special.name == CONSOLE then
        shown = true
      else
        other = true
      end
    end
  end
  return shown, other
end

-- Bring the leaves in line with what shows. Hyprland reports every special
-- workspace that opens or closes, however it came about (a key, focus moving
-- off it, its last window closing, a workspace switch: Monitor.cpp,
-- setSpecialWorkspace), after it has started their animations; OPENED is the
-- one that opened, if any.
local function settle(opened)
  local shown, other = specials()

  -- In is lent only for the console's own drop. Another special workspace that
  -- opened meanwhile gets it back at once, at most a frame into its slide.
  if not shown or (opened and opened.name ~= CONSOLE) then
    give_back(IN)
  end

  if other then
    -- Another special workspace shows: it closes the way the user set, and the
    -- console, if it shows too, retracts that way as well.
    give_back(OUT)
  elseif shown then
    -- The console alone: it retracts with its slide however it is closed. A
    -- special workspace it replaced may still be leaving on the user's leaf.
    if lent[OUT] then
      bump(OUT)
    else
      after(OUT, runs_ms(configured(OUT)), borrow)
    end
  elseif lent[OUT] then
    -- Nothing shows: the console is retracting on the borrowed leaf.
    after(OUT, runs_ms(SLIDE[OUT]), give_back)
  else
    -- Nothing shows and Out was never lent: the console closed while its
    -- borrow still waited on a special workspace leaving the user's way.
    -- Cancel it, or it would land with nothing showing.
    bump(OUT)
  end
end

-- Bind actions return functions for hl.dispatch, so `hyprctl dispatch
-- 'haseen.console.toggle()'` runs the same thing as the key; the keybind sheet
-- (lib/keybinds-scan.lua) reads the expression to replay it.
local function action(fn, expression)
  if type(haseen.bind_expressions) == "table" then
    haseen.bind_expressions[fn] = expression
  end
  return fn
end

local M = {}

-- Show the console on the focused monitor, or hide it there. Opened another
-- way (`hyprctl dispatch`), it shows with the user's dim and drop and still
-- retracts with its slide.
function M.toggle()
  return action(function()
    local monitor = hl.get_active_monitor()
    local open = monitor and monitor.active_special_workspace
    if open and open.name == CONSOLE then
      -- A special workspace showing elsewhere could close on the same leaf.
      local _, other = specials()
      if not other then
        borrow(OUT)
      end
      hl.dispatch(hl.dsp.workspace.toggle_special("console"))
      return
    end

    local dim = hl.get_config("decoration.dim_special")
    borrow(IN)
    if type(dim) == "number" then
      set_dim(DIM)
    end
    local ok, err = pcall(hl.dispatch, hl.dsp.workspace.toggle_special("console"))
    if type(dim) == "number" then
      set_dim(dim)
    end
    after(IN, runs_ms(SLIDE[IN]), give_back)
    if not ok then
      error(err, 0)
    end
  end, "haseen.console.toggle()")
end

-- Special workspaces open on the monitor they are toggled on, not on whichever
-- output last happened to be focused when the rule was written, so these two
-- take the monitor they are handed rather than looking one up.
hl.on("workspace.special_active", function(ws, mon)
  if ws and ws.name == CONSOLE then
    refit(mon)
  end
  settle(ws)
end)

hl.on("workspace.move_to_monitor", function(ws, mon)
  if ws and ws.name == CONSOLE then
    refit(mon)
  end
end)

-- A reload has handed every leaf back; a console still showing borrows Out
-- again, once the user's files have loaded.
hl.on("config.reloaded", function()
  settle(nil)
end)

-- The panel is only centered while the console holds one tiled window, so the
-- count has to be rechecked as apps come and go: opened and closed, moved on or
-- off (SUPER + SHIFT + GRAVE), and floated or tiled (SUPER + T).
-- window.close is left out, since it still counts the window on its way out and
-- window.destroy follows it anyway. Measured by Omarchy on Hyprland 0.56.2, a
-- move is trailed by several window.update_rules, as is a float toggle, and the
-- last of those always reads the settled count; the earlier ones refit to what
-- the rule already is, which cover() skips.
--
-- Only while it is on screen, though. A hidden console is refitted on its way in
-- by workspace.special_active, and every window opened anywhere on the desktop
-- would otherwise rewrite the rule.
local function recount()
  local ws = hl.get_workspace(CONSOLE)
  if ws and ws.visible then
    refit()
  end
end

hl.on("window.open", recount)
hl.on("window.destroy", recount)
hl.on("window.move_to_workspace", recount)
hl.on("window.update_rules", recount)

haseen.console = M
return M
