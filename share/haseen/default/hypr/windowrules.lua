-- haseen window rules, in the native table form hl.window_rule({ name, match, effects }).
-- Match strings are RE2 regexes matched against the WHOLE value: an
-- unanchored "foo" does not match "org.foo.App"; write ".*foo.*".

-- Apps asking to be maximised would otherwise fight the tiling layout.
hl.window_rule({
  name = "haseen_suppress_maximize",
  match = { class = ".*" },
  suppress_event = "maximize",
})

-- Untitled, unclassed XWayland floats are drag-and-drop helper surfaces;
-- focusing them breaks drags out of X11 apps.
hl.window_rule({
  name = "haseen_xwayland_drag",
  match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
  no_focus = true,
})

-- Dialogs: portal file pickers and permission prompts, and the polkit agent
-- when one runs as a window.
hl.window_rule({
  name = "haseen_float_dialogs",
  match = { class = "^(xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland|org\\.freedesktop\\.impl\\.portal\\..*|polkit-gnome-authentication-agent-1)$" },
  float = true,
  center = true,
})

-- Picture-in-picture video stays visible on every workspace.
hl.window_rule({
  name = "haseen_pip",
  match = { title = "^(Picture.?in.?[Pp]icture)$" },
  float = true,
  pin = true,
  keep_aspect_ratio = true,
})

-- Fullscreen apps (games, video) keep the screen awake.
hl.window_rule({
  name = "haseen_fullscreen_idle",
  match = { class = ".*" },
  idle_inhibit = "fullscreen",
})

-- The screensaver's terminals: fullscreen on a silent special workspace and
-- never inhibiting idle, so lock and DPMS still fire behind it. This rule must
-- follow haseen_fullscreen_idle, which it overrides.
hl.window_rule({
  name = "haseen_screensaver",
  match = { class = "^org\\.haseen\\.screensaver$" },
  float = true,
  fullscreen = true,
  idle_inhibit = "none",
  workspace = "special:screensaver silent",
})

-- Terminals opened by haseen commands (pickers, setup steps, editors).
hl.window_rule({
  name = "haseen_floating_terminal",
  match = { class = "^haseen\\.floating$" },
  float = true,
  center = true,
  size = { 875, 600 },
})

-- Webcam overlay while screen recording: a small pinned corner window.
hl.window_rule({
  name = "haseen_webcam_overlay",
  match = { class = "^haseen-webcam$" },
  float = true,
  pin = true,
  no_initial_focus = true,
  move = { "monitor_w-window_w-24", "monitor_h-window_h-24" },
})

-- slurp's region selection: no fade, so the frozen frame is what gets captured.
hl.layer_rule({
  name = "haseen_slurp_selection",
  match = { namespace = "selection" },
  no_anim = true,
})
