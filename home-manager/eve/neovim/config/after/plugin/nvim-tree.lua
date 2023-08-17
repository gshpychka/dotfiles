require("nvim-tree").setup({
	sort_by = "case_sensitive",
	hijack_netrw = true,
	hijack_cursor = true,
	renderer = {
		group_empty = true,
	},
	sync_root_with_cwd = true,
	reload_on_bufenter = true,
	update_focused_file = {
		enable = true,
	},
	filters = {
		dotfiles = false,
	},
})

local api = require("nvim-tree.api")
vim.keymap.set("n", "<C-f>", api.tree.toggle, { desc = "nvim-tree toggle" })
