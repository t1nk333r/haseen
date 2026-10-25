-- haseen window rules, in the native table form hl.window_rule({ name, match, effects }).
-- Match strings are RE2 regexes matched against the WHOLE value: an
-- unanchored "foo" does not match "org.foo.App"; write ".*foo.*".
--
-- The rules marked "Omarchy" are Omarchy 4.5's window look (plan 114):
-- default/hypr/windows.lua, apps/*.lua and helpers.lua at v4.5.0-rc1, MIT,
-- Copyright (c) David Heinemeier Hansson. Its per-app focus, fullscreen and
-- idle fixes are not taken (plans/114-windows-like-omarchy.md lists them).

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

-- Omarchy: the floating treatment (apps/system.lua:1-20): a viewer or a
-- dialog floats, centred, at 875 x 600. Portal windows are only ever dialogs.
hl.window_rule({
  name = "haseen_floating_window_tag",
  match = { class = "(org\\.gnome\\.NautilusPreviewer|org\\.gnome\\.Evince|imv|mpv|xdg-desktop-portal-gtk)" },
  tag = "+floating-window",
})
hl.window_rule({
  name = "haseen_floating_dialog_tag",
  match = {
    class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
    title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
  },
  tag = "+floating-window",
})
-- Omarchy: password managers float and stay out of screen shares
-- (apps/1password.lua, apps/bitwarden.lua).
hl.window_rule({
  name = "haseen_password_managers",
  match = { class = "^(1[pP]assword|com\\.onepassword\\.OnePassword|[bB]itwarden|chrome-nngceckbapebfimnlniiiahkandclblb-Default)$" },
  no_screen_share = true,
  tag = "+floating-window",
})
hl.window_rule({
  name = "haseen_floating_window",
  match = { tag = "floating-window" },
  float = true,
  center = true,
  size = { 875, 600 },
})

-- Omarchy: LocalSend and its fzf share picker float (apps/localsend.lua).
hl.window_rule({
  name = "haseen_share_picker",
  match = { class = "Share" },
  float = true,
  center = true,
})
hl.window_rule({
  name = "haseen_localsend",
  match = { class = "(org\\.localsend\\.)?localsend(_app)?" },
  float = true,
  center = true,
  size = { 1100, 700 },
})

-- Omarchy: Steam floats, its main window and friends list sized
-- (apps/steam.lua); Battle.net's launcher floats and its installer draws its
-- own frame (apps/battlenet.lua); Hermes' HUD has no border (apps/hermes.lua).
hl.window_rule({
  name = "haseen_steam",
  match = { class = "steam" },
  float = true,
})
hl.window_rule({
  name = "haseen_steam_main",
  match = { class = "steam", title = "Steam" },
  center = true,
  size = { 1100, 700 },
})
hl.window_rule({
  name = "haseen_steam_friends",
  match = { class = "steam", title = "Friends List" },
  size = { 460, 800 },
})
hl.window_rule({
  name = "haseen_battlenet",
  match = { class = "^steam_app_battlenet$", title = "^Battle\\.net$" },
  float = true,
  center = true,
  size = { 1280, 800 },
})
hl.window_rule({
  name = "haseen_battlenet_setup",
  match = { class = "^steam_app_battlenet$", title = "^Battle\\.net Setup$" },
  decorate = false,
  no_blur = true,
  no_shadow = true,
})
hl.window_rule({
  name = "haseen_hermes_hud",
  match = { class = "^Hermes$", title = "^Hermes HUD$" },
  float = true,
  border_size = 0,
})

-- Omarchy: browsers carry a tag for the rules that single them out
-- (apps/browser.lua:2-3). Only tags: Omarchy's forced tiling is not taken.
hl.window_rule({
  name = "haseen_chromium_tag",
  match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" },
  tag = "+chromium-based-browser",
})
hl.window_rule({
  name = "haseen_firefox_tag",
  match = { class = "([fF]irefox|zen|librewolf)" },
  tag = "+firefox-based-browser",
})

-- Omarchy: picture-in-picture video (apps/pip.lua): borderless, pinned on
-- every workspace, 600 x 338 in the top-right corner; Google Meet's, which
-- carries the meeting's title, in the bottom-right one.
hl.window_rule({
  name = "haseen_pip_tag",
  match = { title = "(Picture.?in.?[Pp]icture)" },
  tag = "+pip",
})
hl.window_rule({
  name = "haseen_pip",
  match = { tag = "pip" },
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  move = { "(monitor_w-window_w-40)", "(monitor_h*0.04)" },
})
hl.window_rule({
  name = "haseen_meet_pip",
  match = { tag = "chromium-based-browser", title = "^Meet - .+" },
  float = true,
  pin = true,
  size = { 600, 338 },
  keep_aspect_ratio = true,
  border_size = 0,
  move = { "(monitor_w-window_w-40)", "(monitor_h-window_h-40)" },
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
  -- Omarchy's screensaver slides in (apps/system.lua:35).
  animation = "slide",
})

-- The "terminal" tag: one definition of what counts as a terminal, which the
-- universal copy/paste binds (binds.lua) read. Adapted from Omarchy
-- default/hypr/apps/terminals.lua (MIT, Copyright (c) David Heinemeier
-- Hansson). The class is matched in full, so foot's other app-id is spelt out.
hl.window_rule({
  name = "haseen_terminal_tag",
  match = { class = "^(Alacritty|kitty|com\\.mitchellh\\.ghostty|foot|footclient|org\\.codeberg\\.dnkl\\.foot|wezterm|org\\.wezfurlong\\.wezterm|haseen\\.floating)$" },
  tag = "+terminal",
})

-- Terminals opened by haseen commands (pickers, setup steps, editors): the
-- floating treatment Omarchy gives its own TUI windows (apps/system.lua:2-4).
hl.window_rule({
  name = "haseen_floating_terminal",
  match = { class = "^haseen\\.floating$" },
  float = true,
  center = true,
  size = { 875, 600 },
})

-- haseen.transparent_window(match, opacity) — Omarchy's standard active and
-- inactive transparency for the windows MATCH selects (a class pattern or a
-- match table); a theme may pass its own "active inactive" pair. Adapted
-- from Omarchy's o.transparent_window (helpers.lua:316-320). Without blur,
-- only the wallpaper shows through.
function haseen.transparent_window(match, opacity)
  if type(match) == "string" then
    match = { class = match }
  end
  hl.window_rule({ match = match, opacity = opacity or "0.985 0.96", tag = "+transparent-window" })
end

-- Omarchy: terminals, TUIs included, and these apps opt in (windows.lua:21-23).
haseen.transparent_window({ tag = "terminal" })
haseen.transparent_window("(omawrite|1[pP]assword|com\\.onepassword\\.OnePassword|org\\.gnome\\.Nautilus)")
haseen.transparent_window("(org\\.localsend\\.)?localsend(_app)?")

-- Webcam overlay while screen recording: Omarchy's default (medium) size and
-- corner, scaled from the monitor height, pinned and never dimmed
-- (apps/webcam-overlay.lua:7-10,18-23).
hl.window_rule({
  name = "haseen_webcam_overlay",
  match = { class = "^haseen-webcam$" },
  float = true,
  pin = true,
  no_initial_focus = true,
  no_dim = true,
  size = { "(monitor_h*2/9)", "(monitor_h/4)" },
  move = { "(monitor_w-monitor_h*2/9-40)", "(monitor_h-monitor_h/4-40)" },
})

-- slurp's region selection: no fade, so the frozen frame is what gets
-- captured (Omarchy: apps/screenshot-selection.lua:2).
hl.layer_rule({
  name = "haseen_slurp_selection",
  match = { namespace = "selection" },
  no_anim = true,
  animation = "none",
})

-- Omasnap's overlay (plan 107) opens and closes at once, as its README and
-- Omarchy 4.5 (default/hypr/apps/screenshot-selection.lua) set it. Not
-- no_screen_share as Omarchy has it: Hyprland then blacks out the whole
-- overlay in output capture, its transparent live region included, and a
-- scrolling capture stitches nothing (Omasnap 282b338, issue #128).
hl.layer_rule({
  name = "haseen_omasnap_overlay",
  match = { namespace = "^omasnap$" },
  no_anim = true,
  animation = "none",
})

-- The menu (placement "overlay") pops in and out without the layer fade, as
-- Omarchy's menu does; mid-fade it showed the windows behind it through.
hl.layer_rule({
  name = "haseen_overlay_panel",
  match = { namespace = "^haseen-overlay$" },
  no_anim = true,
})

-- Omarchy: the bar stays put, and the OSD and the keyboard panel pop, with no
-- layer animation (apps/omarchy-shell.lua:5,12), on haseen's namespaces.
hl.layer_rule({
  name = "haseen_bar_layer",
  match = { namespace = "^haseen-bar$" },
  no_anim = true,
  animation = "none",
})
hl.layer_rule({
  name = "haseen_popped_layers",
  match = { namespace = "^(haseen-osd|omarchy-keyboard-panel)$" },
  no_anim = true,
  animation = "none",
})
