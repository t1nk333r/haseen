-- Keep only your personal keybinding overrides here.

-- Add a new binding.
-- o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")

-- Released defaults (what replaces them is bound below)
hl.unbind("SUPER + J") -- toggle split -> focus down
for i = 1, 10 do
	hl.unbind("SUPER + SHIFT + code:" .. (9 + i))
end

-- Focus (vim keys)
o.bind("SUPER + H", "Move focus left", hl.dsp.focus({ direction = "left" }))
o.bind("SUPER + J", "Move focus down", hl.dsp.focus({ direction = "down" }))

hl.bind("ALT + TAB", function()
	hl.dispatch(hl.dsp.window.cycle_next())
	hl.dispatch(hl.dsp.window.bring_to_top())
end, { description = "Cycle windows (raise)" })

for i = 1, 10 do
	local key = "code:" .. (9 + i)
	o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. i .. " silently", hl.dsp.window.move({ workspace = tostring(i), follow = false }))
end

-- Launchers
o.bind("SUPER + D", "Apps menu", "omarchy-menu toggle apps")
o.bind("SUPER + SHIFT + Z", "Browser", o.launch("zen-browser"))
o.bind("SUPER + SHIFT + F", "File manager", { launch = 'flea --gui' })
o.bind("SUPER + ALT + SHIFT + F", "File manager (cwd)", { launch = 'flea --gui "$(omarchy-cmd-terminal-cwd)"' })
o.bind("SUPER + SHIFT + B", "Docs", { webapp = "https://example.com" })
o.window("com.example.picker", { tag = "+floating-window" })
