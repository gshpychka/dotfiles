require("eyeliner").setup({
	highlight_on_key = true,
	dim = true,
})
vim.api.nvim_set_hl(0, "EyelinerDimmed", { link = "NonText" })
vim.api.nvim_set_hl(0, "EyelinerPrimary", { link = "GruvboxGreenBold" })
