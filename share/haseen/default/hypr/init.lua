-- haseen Hyprland defaults: the entry point the user's ~/.config/hypr/hyprland.lua
-- dofile()s. Never edited by users; overrides go in ~/.config/hypr/*.lua.
--
-- Load order (each later step may override the earlier ones):
--   1. this file and its siblings (input, looknfeel, binds, windowrules, autostart)
--   2. the theme:  ~/.local/state/haseen/current/theme/hyprland.lua  (user file)
--   3. the user:   ~/.config/hypr/{monitors,bindings,local}.lua      (user file)
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
-- location works for the repo checkout, /usr/local, /usr and a Nix store path
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

local here = haseen.path .. "/default/hypr/"
for _, module in ipairs({ "input", "looknfeel", "binds", "windowrules", "autostart" }) do
  dofile(here .. module .. ".lua")
end

-- Toggles that `haseen toggle …` / `haseen hardware …` persist (gaps,
-- animations, workspace layout, displays, touchpad). They load after the
-- defaults so they win, and before the user's files so those still win.
local toggles = haseen.paths.state_home .. "/haseen/toggles/hypr"
local listing = io.popen('ls -1 "' .. toggles .. '"/*.lua 2>/dev/null')
if listing then
  for file in listing:lines() do
    haseen.include_optional(file)
  end
  listing:close()
end
