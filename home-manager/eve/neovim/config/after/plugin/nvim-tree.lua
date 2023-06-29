require("nvim-tree").setup({
	sort_by = "case_sensitive",
	hijack_netrw = true,
	hijack_cursor = true,
	renderer = {
		group_empty = true,
	},
	filters = {
		dotfiles = true,
	},
})

local api = require("nvim-tree.api")
vim.keymap.set("n", "<C-f>", api.tree.toggle, { desc = "nvim-tree toggle" })
