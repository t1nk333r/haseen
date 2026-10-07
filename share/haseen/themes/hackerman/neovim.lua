return {
	{
		"bjarneo/hackerman.nvim",
		-- hackerman's colours call require("aether"); the same name and branch as
		-- the template, so the aether plugin every generated theme uses serves it.
		dependencies = { { "omacom/aether.nvim", branch = "v3", name = "aether" } },
		priority = 1000,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "hackerman",
		},
	},
}
