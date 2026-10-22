-- Workspace modes for `haseen toggle workspace-layout` (plan 105): dwindle,
-- scrolling, and floating, where every window on the workspace floats.
--
-- Hyprland has dwindle and scrolling as tiled layouts, but nothing that floats
-- a whole workspace: it reports a workspace's `tiledLayout` and takes an
-- unknown layout name in silence, falling back to dwindle. So floating is
-- applied to the windows themselves, through the same float dispatcher
-- SUPER + T uses.
--
-- Ending the mode has to tile the windows the mode floated and only those, so
-- each one is tagged. The tag lives on the window: it dies with it, follows it
-- between workspaces, and survives the config reload that a monitor being
-- plugged in performs, none of which a table on this side would do.
--
-- A saved mode is a file in $XDG_STATE_HOME/haseen/toggles/hypr/ that calls
-- haseen.workspace_mode({ workspace = "3", mode = "floating" }); init.lua
-- loads those files, then calls haseen.workspace_modes.apply(). Nothing here
-- subscribes to an event until a workspace floats, or a window the mode
-- floated is still around.
--
-- Adapted from Omarchy default/hypr/workspace-modes.lua at 149871896 (#14482,
-- "Add a floating mode with titlebars to the workspace layout cycle"; MIT,
-- Copyright (c) David Heinemeier Hansson). Left out: the titlebars (a compiled
-- Hyprland plugin), the shadows and opacity a floating workspace turned on,
-- and the dock added later (124328fd8), none of which haseen has; and the
-- user-chosen default mode, since haseen keeps Hyprland's general.layout as
-- the default (plan 102). Changed: focus-follows-mouse is read when a floating
-- workspace comes into view, not when the first mode loads, so a value the
-- user's own files set after haseen's is the one given back.

local FLOATED_TAG = "haseen-mode-floated"

local M = {}

local modes = {}
local watching = false
local cascade = 0

-- Hyprland's lists are plain tables; a stub's may be anything.
local function list(value)
  return type(value) == "table" and value or {}
end

local function set_floating(window, floating)
  hl.dispatch(hl.dsp.window.float({ action = floating and "on" or "off", window = window }))
end

local function set_claimed(window, claimed)
  hl.dispatch(hl.dsp.window.tag({ tag = (claimed and "+" or "-") .. FLOATED_TAG, window = window }))
end

local function claimed()
  local addresses = {}

  for _, window in ipairs(list(hl.get_windows({ tag = FLOATED_TAG }))) do
    addresses[window.address] = true
  end

  return addresses
end

-- Special workspaces, such as the scratchpad and the console, and named ones,
-- which report a negative id, keep whatever state a window arrived with.
local function floating_workspace(id)
  id = tonumber(id)

  if not id or id < 1 then
    return false
  end

  return modes[tostring(id)] == "floating"
end

local function anything_floats()
  for _, mode in pairs(modes) do
    if mode == "floating" then
      return true
    end
  end

  return false
end

-- A window the mode floats opens at a comfortable size in the middle of its
-- monitor, each one stepped from the last so a workspace floated all at once does
-- not leave every window stacked exactly on the one beneath it.
local function place(window)
  local monitor = window.monitor
  if not monitor or not monitor.width or not monitor.scale or monitor.scale <= 0 then
    return
  end

  local width = math.floor(monitor.width / monitor.scale)
  local height = math.floor(monitor.height / monitor.scale)

  if (monitor.transform or 0) % 2 == 1 then
    width, height = height, width
  end

  local reserved = monitor.reserved or {}
  width = width - (reserved.left or 0) - (reserved.right or 0)
  height = height - (reserved.top or 0) - (reserved.bottom or 0)

  hl.dispatch(hl.dsp.window.resize({
    x = math.min(1100, math.floor(width * 0.64)),
    y = math.min(760, math.floor(height * 0.68)),
    relative = false,
    window = window,
  }))
  hl.dispatch(hl.dsp.window.center({ window = window }))

  cascade = (cascade + 1) % 5
  hl.dispatch(hl.dsp.window.move({ x = cascade * 24 - 48, y = cascade * 24 - 48, relative = true, window = window }))
end

-- A window already floating on its own account -- an app with a float rule of
-- its own, a dialog, one popped out with SUPER + T -- is left unclaimed, so it
-- is still floating when the mode ends. A fullscreen window is left as it is.
--
-- Every tiled window is claimed before any of them is floated: floating one
-- member of a group floats the rest, and a single pass would then find those
-- already floating and leave them to be stranded when the mode ends.
local function float_for_mode(windows)
  local claiming = {}

  for _, window in ipairs(windows) do
    if not window.floating and (window.fullscreen or 0) == 0 then
      set_claimed(window, true)
      table.insert(claiming, window)
    end
  end

  for _, window in ipairs(claiming) do
    set_floating(window, true)
    place(window)
  end
