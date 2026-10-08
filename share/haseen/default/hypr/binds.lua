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
--
-- The layout is the owner's: vim directions, SUPER + Q to close, a silent
-- SUPER + SHIFT + <n>, ALT for split and workspace layout, and the HYPER snap
-- layer all come from waydots ~/.config/hypr/bindings.lua rather than from
-- Omarchy's defaults. Keep a description on every bind: `haseen keybinds` and
-- the haseen.keybinds sheet show it, and group binds by the `-- Section ---`
-- comment they are written under.

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
-- SUPER + F1 and ALT + V, not SUPER + SLASH and SUPER + CTRL + V: the owner's
-- layout (waydots ~/.config/hypr/bindings.lua).
b("SUPER + F1", "Keybindings", ipc("keybinds", "toggle"))
b("ALT + V", "Clipboard history", ipc("panel", "toggle", "haseen.clipboard"))
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
-- Screen search, on the keys the owner uses: read a region, or act on the
-- picture itself. `haseen capture text` is the plain stock OCR and stays in
-- the capture menu.
b("SUPER + CTRL + PRINT", "OCR screen region", "haseen search screen text")
b("SUPER + SHIFT + PRINT", "Search a screen region", "haseen search screen image")
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
-- the lock state has settled; ignore_mods: Shift + Caps Lock too.
-- The kind is off by default, and Caps is a busy key under compose:caps: so
-- the bind is one `test` in the shell Hyprland runs it with, and the IPC
-- call (two scripts and a qs client, ~40 ms) only follows while haseen.osd
-- has lockKeys on and keeps the flag file in $XDG_RUNTIME_DIR/haseen.
local lockkey = { non_consuming = true, release = true, ignore_mods = true }
local lockkeys = 'test -e "$XDG_RUNTIME_DIR/haseen/osd-lockkeys" && ' .. ipc("osd", "lockkeys")
b("code:66", "Caps Lock OSD", lockkeys, lockkey)
b("code:77", "Num Lock OSD", lockkeys, lockkey)

