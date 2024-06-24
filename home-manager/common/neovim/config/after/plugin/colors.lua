require("gruvbox").setup({
	terminal_colors = true,
	undercurl = true,
	underline = true,
	bold = false,
	-- italic = {
	--   strings = true,
	--   comments = true,
	--   operators = false,
	--   folds = true,
	-- },
	strikethrough = true,
	invert_selection = false,
	invert_signs = false,
	invert_tabline = false,
	invert_intend_guides = false,
	inverse = true, -- invert background for search, diffs, statuslines and errors
	contrast = "hard", -- can be "hard", "soft" or empty string
	dim_inactive = false,
	transparent_mode = false,
})
vim.opt.termguicolors = true
vim.o.background = "dark"
vim.cmd.colorscheme("gruvbox")
-- @lsp.type.comment from LSP overrides @comment.todo from Treesitter
-- So this does not work properly
-- The backgroung is preserved, since the LSP highlight doesn't touch it
vim.api.nvim_set_hl(0, "TODO", { link = "GruvboxYellowSign" })