end

-- A pinned window is one the user asked to keep above everything, and tiling it
-- would unpin it as well, so the mode leaves it be.
local function tile_for_mode(window, mine)
  if not mine[window.address] or window.pinned then
    return
  end

  set_claimed(window, false)
  set_floating(window, false)
end

-- The workspace is passed in when a window is still on its way to it.
local function arrange(windows, workspace)
  local floating = {}
  local mine = claimed()

  for _, window in ipairs(list(windows)) do
    local id = tonumber(workspace and workspace.id or (window.workspace and window.workspace.id))

    if id and id >= 1 then
      if floating_workspace(id) then
        table.insert(floating, window)
      else
        tile_for_mode(window, mine)
      end
    end
  end

  float_for_mode(floating)
end

-- Overlapping windows are placed with the pointer, so a floating workspace
-- focuses on click rather than on hover. Every other workspace keeps the
-- user's own setting, read as the floating one comes into view.
local input = { floating = false, follow_mouse = nil }

local function update_input()
  local workspace = hl.get_active_workspace()
  local active = workspace ~= nil and floating_workspace(workspace.id)

  if active == input.floating then
    return
  end
  input.floating = active

  if active then
    local value = hl.get_config("input.follow_mouse")
    input.follow_mouse = type(value) == "number" and value or nil
    hl.config({ input = { follow_mouse = 0 } })
  elseif input.follow_mouse ~= nil then
    hl.config({ input = { follow_mouse = input.follow_mouse } })
    input.follow_mouse = nil
  end
end

-- Windows arrive by opening and by being carried in, and a window rule only ever
-- fires for the first. One carried back out gives up the floating the mode gave
-- it rather than staying floating somewhere that tiles.
local function watch()
  if watching then
    return
  end

  watching = true

  hl.on("window.open", function(window)
    arrange({ window })
  end)

  -- A move is still being committed when this fires, and changing the window's
  -- floating state underneath it loses the move. Let it land first.
  hl.on("window.move_to_workspace", function(window, workspace)
    hl.timer(function()
      arrange({ window }, workspace)
    end, { type = "oneshot", timeout = 1 })
  end)

  -- A fullscreen window is left as it is, so it is arranged once it comes back
  -- out: a tiled one leaving fullscreen on a floating workspace floats then.
  hl.on("window.fullscreen", function(window)
    hl.timer(function()
      arrange({ window })
    end, { type = "oneshot", timeout = 1 })
  end)

  hl.on("workspace.active", update_input)
  hl.on("monitor.focused", update_input)
end

-- The mode a workspace was given in this config load: "floating" from a saved
-- mode, else nil (Hyprland's tiledLayout tells dwindle from scrolling).
function M.mode(workspace)
  return modes[tostring(workspace)]
end

-- haseen.workspace_mode({ workspace = "3", mode = "dwindle"|"scrolling"|"floating" })
function haseen.workspace_mode(spec)
  local workspace = tostring(spec.workspace)
  local mode = spec.mode

  -- Hyprland reads a leading "-" as a selector relative to the current
  -- workspace, so a named workspace's negative id would reach workspace 1.
  local id = tonumber(workspace)
  if not id or id < 1 or math.floor(id) ~= id then
    error("haseen.workspace_mode: workspace must be a positive id, not " .. workspace)
  end
  if mode ~= "dwindle" and mode ~= "scrolling" and mode ~= "floating" then
    error("haseen.workspace_mode: mode must be dwindle, scrolling or floating, not " .. tostring(mode))
  end

  -- Floating keeps whatever tiled layout the workspace had, so nothing has to be
  -- chosen for it on the way back out.
  if mode ~= "floating" then
    hl.workspace_rule({ workspace = workspace, layout = mode })
  end

  modes[workspace] = mode

  -- The watchers are only needed while something floats or something the mode
  -- floated has yet to be tiled again.
  if mode == "floating" or next(claimed()) ~= nil then
    watch()
  end

  arrange(hl.get_workspace_windows(workspace))
  if watching then
    update_input()
  end
end

-- Runs once every saved mode has loaded. A reload is a fresh start on this side
-- but not for the windows, so each one is brought in line with the modes as they
-- now stand: a workspace whose saved mode went away has to give back what the
-- mode floated, even though nothing names it any more.
function M.apply()
  if anything_floats() or #list(hl.get_windows({ tag = FLOATED_TAG })) > 0 then
    watch()
  end

  if watching then
    arrange(hl.get_windows())
    update_input()
  end
end

haseen.workspace_modes = M

return M