-- Windows ----------------------------------------------------------------------
-- SUPER + Q is the owner's close key; SUPER + W is Omarchy's and stays, so
-- muscle memory from either keeps working.
b("SUPER + Q", "Close window", hl.dsp.window.close())
b("SUPER + W", "Close window", hl.dsp.window.close())
b("SUPER + T", "Toggle floating", hl.dsp.window.float({ action = "toggle" }))
b("SUPER + F", "Fullscreen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
b("SUPER + ALT + F", "Maximise", hl.dsp.window.fullscreen({ mode = "maximized" }))
b("SUPER + P", "Pseudo-tile", hl.dsp.window.pseudo())
b("SUPER + G", "Toggle group", hl.dsp.group.toggle())
b("SUPER + ALT + TAB", "Next window in group", hl.dsp.group.next())

-- On ALT, not SUPER: SUPER + J and SUPER + L are focus keys below.
b("ALT + J", "Toggle split", hl.dsp.layout("togglesplit"))
b("ALT + L", "Toggle workspace layout", "haseen toggle workspace-layout")

-- Focus and move, on the arrows and on the vim keys. SUPER + SHIFT swaps with
-- the arrows (Omarchy's pairing) and moves with the vim keys (the owner's),
-- so both habits reach the dispatcher they expect.
for _, d in ipairs({
  { arrow = "LEFT", vim = "H", dir = "l", name = "left" },
  { arrow = "RIGHT", vim = "L", dir = "r", name = "right" },
  { arrow = "UP", vim = "K", dir = "u", name = "up" },
  { arrow = "DOWN", vim = "J", dir = "d", name = "down" },
}) do
  b("SUPER + " .. d.arrow, "Move focus " .. d.name, hl.dsp.focus({ direction = d.dir }))
  b("SUPER + " .. d.vim, "Move focus " .. d.name, hl.dsp.focus({ direction = d.dir }))
  b("SUPER + SHIFT + " .. d.arrow, "Swap window " .. d.name, hl.dsp.window.swap({ direction = d.dir }))
  b("SUPER + SHIFT + " .. d.vim, "Move window " .. d.name, hl.dsp.window.move({ direction = d.dir }))
end

-- Cycling raises too, so the window you land on is not left under a floating
-- one. Omarchy stacks a second bind on the key for that; one Lua function is
-- one bind, so the sheet shows the key once.
local function cycle_and_raise(dispatcher)
  return function()
    hl.dispatch(dispatcher)
    hl.dispatch(hl.dsp.window.bring_to_top())
  end
end
b("ALT + TAB", "Next window (raised)", cycle_and_raise(hl.dsp.window.cycle_next()))
b("ALT + SHIFT + TAB", "Previous window (raised)", cycle_and_raise(hl.dsp.window.cycle_next({ next = false })))

b("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
b("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })

b("SUPER + minus", "Shrink width", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { repeating = true })
b("SUPER + equal", "Grow width", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { repeating = true })
b("SUPER + SHIFT + minus", "Shrink height", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { repeating = true })
b("SUPER + SHIFT + equal", "Grow height", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { repeating = true })

-- Workspaces -----------------------------------------------------------------
-- code:10..19 are the number-row keys 1..0 on every layout, including AZERTY
-- and Arabic, where the keysyms are not digits.
--
-- SUPER + SHIFT moves the window silently (the owner's layout): the window
-- goes, the view stays. Add ALT to follow it over.
for ws = 1, 10 do
  local key = "code:" .. tostring(ws + 9)
  local name = tostring(ws)
  b("SUPER + " .. key, "Workspace " .. name, hl.dsp.focus({ workspace = name }))
  b("SUPER + SHIFT + " .. key, "Move window silently to workspace " .. name,
    hl.dsp.window.move({ workspace = name, follow = false }))
  b("SUPER + SHIFT + ALT + " .. key, "Move window to workspace " .. name,
    hl.dsp.window.move({ workspace = name }))
end

b("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
b("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))
b("SUPER + mouse_down", "Next workspace", hl.dsp.focus({ workspace = "e+1" }))
b("SUPER + mouse_up", "Previous workspace", hl.dsp.focus({ workspace = "e-1" }))

b("SUPER + S", "Scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))
b("SUPER + ALT + S", "Move window to scratchpad", hl.dsp.window.move({ workspace = "special:scratchpad", follow = false }))

b("SUPER + SHIFT + ALT + LEFT", "Move workspace to left monitor", hl.dsp.workspace.move({ monitor = "l" }))
b("SUPER + SHIFT + ALT + RIGHT", "Move workspace to right monitor", hl.dsp.workspace.move({ monitor = "r" }))

-- Snap layer -------------------------------------------------------------------
-- Rectangle-style snapping on HYPER, which is CapsLock remapped to
-- SUPER+SHIFT+ALT+CTRL by keyd; the four-modifier chord works without keyd too.
-- A snap floats the window, sizes it to a fraction of the monitor's usable
-- area (the space a bar reserves is left out) and pushes it to an edge.
-- Pressing the same snap again puts the window back where it was.
--
-- All of it is Hyprland dispatchers from Lua: no helper process, no polling,
-- nothing to install.
local HYPER = "SUPER + SHIFT + ALT + CTRL + "

-- One record, not a table keyed by window: the restore you want is for the
-- window you are snapping right now, and a per-address table would outlive
-- every window in it. It lives on `haseen` because Hyprland re-runs this file
-- on reload, which would forget a local.
haseen.snap = haseen.snap or {}

-- usable_area(MONITOR) -> x, y, w, h in layout coordinates, whole pixels.
-- Monitor width and height are physical pixels and the reserved edges are
-- floats; everything a dispatcher takes is scaled and integral.
local function usable_area(mon)
  local reserved = mon.reserved or {}
  local left, top = reserved.left or 0, reserved.top or 0
  local scale = mon.scale
  if not scale or scale == 0 then
    scale = 1
  end
  return math.floor(mon.x + left),
    math.floor(mon.y + top),
    math.floor(mon.width / scale - left - (reserved.right or 0)),
    math.floor(mon.height / scale - top - (reserved.bottom or 0))
end

-- offset(ANCHOR, SLACK) -> how far from the left or top edge to start.
local function offset(anchor, slack)
  if anchor == "r" or anchor == "d" then
    return slack
  elseif anchor == "c" then
    return math.floor(slack / 2)
  end
  return 0
end

-- snap(MODE, WIDTH%, HEIGHT%, XANCHOR l|c|r, YANCHOR u|c|d) -> the bind action.
local function snap(mode, wpct, hpct, xanchor, yanchor)
  return function()
    local win = hl.get_active_window()
    if not win then
      return
    end
    local was = haseen.snap
    if was.address == win.address and was.mode == mode then
      -- The same snap twice: undo it.
      if was.floating then
        hl.dispatch(hl.dsp.window.resize({ x = was.w, y = was.h, exact = true }))
        hl.dispatch(hl.dsp.window.move({ x = was.x, y = was.y, exact = true }))
      else
        hl.dispatch(hl.dsp.window.float({ action = "off" }))
      end
      haseen.snap = {}
      return
    end
    local mon = win.monitor or hl.get_active_monitor()
    if not mon then
      return
    end
    if was.address == win.address then
      -- A different snap on the same window: keep the geometry it started
      -- from, so a later repeat still restores that and not this snap.
      was.mode = mode
    else
      haseen.snap = {
        address = win.address,
        mode = mode,
        floating = win.floating,
        x = win.at.x,
        y = win.at.y,
        w = win.size.x,
        h = win.size.y,
      }
    end
    local ux, uy, uw, uh = usable_area(mon)
    local w = math.floor(uw * wpct / 100)
    local h = math.floor(uh * hpct / 100)
    if not win.floating then
      hl.dispatch(hl.dsp.window.float({ action = "on" }))
    end
    hl.dispatch(hl.dsp.window.resize({ x = w, y = h, exact = true }))
    hl.dispatch(hl.dsp.window.move({
      x = ux + offset(xanchor, uw - w),
      y = uy + offset(yanchor, uh - h),
      exact = true,
    }))
  end
end

b(HYPER .. "H", "Snap left", snap("left", 50, 100, "l", "u"))
b(HYPER .. "L", "Snap right", snap("right", 50, 100, "r", "u"))
b(HYPER .. "K", "Snap top", snap("top", 100, 50, "l", "u"))
b(HYPER .. "J", "Snap bottom", snap("bottom", 100, 50, "l", "d"))
-- The bracket and quote keys sit where the corners are on the keyboard.
b(HYPER .. "BRACKETLEFT", "Snap top-left", snap("tl", 50, 50, "l", "u"))
b(HYPER .. "BRACKETRIGHT", "Snap top-right", snap("tr", 50, 50, "r", "u"))
b(HYPER .. "APOSTROPHE", "Snap bottom-left", snap("bl", 50, 50, "l", "d"))
b(HYPER .. "BACKSLASH", "Snap bottom-right", snap("br", 50, 50, "r", "d"))
b(HYPER .. "G", "Snap 80% centred", snap("big", 80, 80, "c", "c"))
-- F and M both maximise: the owner reaches for either.
b(HYPER .. "F", "Snap maximise", snap("max", 100, 100, "l", "u"))
b(HYPER .. "M", "Snap maximise", snap("max", 100, 100, "l", "u"))
