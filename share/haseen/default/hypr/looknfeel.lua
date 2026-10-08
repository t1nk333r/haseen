-- haseen look and feel: no blur, no shadows, small gaps, few and fast
-- animations. Border colours here are the fallback; the theme file
-- (~/.local/state/haseen/current/theme/hyprland.lua) replaces them.

local active_border = "rgb(7aa2f7)"
local inactive_border = "rgba(595959aa)"

hl.config({
  general = {
    gaps_in = 2,
    gaps_out = 4,
    border_size = 2,
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
    resize_on_border = false,
    allow_tearing = false,
    layout = "dwindle",
  },

  decoration = {
    -- Twice the default radius token, the frame's inner radius: the rendered
    -- theme replaces it with the shared window radius (plan 046).
    rounding = 12,
    shadow = { enabled = false },
    blur = { enabled = false },
  },

  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
    groupbar = {
      font_size = 11,
      height = 18,
      gradients = false,
      render_titles = true,
    },
  },

  animations = {
    enabled = true,
  },

  dwindle = {
    preserve_split = true,
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    focus_on_activate = true,
    -- A crashed lock client must not leave the session wide open or stuck:
    -- let the restarted shell take the lock back.
    allow_session_lock_restore = true,
  },

  cursor = {
    hide_on_key_press = true,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },

  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})

-- Animations: short and linear-ish. Windows pop in, everything else fades;
-- workspace switches are instant.
hl.curve("haseenOut", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.animation({ leaf = "global", enabled = true, speed = 4, bezier = "haseenOut" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 2.5, bezier = "haseenOut", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "haseenOut", style = "popin 90%" })
hl.animation({ leaf = "border", enabled = false })
hl.animation({ leaf = "workspaces", enabled = false })
hl.animation({ leaf = "layers", enabled = true, speed = 2, bezier = "haseenOut", style = "fade" })
