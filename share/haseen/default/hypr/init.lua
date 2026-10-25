-- haseen Hyprland defaults: the entry point the user's ~/.config/hypr/hyprland.lua
-- dofile()s. Never edited by users; overrides go in ~/.config/hypr/*.lua.
--
-- Load order (each later step may override the earlier ones):
--   1. defaults: this file and its siblings (input, looknfeel, binds, …)
--   2. toggles:  $XDG_STATE_HOME/haseen/toggles/hypr/*.lua       (runtime)
--   3. hyprmod:  ~/.config/hypr/hyprland-gui.lua                 (GUI app)
--   4. theme:    ~/.local/state/haseen/current/theme/hyprland.lua (user file;
--                it yields to the toggles and hyprmod, see haseen.theme_hl)
--   5. user:     ~/.config/hypr/{monitors,bindings,local}.lua    (user file)
--
-- Modules are run with dofile(), not require(): Hyprland keeps one Lua VM
-- across config reloads, so require() would serve cached modules and a reload
-- would silently skip them.
--
-- Defines the global table `haseen` for the user's files:
--   haseen.path                       share/haseen root
--   haseen.paths.{home,config_home,state_home}
--   haseen.include_optional(path)     dofile PATH if it exists; errors are printed, not fatal
--   haseen.bind(keys, description, dispatcher_or_command, options)
--   haseen.ipc(target, fn, ...)        command string for `haseen shell ipc …`
--   haseen.launch(command)            command string run as a uwsm app unit
--   haseen.bind_expressions           function -> the Lua expression `hyprctl dispatch`
--                                     replays it with (the keybind sheet reads it)
--   haseen.workspaces                 per-monitor workspaces (monitor-workspaces.lua)
--   haseen.workspace_mode(spec)       a workspace's layout or floating mode
--                                     (workspace-modes.lua)
--   haseen.console                    the SUPER + GRAVE console (qconsole.lua)
--   haseen.transparent_window(match, opacity)  Omarchy's window transparency
--                                     (windowrules.lua)
--   haseen.animations                 leaf -> the last hl.animation spec the config
--                                     gave it; haseen.set_animation sets one
--                                     without recording it
--   haseen.held                       "section.key" and "animation:<leaf>" ->
--                                     true for what a toggle or hyprmod set
--
-- The helper shape (bind/launch/window over hl.*) is adapted from Omarchy
-- default/hypr/helpers.lua. Omarchy is MIT licensed, Copyright (c) David
-- Heinemeier Hansson.

local function env_or(name, fallback)
  local value = os.getenv(name)
  if value == nil or value == "" then
    return fallback
  end
  return value
end

-- share/haseen is two directories above this file. Taking it from our own
-- location works for the repo checkout, /usr/local and /usr
-- alike; HASEEN_PATH (exported by ~/.config/uwsm/env.d/10-haseen) is only the
-- fallback for a VM without the debug library.
local function own_root()
  -- Level 1 is this function, defined in init.lua. (Not through pcall: that
  -- would make level 1 pcall itself.)
  local info = type(debug) == "table" and debug.getinfo and debug.getinfo(1, "S")
  if info and type(info.source) == "string" then
    local root = info.source:match("^@(.*)/default/hypr/init%.lua$")
    if root then
      return root
    end
  end
  return nil
end

local home = os.getenv("HOME") or ""

haseen = haseen or {}
haseen.path = own_root() or env_or("HASEEN_PATH", "/usr/local/share/haseen")
haseen.paths = {
  home = home,
  config_home = env_or("XDG_CONFIG_HOME", home .. "/.config"),
  state_home = env_or("XDG_STATE_HOME", home .. "/.local/state"),
}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end
haseen.shell_quote = shell_quote

-- A broken theme or user file must not take the rest of the config with it:
-- the error is caught, logged, and shown as a Hyprland notification, and the
-- files after it still load.
function haseen.include_optional(path)
  local file = io.open(path, "r")
  if not file then
    return false
  end
  file:close()
  local ok, err = pcall(dofile, path)
  if not ok then
    local message = "haseen: " .. path .. " failed to load: " .. tostring(err)
    print(message)
    if type(hl.notification) == "table" and hl.notification.create then
      pcall(hl.notification.create, { text = message, timeout = 15000, color = "rgb(f7768e)" })
    end
  end
  return ok
end

-- Apps run as their own systemd scope through uwsm, so a crash or an OOM kill
-- takes the app, not the compositor's process tree.
function haseen.launch(command)
  return "uwsm-app -- " .. command
end

-- `haseen shell ipc` routes to the haseen shell or, when DMS is the active
-- shell, translates the call (docs/architecture.md §5.5).
function haseen.ipc(target, fn, ...)
  local parts = { "haseen", "shell", "ipc", target, fn }
  for _, arg in ipairs({ ... }) do
    table.insert(parts, shell_quote(arg))
  end
  return table.concat(parts, " ")
end

-- A bind whose action is a Lua function records here how `hyprctl dispatch`
-- can run the same thing, so the keybind sheet can replay it. Weak keys: an
-- entry goes with the function when a reload drops the bind.
haseen.bind_expressions = setmetatable({}, { __mode = "k" })

-- Hyprland has no getter for an animation leaf, and the console (qconsole.lua)
-- borrows the special-workspace leaves while it shows and must hand back what
-- the config set: remember the last spec per leaf, from here to the user's
-- files. A reload resets Hyprland's tree, so the record starts empty on every
-- load; the wrapper goes on once per Lua state, so a state kept across reloads
-- is not wrapped twice. A spec without a leaf, or without a speed and a curve
-- while enabled, is not remembered: Hyprland refuses those, reports it and
-- returns normally. That is a check of the spec's shape only: Hyprland may
-- still reject a spec the recorder stored (an unknown leaf, bezier or style),
-- so the record is what the config asked for, not what Hyprland applied.
haseen.animations = {}
if not haseen.set_animation then
  haseen.set_animation = hl.animation
  hl.animation = function(spec)
    haseen.set_animation(spec)
    if type(spec) ~= "table" or type(spec.leaf) ~= "string" then
      return
    end
    if spec.enabled ~= false and not ((tonumber(spec.speed) or 0) > 0 and (spec.bezier or spec.spring)) then
      return
    end
    local copy = {}
    for key, value in pairs(spec) do
      copy[key] = value
    end
    haseen.animations[spec.leaf] = copy
  end
end

function haseen.bind(keys, description, dispatcher, options)
  local opts = options or {}
  if description then
    opts.description = description
  end
  if type(dispatcher) == "string" then
    dispatcher = hl.dsp.exec_cmd(dispatcher)
  end
  return hl.bind(keys, dispatcher, opts)
end

-- haseen.rebind: the same, but it replaces whatever `keys` already does.
-- Hyprland stacks binds, so a user bind on a key haseen also binds would run
-- both actions (a close-window key closing two windows). Unbinding a key that
-- is not bound is harmless.
function haseen.rebind(keys, description, dispatcher, options)
  hl.unbind(keys)
  return haseen.bind(keys, description, dispatcher, options)
end

-- A setting a toggle or hyprmod made, by its path in hl.config's tables
-- ("decoration.rounding") or its animation leaf ("animation:border"). A
-- gradient ({ colors = …, angle = … }) and a list ({ 875, 600 }) are one
-- value, not a section. The record starts empty on every load.
haseen.held = {}

local function is_value(v)
  return type(v) ~= "table" or v.colors ~= nil or v[1] ~= nil
end

local function hold_keys(t, prefix)
  if type(t) ~= "table" then
    return
  end
  for k, v in pairs(t) do
    local key = prefix .. tostring(k)
    if is_value(v) then
      haseen.held[key] = true
    else
      hold_keys(v, key .. ".")
    end
  end
end

-- include_held(path) — haseen.include_optional, recording what the file sets
-- in haseen.held.
local function include_held(path)
  local config, animation = hl.config, hl.animation
  hl.config = function(t, ...)
    hold_keys(t, "")
    return config(t, ...)
  end
  hl.animation = function(spec, ...)
    if type(spec) == "table" and type(spec.leaf) == "string" then
      haseen.held["animation:" .. spec.leaf] = true
    end
    return animation(spec, ...)
  end
  local ok = haseen.include_optional(path)
  hl.config, hl.animation = config, animation
  return ok
end

-- haseen.theme_hl(hl) — the `hl` the current theme's hyprland.lua sees
-- (haseen theme set prefixes it with `local hl = haseen.theme_hl(hl)`). The
-- theme owns the window look, as an Omarchy theme does, its corners included
-- (decoration.rounding, plan 114), but it loads after the toggles and
-- hyprmod: a key or animation leaf either of them set is dropped from the
-- theme's calls, so `haseen toggle gaps` and the GUI still win over it. The
-- user's own files load after the theme and win over all three.
function haseen.theme_hl(real)
  local function without_held(t, prefix)
    local copy, kept = {}, false
    for k, v in pairs(t) do
      local key = prefix .. tostring(k)
      if not haseen.held[key] then
        if is_value(v) then
          copy[k], kept = v, true
        else
          local sub = without_held(v, key .. ".")
          if sub then
            copy[k], kept = sub, true
          end
        end
      end
    end
    return kept and copy or nil
  end
  return setmetatable({
    config = function(t, ...)
      if type(t) ~= "table" then
        return real.config(t, ...)
      end
      local kept = without_held(t, "")
      if kept then
        return real.config(kept, ...)
      end
    end,
    animation = function(spec, ...)
      if type(spec) == "table" and type(spec.leaf) == "string" and haseen.held["animation:" .. spec.leaf] then
        return
      end
      return real.animation(spec, ...)
    end,
  }, { __index = real })
end

-- monitor-workspaces, workspace-modes and qconsole define what binds.lua and
-- the toggles below call; qconsole follows looknfeel, whose curves it uses.
local here = haseen.path .. "/default/hypr/"
for _, module in ipairs({ "input", "looknfeel", "monitor-workspaces", "workspace-modes", "qconsole", "binds", "windowrules", "autostart" }) do
  dofile(here .. module .. ".lua")
end

-- Toggles that `haseen toggle …` / `haseen hardware …` persist (gaps,
-- animations, workspace layout, displays, touchpad). They load after the
-- defaults so they win, and before the user's files so those still win.
local toggles = haseen.paths.state_home .. "/haseen/toggles/hypr"
local listing = io.popen('ls -1 "' .. toggles .. '"/*.lua 2>/dev/null')
if listing then
  for file in listing:lines() do
    include_held(file)
  end
  listing:close()
end

-- hyprmod (AUR, GPL-3.0) is the optional GTK4 settings app for Hyprland. It
-- writes only this one file and never touches haseen's. It loads last of
-- haseen's includes, so the GUI wins: every monitor, workspace, animation,
-- env, exec, windowrule and layerrule key hyprmod holds overrides what
-- `haseen toggle …` and `haseen hw …` wrote just above, and over the theme's
-- (haseen.theme_hl). Turn a setting off in hyprmod (or uninstall it and delete
-- the file) to get haseen's value back. The user's own ~/.config/hypr/*.lua
-- files still load after this one.
include_held(haseen.paths.config_home .. "/hypr/hyprland-gui.lua")

-- Every saved workspace mode has loaded with the toggles: bring the windows in
-- line with them (workspace-modes.lua). It reads live windows, so a failure is
-- printed and never takes the rest of the config with it.
local applied, apply_error = pcall(haseen.workspace_modes.apply)
if not applied then
  print("haseen: workspace modes: " .. tostring(apply_error))
end
