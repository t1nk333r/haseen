-- haseen.nvim's colourscheme bridge. `haseen setup nvim` links this file into
-- ~/.config/nvim/lua/plugins/ of the config it installs (the owner's plain
-- lazy.nvim config, plan 065), and `haseen theme set` takes the link as the
-- sign that a config without LazyVim follows haseen's themes too.
--
-- haseen's theme specs (current/theme/neovim.lua, linked as theme.lua) are
-- written for LazyVim: the colourscheme is opts.colorscheme of a
-- "LazyVim/LazyVim" entry, which LazyVim applies at startup. Without LazyVim
-- that entry would only clone LazyVim, so it is disabled here, and the
-- colourscheme is applied once lazy.nvim has set up (User LazyDone). lazy's
-- ColorSchemePre handler loads the theme's plugin even when it is lazy.
-- Switching in a running nvim is haseen-theme-hotreload.lua's job.
--
-- lazy runs this file on every spec load, so the augroup is cleared each time.

local function theme_colorscheme()
	package.loaded["plugins.theme"] = nil
	local ok, spec = pcall(require, "plugins.theme")
	if not ok or type(spec) ~= "table" then
		return nil
	end
	for _, entry in ipairs(spec) do
		if type(entry) == "table" and entry[1] == "LazyVim/LazyVim" then
			return entry.opts and entry.opts.colorscheme
		end
	end
	return nil
end

vim.api.nvim_create_autocmd("User", {
	group = vim.api.nvim_create_augroup("haseen-colorscheme", { clear = true }),
	pattern = "LazyDone",
	once = true,
	-- :colorscheme must fire ColorSchemePre (lazy loads the plugin there) and
	-- ColorScheme (statuslines re-read the colours) from inside this autocmd.
	nested = true,
	desc = "haseen: apply the theme `haseen theme set` linked",
	callback = function()
		local name = theme_colorscheme()
		if not name then
			return
		end
		local ok, err = pcall(vim.cmd.colorscheme, name)
		if not ok then
			vim.notify("haseen: colorscheme " .. name .. ": " .. tostring(err), vim.log.levels.WARN)
		end
	end,
})

return { { "LazyVim/LazyVim", enabled = false } }
