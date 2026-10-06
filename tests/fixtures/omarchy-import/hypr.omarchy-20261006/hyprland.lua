dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")
require("default.hypr.omarchy")

-- t1nk33r.workspace-layout: load generated layouts, if present.
do
  local path = (os.getenv("XDG_STATE_HOME") or (os.getenv("HOME") .. "/.local/state"))
    .. "/omarchy/t1nk33r.workspace-layout/layouts.lua"
  local file = io.open(path, "r")
  if file then
    file:close()
    local loaded, why = pcall(dofile, path)
    if not loaded then
      print("t1nk33r.workspace-layout: generated layouts failed to load: " .. tostring(why))
    end
  end
end

-- Add any other personal Hyprland configuration below.
-- o.window("qemu", { workspace = "5" })

-- omagesture:begin (managed by io.github.heroesofcode.omagesture — do not edit)
pcall(require, "hypr.omagesture")
-- omagesture:end
