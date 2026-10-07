-- haseen default key bindings.
--
-- Hyprland stacks binds: to change one, hl.unbind() the exact key string used
-- here first (in ~/.config/hypr/bindings.lua), then bind it again; otherwise
-- both actions fire.
--
-- Shell actions go through `haseen shell ipc`, which talks to whichever shell
-- is active (haseen or DMS). Volume calls wpctl directly and brightness goes
-- through `haseen brightness` (the backlight, or DDC monitors on a machine
-- without one); the shell's OSD watches PipeWire and the backlight itself.

local b = haseen.bind
local ipc = haseen.ipc
local launch = haseen.launch

-- Shell --------------------------------------------------------------------
-- The menus sit on Omarchy's keys (SUPER+SPACE menu, SUPER+ESCAPE system
-- menu), so muscle memory from Omarchy carries over; the app launcher takes
-- SUPER+SHIFT+SPACE, which pushes the bar toggle to SUPER+ALT+SPACE.
b("SUPER + SPACE", "Menu", "haseen menu")
b("SUPER + SHIFT + SPACE", "Launcher", ipc("launcher", "toggle"))
b("SUPER + ESCAPE", "System menu", "haseen menu system")
b("SUPER + CTRL + L", "Lock screen", ipc("lock", "lock"))
b("SUPER + A", "AI panel", ipc("panel", "toggle", "haseen.ai"))
b("SUPER + SHIFT + comma", "Clear notifications", ipc("notifications", "clear"))
b("SUPER + CTRL + comma", "Do not disturb", "haseen toggle dnd")
b("SUPER + CTRL + ESCAPE", "Close panel", ipc("panel", "close"))
b("SUPER + ALT + SPACE", "Toggle bar", "haseen bar toggle")
b("SUPER + SLASH", "Keybindings", ipc("keybinds", "toggle"))
b("SUPER + CTRL + V", "Clipboard history", ipc("panel", "toggle", "haseen.clipboard"))
b("SUPER + CTRL + E", "Emoji picker", ipc("panel", "toggle", "haseen.emoji"))
b("SUPER + ALT + C", "Calendar", ipc("panel", "toggle", "haseen.calendar"))

-- Style ------------------------------------------------------------------------
-- Omarchy's keys: SUPER+CTRL+SHIFT+SPACE picks a theme, SUPER+CTRL+SPACE picks a
-- background. Both are pickers; stepping to the next background (also `n` in
-- the picker) gets ALT added.
b("SUPER + CTRL + SHIFT + SPACE", "Theme picker", ipc("panel", "toggle", "haseen.themepicker"))
b("SUPER + CTRL + SPACE", "Background picker", ipc("panel", "toggle", "haseen.background"))
b("SUPER + CTRL + ALT + SPACE", "Next background", "haseen theme bg next")

-- Ambient ----------------------------------------------------------------------
b("SUPER + CTRL + I", "Stay awake", "haseen toggle idle")
b("SUPER + CTRL + N", "Night light", "haseen toggle nightlight")
b("SUPER + CTRL + S", "Screensaver", "haseen screensaver --force")
-- M for mode: free in haseen and in Omarchy's SUPER + CTRL row (plan 062).
b("SUPER + CTRL + M", "Context menu", "haseen menu trigger.context")

-- Apps -----------------------------------------------------------------------
b("SUPER + RETURN", "Terminal", launch('"${TERMINAL:-foot}"'))
b("SUPER + B", "Browser", launch('"$(xdg-settings get default-web-browser)"'))

-- Clipboard --------------------------------------------------------------------
-- Universal copy, paste and cut: SUPER + C/V/X send the app's own shortcut, so
-- one chord works in browsers, editors and terminals alike (terminals take
-- CTRL+Insert / SHIFT+Insert, as CTRL+C would interrupt). Adapted from Omarchy
-- default/hypr/bindings/clipboard.lua (MIT, Copyright (c) David Heinemeier
-- Hansson). The chord is sent with explicit mods to the focused surface, so the
-- held SUPER never merges into it; down and up are split because Hyprland's
-- send_shortcut can leave a synthetic key stuck (hyprwm/Hyprland discussion 14099).
local function send_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

