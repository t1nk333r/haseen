-- haseen input defaults. Override in ~/.config/hypr/local.lua with your own
-- hl.config({ input = { ... } }).
--
-- The vconsole layout lookup and the "Latin layout first" rule are adapted
-- from Omarchy default/hypr/input.lua. Omarchy is MIT licensed, Copyright (c)
-- David Heinemeier Hansson.

-- Keyboard layout follows the console layout chosen at install time
-- (/etc/vconsole.conf XKBLAYOUT/XKBVARIANT), so the installer's choice carries
-- over without a second prompt.
local function vconsole()
  local values = {}
  local file = io.open("/etc/vconsole.conf", "r")
  if not file then
    return values
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and value then
      values[key] = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
    end
  end
  file:close()
  return values
end

local console = vconsole()
local layout = console.XKBLAYOUT or "us"
local variant = console.XKBVARIANT or ""
local options = "compose:caps"

-- Hyprland resolves binds against the first layout. When that layout cannot
-- type Latin letters (Arabic, Persian, Cyrillic, …) put "us" first so
-- SUPER + letter binds keep working, and switch layouts with both Alts.
local latin = { us = true, gb = true, de = true, fr = true, es = true, it = true, pt = true, br = true,
  nl = true, be = true, ch = true, at = true, se = true, no = true, dk = true, fi = true, pl = true,
  cz = true, sk = true, hu = true, ro = true, tr = true, latam = true, ca = true, ie = true }
local first = layout:match("^[^,]*")
if not latin[first] then
  layout = "us," .. layout
  variant = "," .. variant
  options = options .. ",grp:alts_toggle"
end

hl.config({
  input = {
    kb_layout = layout,
    kb_variant = variant,
    kb_options = options,
    follow_mouse = 1,
    sensitivity = 0,
    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})
