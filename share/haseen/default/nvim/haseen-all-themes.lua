-- Every colourscheme plugin a haseen stock theme names, installed but not
-- loaded, so `haseen theme set` can switch a running nvim to any of them
-- without a network clone. `haseen theme set` links this file into
-- ~/.config/nvim/lua/plugins/; tests/test-nvim-theme.sh fails when a stock
-- theme or the neovim.lua template names a plugin missing here.
--
-- Adapted from Omarchy's all-themes.lua (MIT, Copyright (c) David Heinemeier
-- Hansson). Name and branch of aether match share/haseen/themed/neovim.lua.tpl:
-- lazy merges specs by name, and a different name here would install the
-- plugin into a directory the theme never loads.
local function theme(repo, extra)
	return vim.tbl_extend("force", { repo, lazy = true, priority = 1000 }, extra or {})
end

return {
	theme("omacom/aether.nvim", { branch = "v3", name = "aether" }),
	theme("catppuccin/nvim", { name = "catppuccin" }),
	theme("neanias/everforest-nvim"),
	theme("kepano/flexoki-neovim"),
	theme("ellisonleao/gruvbox.nvim"),
	theme("bjarneo/hackerman.nvim"),
	theme("rebelot/kanagawa.nvim"),
	theme("omacom-io/lumon.nvim"),
	theme("tahayvr/matteblack.nvim"),
	theme("EdenEast/nightfox.nvim"),
	theme("ribru17/bamboo.nvim"),
	theme("OldJobobo/retro-82.nvim"),
	theme("rose-pine/neovim", { name = "rose-pine" }),
	theme("ficcdaf/ashen.nvim"),
	theme("folke/tokyonight.nvim"),
}
