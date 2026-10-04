-- haseen default key bindings.
--
-- Hyprland stacks binds: to change one, hl.unbind() the exact key string used
-- here first (in ~/.config/hypr/bindings.lua), then bind it again; otherwise
-- both actions fire.
--
-- Shell actions go through `haseen shell ipc`, which talks to whichever shell
-- is active (haseen or DMS). Volume and brightness call wpctl/brightnessctl
-- directly; the shell's OSD watches PipeWire and the backlight itself.

local b = haseen.bind
local ipc = haseen.ipc
local launch = haseen.launch

-- Shell --------------------------------------------------------------------
b("SUPER + SPACE", "Launcher", ipc("launcher", "toggle"))
b("SUPER + CTRL + L", "Lock screen", ipc("lock", "lock"))
b("SUPER + A", "AI panel", ipc("panel", "toggle", "haseen.ai"))
b("SUPER + SHIFT + comma", "Clear notifications", ipc("notifications", "clear"))
b("SUPER + CTRL + comma", "Do not disturb", ipc("notifications", "toggleDnd"))
b("SUPER + ESCAPE", "Close panel", ipc("panel", "close"))

-- Apps -----------------------------------------------------------------------
b("SUPER + RETURN", "Terminal", launch('"${TERMINAL:-foot}"'))
b("SUPER + B", "Browser", launch('"$(xdg-settings get default-web-browser)"'))

-- Screenshots and colour picker ----------------------------------------------
b("PRINT", "Screenshot region to clipboard", 'grim -g "$(slurp -d)" - | wl-copy -t image/png')
b("SHIFT + PRINT", "Screenshot screen to clipboard", "grim - | wl-copy -t image/png")
b("SUPER + PRINT", "Colour picker", "pkill hyprpicker || hyprpicker -a")

-- Session ----------------------------------------------------------------------
b("SUPER + SHIFT + ESCAPE", "Log out", "uwsm stop")

-- Volume, brightness, media (also on the lock screen) ------------------------
local held = { locked = true, repeating = true }
local once = { locked = true }
b("XF86AudioRaiseVolume", "Volume up", "wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+", held)
b("XF86AudioLowerVolume", "Volume down", "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", held)
b("XF86AudioMute", "Mute", "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", once)
b("XF86AudioMicMute", "Mute microphone", "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle", once)
b("XF86MonBrightnessUp", "Brightness up", "brightnessctl -e4 -n2 set 5%+", held)
b("XF86MonBrightnessDown", "Brightness down", "brightnessctl -e4 -n2 set 5%-", held)
b("XF86AudioPlay", "Play/pause", "playerctl play-pause", once)
b("XF86AudioPause", "Play/pause", "playerctl play-pause", once)
b("XF86AudioNext", "Next track", "playerctl next", once)
b("XF86AudioPrev", "Previous track", "playerctl previous", once)

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
