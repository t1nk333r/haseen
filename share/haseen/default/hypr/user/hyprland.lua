-- ~/.config/hypr/hyprland.lua — your Hyprland config.
-- Seeded once by `haseen layer apply desktop`; haseen never rewrites it.
-- Learn the Lua API: https://wiki.hypr.land/Configuring/Start/
--
-- haseen's defaults live in $HASEEN_PATH/default/hypr/ and improve with
-- updates. Override them below or in the optional files loaded at the end;
-- to replace a default bind, hl.unbind() its key first (see binds.lua there).

-- Where haseen is installed. ~/.config/uwsm/env.d/10-haseen exports
-- HASEEN_PATH for the session; the list covers a start without uwsm.
local haseen_path = os.getenv("HASEEN_PATH")
if haseen_path == nil or haseen_path == "" then
  for _, candidate in ipairs({ "/usr/local/share/haseen", "/usr/share/haseen" }) do
    local file = io.open(candidate .. "/default/hypr/init.lua", "r")
    if file then
      file:close()
      haseen_path = candidate
      break
    end
  end
end
if haseen_path == nil or haseen_path == "" then
  error("haseen not found: HASEEN_PATH is unset and neither /usr/local/share/haseen nor /usr/share/haseen exists. Run 'haseen layer apply desktop' (it writes ~/.config/uwsm/env.d/10-haseen).")
end

-- haseen defaults (input, look and feel, binds, window rules, autostart).
dofile(haseen_path .. "/default/hypr/init.lua")

-- The current theme's border colours, written by `haseen theme set`.
haseen.include_optional(haseen.paths.state_home .. "/haseen/current/theme/hyprland.lua")

-- Your own files; each is optional. Create them as you need them:
--   monitors.lua  hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "0x0", scale = 1 })
--   bindings.lua  hl.unbind("SUPER + B")  haseen.bind("SUPER + B", "Browser", "uwsm-app -- firefox")
--   local.lua     anything else
haseen.include_optional(haseen.paths.config_home .. "/hypr/monitors.lua")
haseen.include_optional(haseen.paths.config_home .. "/hypr/bindings.lua")
haseen.include_optional(haseen.paths.config_home .. "/hypr/local.lua")
