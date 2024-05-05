vim.g.tmux_navigator_no_mappings = 1

vim.keymap.set(
	"n",
	"<m-h>",
	":TmuxNavigateLeft<cr>",
	{ noremap = true, silent = true, desc = "Move left with tmux-navigator" }
)
vim.keymap.set(
	"n",
	"<m-j>",
	":TmuxNavigateDown<cr>",
	{ noremap = true, silent = true, desc = "Move down with tmux-navigator" }
)
vim.keymap.set(
	"n",
	"<m-k>",
	":TmuxNavigateUp<cr>",
	{ noremap = true, silent = true, desc = "Move up with tmux-navigator" }
)
vim.keymap.set(
	"n",
	"<m-l>",
	":TmuxNavigateRight<cr>",
	{ noremap = true, silent = true, desc = "Move right with tmux-navigator" }
)
