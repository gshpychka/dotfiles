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

-- Toggle displaying absolute line numbers instead of relative
local default_statuscolumn = vim.o.statuscolumn

local toggle_absolute_line_numbers = function()
	if vim.o.statuscolumn == default_statuscolumn then
		vim.o.statuscolumn =
			"%=%{v:virtnum < 1 ? (v:lnum < 10 ? v:lnum . '  ' : v:lnum) : ''}%=%s"
	else
		vim.o.statuscolumn = default_statuscolumn
	end
end

vim.keymap.set(
	"n",
	"<leader>ln",
	toggle_absolute_line_numbers,
	{ desc = "Toggle absolute line numbers" }
)

vim.keymap.set(
	"n",
	"]q",
	":cnext<CR>",
	{ desc = "Go to the next item in the Quickfix list" }
)
vim.keymap.set(
	"n",
	"[q",
	":cprevious<CR>",
	{ desc = "Go to the previous item in the Quickfix list" }
)
