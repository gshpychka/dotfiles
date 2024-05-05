vim.g.mapleader = " "
-- cannot be in after/plugin because has to run before plugin
vim.g.tmux_navigator_no_mappings = 1

vim.keymap.set(
	"v",
	"p",
	'"_dP',
	{ noremap = true, desc = "Paste without yanking" }
)
vim.keymap.set(
	{ "n", "v" },
	"<leader>y",
	'"+y',
	{ noremap = true, desc = "Yank into system clipboard" }
)

vim.keymap.set(
	"n",
	"<C-d>",
	"<C-d>zz",
	{ desc = "Move down and keep cursor in the middle" }
)
vim.keymap.set(
	"n",
	"<C-u>",
	"<C-u>zz",
	{ desc = "Move up and keep cursor in the middle" }
)

vim.keymap.set(
	"n",
	"n",
	"nzzzv",
	{ desc = "Next result in the middle of the screen" }
)
vim.keymap.set(
	"n",
	"N",
	"Nzzzv",
	{ desc = "Previous result in the middle of the screen" }
)

-- Toggle displaying absolute line numbers in addition to relative
local toggleAbsoluteLineNumbers = function()
	if vim.o.statuscolumn == "%s %l %r" then
		vim.o.statuscolumn = "%s %r"
	else
		vim.o.statuscolumn = "%s %l %r"
	end
end

vim.keymap.set(
	"n",
	"<leader>ln",
	toggleAbsoluteLineNumbers,
	{ desc = "Toggle absolute line numbers" }
)
