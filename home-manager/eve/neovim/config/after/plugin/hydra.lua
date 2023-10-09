local Hydra = require("hydra")
local gitsigns = require("gitsigns")

Hydra({
	name = "Git",
	config = {
		-- buffer = bufnr,
		color = "pink",
		invoke_on_body = true,
		hint = {
			border = "rounded",
		},
		on_enter = function()
			vim.cmd("mkview")
			vim.cmd("silent! %foldopen!")
			vim.bo.modifiable = false
			-- gitsigns.toggle_signs(true)
			gitsigns.toggle_line_blame(true)
			gitsigns.toggle_linehl(true)
			gitsigns.toggle_deleted(true)
		end,
		on_exit = function()
			local cursor_pos = vim.api.nvim_win_get_cursor(0)
			vim.cmd("loadview")
			vim.api.nvim_win_set_cursor(0, cursor_pos)
			vim.cmd("normal zv")
			-- gitsigns.toggle_signs(false)
			gitsigns.toggle_line_blame(false)
			gitsigns.toggle_linehl(false)
			gitsigns.toggle_deleted(false)
		end,
	},
	mode = { "n", "x" },
	body = "<leader>g",
	heads = {
		{
			"J",
			function()
				if vim.wo.diff then
					return "]c"
				end
				vim.schedule(function()
					gitsigns.next_hunk()
				end)
				return "<Ignore>"
			end,
			{ expr = true, desc = "next hunk" },
		},
		{
			"K",
			function()
				if vim.wo.diff then
					return "[c"
				end
				vim.schedule(function()
					gitsigns.prev_hunk()
				end)
				return "<Ignore>"
			end,
			{ expr = true, desc = "prev hunk" },
		},
		{ "s", gitsigns.stage_hunk, { silent = true, desc = "Stage hunk" } },
		{ "S", gitsigns.stage_buffer, { desc = "Stage buffer" } },
		{ "r", gitsigns.reset_hunk, { silent = true, desc = "Reset hunk" } },
		{ "R", gitsigns.reset_buffer, { silent = true, desc = "Reset buffer" } },
		{ "u", gitsigns.undo_stage_hunk, { desc = "Unstage hunk" } },
		{ "p", gitsigns.preview_hunk, { desc = "Preview hunk" } },
		{ "d", gitsigns.toggle_deleted, { nowait = true, desc = "Toggle deleted" } },
		{ "d", gitsigns.diffthis, { nowait = true, desc = "Diff" } },
		{
			"B",
			function()
				gitsigns.blame_line({ full = true })
			end,
			{ desc = "blame show full" },
		},
		{ "/", gitsigns.show, { exit = true, desc = "show base file" } }, -- show the base of the file
		-- { "<Enter>", "<Cmd>Neogit<CR>", { exit = true, desc = "Neogit" } },
		{ "q", nil, { exit = true, nowait = true, desc = "exit" } },
	},
})
