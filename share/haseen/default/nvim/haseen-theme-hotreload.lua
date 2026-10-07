-- haseen theme hot-reload for LazyVim and haseen.nvim. `haseen theme set`
-- links this file into ~/.config/nvim/lua/plugins/ next to theme.lua, which
-- points at ~/.local/state/haseen/current/theme/neovim.lua.
--
-- lazy.nvim's change detection stats every spec file every 2 s, following the
-- theme.lua link, and fires `User LazyReload` once the new theme is in place.
-- The autocmd below answers that event: it re-reads plugins.theme, reloads the
-- colourscheme plugin with the new opts and applies the colourscheme.
--
-- Registered from the module body, and the spec is empty. Omarchy wraps the
-- same code in a local plugin with dir = stdpath("config"), but lazy merges
-- local plugins by dir, so a second such spec (Omarchy's hook, or one of the
-- user's) would replace this one's config. lazy runs the body on every spec
-- load, so the augroup is cleared each time.
--
-- Adapted from Omarchy's omarchy-theme-hotreload.lua (MIT, Copyright (c)
-- David Heinemeier Hansson): same trigger and reload steps, haseen's name.

-- A user file Omarchy's setup also honours: re-applied after the switch.
local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

local function apply()
	local ok, theme_spec = pcall(require, "plugins.theme")
	if not ok or type(theme_spec) ~= "table" then
		return
	end

	-- The first entry that is not LazyVim is the colourscheme plugin.
	local theme_plugin_name, colorscheme = nil, nil
	for _, spec in ipairs(theme_spec) do
		if spec[1] == "LazyVim/LazyVim" then
			colorscheme = spec.opts and spec.opts.colorscheme
		elseif not theme_plugin_name and type(spec[1]) == "string" then
			theme_plugin_name = spec.name or spec[1]:match("[^/]+$")
		end
	end
	if not colorscheme then
		return
	end

	vim.cmd("highlight clear")
	if vim.fn.exists("syntax_on") == 1 then
		vim.cmd("syntax reset")
	end
	-- A light colourscheme sets "light" itself.
	vim.o.background = "dark"

	local theme_plugin = theme_plugin_name and require("lazy.core.config").plugins[theme_plugin_name]
	if theme_plugin then
		-- Drop the plugin's modules so its colours are read again.
		require("lazy.core.util").walkmods(theme_plugin.dir .. "/lua", function(modname)
			package.loaded[modname] = nil
			package.preload[modname] = nil
		end)
	end

	-- Two themes on one plugin (every generated theme uses aether): lazy keeps
	-- the old opts of a loaded plugin, so reload it to run setup() with the
	-- new ones.
	if theme_plugin and theme_plugin._ and theme_plugin._.loaded then
		require("lazy.core.loader").reload(theme_plugin)
	else
		require("lazy.core.loader").colorscheme(colorscheme)
	end

	vim.defer_fn(function()
		pcall(vim.cmd.colorscheme, colorscheme)
		vim.cmd("redraw!")
		if vim.fn.filereadable(transparency_file) == 1 then
			vim.defer_fn(function()
				vim.cmd.source(transparency_file)
				vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
				vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
				vim.cmd("redraw!")
			end, 5)
		end
	end, 5)
end

vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("haseen-theme-hotreload", { clear = true }),
	pattern = "LazyReload",
	desc = "haseen: apply the theme `haseen theme set` linked",
	callback = function()
		package.loaded["plugins.theme"] = nil
		vim.schedule(apply)
	end,
})

return {}