local function focused_is_terminal()
  local window = hl.get_active_window()
  for _, tag in ipairs(window and window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function universal(mods, key, terminal_mods, terminal_key)
  return function()
    if focused_is_terminal() then
      send_once(terminal_mods, terminal_key)()
    else
      send_once(mods, key)()
    end
  end
end

b("SUPER + C", "Universal copy", universal("CTRL", "C", "CTRL", "Insert"))
b("SUPER + V", "Universal paste", universal("CTRL", "V", "SHIFT", "Insert"))
b("SUPER + X", "Universal cut", send_once("CTRL", "X"))

-- Capture ----------------------------------------------------------------------
b("PRINT", "Screenshot region", "haseen capture screenshot")
b("SHIFT + PRINT", "Screenshot window", "haseen capture screenshot window")
b("CTRL + PRINT", "Screenshot monitor", "haseen capture screenshot output")
b("ALT + PRINT", "Screen recording start/stop", "haseen capture screenrecord")
b("SUPER + PRINT", "Colour picker", "haseen capture color")
b("SUPER + CTRL + C", "Capture menu", "haseen menu trigger.capture")

-- Session ----------------------------------------------------------------------
b("SUPER + SHIFT + ESCAPE", "Log out", "uwsm stop")

-- Volume, brightness, media (also on the lock screen) ------------------------
local held = { locked = true, repeating = true }
local once = { locked = true }
b("XF86AudioRaiseVolume", "Volume up", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", held)
b("XF86AudioLowerVolume", "Volume down", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", held)
b("XF86AudioMute", "Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", once)
b("XF86AudioMicMute", "Mute microphone", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", once)
b("XF86MonBrightnessUp", "Brightness up", "haseen brightness up", held)
b("XF86MonBrightnessDown", "Brightness down", "haseen brightness down", held)
b("XF86KbdBrightnessUp", "Keyboard backlight up", "haseen brightness up kbd", held)
b("XF86KbdBrightnessDown", "Keyboard backlight down", "haseen brightness down kbd", held)
b("XF86AudioPlay", "Play/pause", "playerctl play-pause", once)
b("XF86AudioPause", "Play/pause", "playerctl play-pause", once)
b("XF86AudioNext", "Next track", "playerctl next", once)
b("XF86AudioPrev", "Previous track", "playerctl previous", once)

-- Lock keys ----------------------------------------------------------------
-- Hyprland sends no event when Caps Lock or Num Lock changes, so a bind on
-- the keys themselves tells the OSD to read the state once (plan 079).
-- code:66 and code:77 are the Caps Lock and Num Lock keys whatever they
-- type: under compose:caps Caps is Compose, and the read then finds nothing
-- changed. non_consuming: the key still reaches xkb and the app; release:
-- the lock state has settled; ignore_mods: Shift + Caps Lock too. The OSD
-- shows nothing unless haseen.osd's lockKeys setting is on.
local lockkey = { non_consuming = true, release = true, ignore_mods = true }
b("code:66", "Caps Lock OSD", ipc("osd", "lockkeys"), lockkey)
b("code:77", "Num Lock OSD", ipc("osd", "lockkeys"), lockkey)

-- Windows ----------------------------------------------------------------------
b("SUPER + W", "Close window", hl.dsp.window.close())
b("SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
b("SUPER + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
b("SUPER + ALT + F", "Maximise", hl.dsp.window.fullscreen({ mode = "maximized" }))
b("SUPER + J", "Toggle split", hl.dsp.layout("togglesplit"))
b("SUPER + P", "Pseudo-tile", hl.dsp.window.pseudo())
b("SUPER + G", "Toggle group", hl.dsp.group.toggle())
b("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())

for key, dir in pairs({ LEFT = "l", RIGHT = "r", UP = "u", DOWN = "d" }) do
  b("SUPER + " .. key, "Focus " .. dir, hl.dsp.focus({ direction = dir }))
  b("SUPER + SHIFT + " .. key, "Swap window " .. dir, hl.dsp.window.swap({ direction = dir }))
end

b("ALT + TAB", "Next window", hl.dsp.window.cycle_next())
b("ALT + SHIFT + TAB", "Previous window", hl.dsp.window.cycle_next({ next = false }))

b("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
b("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

b("SUPER + minus", "Shrink width", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
b("SUPER + equal", "Grow width", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
b("SUPER + SHIFT + minus", "Shrink height", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })
b("SUPER + SHIFT + equal", "Grow height", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })

-- Workspaces -----------------------------------------------------------------
-- code:10..19 are the number-row keys 1..0 on every layout, including AZERTY
-- and Arabic, where the keysyms are not digits.
for ws = 1, 10 do
  local key = "code:" .. tostring(ws + 9)
  local name = tostring(ws)
  b("SUPER + " .. key, "Workspace " .. name, hl.dsp.focus({ workspace = name }))
  b("SUPER + SHIFT + " .. key, "Move window to workspace " .. name, hl.dsp.window.move({ workspace = name }))
  b("SUPER + SHIFT + ALT + " .. key, "Move window silently to workspace " .. name,
    hl.dsp.window.move({ workspace = name, follow = false }))
end

b("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
b("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
b("SUPER + mouse_down", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
b("SUPER + mouse_up", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

b("SUPER + S", "Scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
b("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

b("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
b("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))
