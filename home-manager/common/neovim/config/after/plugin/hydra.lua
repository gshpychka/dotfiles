local Hydra = require("hydra")
local gitsigns = require("gitsigns")
local ts_builtin = require("telescope.builtin")

Hydra({
	name = "Git",
	config = {
		color = "pink",
		invoke_on_body = true,
		hint = false,
		on_enter = function()
			gitsigns.toggle_numhl(true)
			gitsigns.toggle_current_line_blame(true)
			gitsigns.toggle_linehl(true)
			gitsigns.toggle_deleted(true)
		end,
		on_exit = function()
			gitsigns.toggle_numhl(false)
			gitsigns.toggle_current_line_blame(false)
			gitsigns.toggle_linehl(false)
			gitsigns.toggle_deleted(false)
		end,
	},
	mode = { "n", "x", "v" },
	body = "<leader>gg",
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
		{
			"s",
			gitsigns.stage_hunk,
			{ silent = true, desc = "Stage hunk" },
		},
		{ "S", gitsigns.stage_buffer, { desc = "Stage buffer" } },
		{
			"r",
			gitsigns.reset_hunk,
			{ silent = true, desc = "Reset hunk" },
		},
		{
			"R",
			gitsigns.reset_buffer,
			{ silent = true, desc = "Reset buffer" },
		},
		{ "u", gitsigns.undo_stage_hunk, { desc = "Unstage hunk" } },
		{ "p", gitsigns.preview_hunk, { desc = "Preview hunk" } },
		{ "d", gitsigns.diffthis, { nowait = true, desc = "Diff" } },
		{
			"B",
			function()
				gitsigns.blame_line({ full = true })
			end,
			{ desc = "blame show full" },
		},
		{
			"<leader>fc",
			ts_builtin.git_commits,
			{ desc = "Telescope Git commits" },
		},
		{
			"<leader>fbc",
			ts_builtin.git_bcommits,
			{ desc = "Telescope Git buffer commits" },
		},
		{
			"<leader>fbc",
			ts_builtin.git_bcommits_range,
			{ mode = "v", desc = "Telescope Git commits for range" },
		},
		{
			"<leader>fbr",
			ts_builtin.git_branches,
			{ desc = "Telescope Git branches" },
		},
		{
			"<leader>fs",
			ts_builtin.git_status,
			{ desc = "Telescope Git status" },
		},
		{ "/", gitsigns.show, { exit = true, desc = "show base file" } }, -- show the base of the file
		-- { "<Enter>", "<Cmd>Neogit<CR>", { exit = true, desc = "Neogit" } },
		{
			"<esc>",
			nil,
			{ exit = true, nowait = true, desc = "exit" },
		},
	},
})

Hydra({
	name = "WindowManage",
	config = {
		color = "pink",
		invoke_on_body = true,
		hint = false,
	},
	mode = { "n", "x" },
	body = "<leader>w",
	heads = {
		{ "<esc>", nil, { exit = true, nowait = true, desc = "exit" } },
		{
			"h",
			function()
				vim.cmd("wincmd h")
			end,
			{ nowait = true, desc = "Move to left window" },
		},
		{
			"j",
			function()
				vim.cmd("wincmd j")
			end,
			{ nowait = true, desc = "Move to window below" },
		},
		{
			"k",
			function()
				vim.cmd("wincmd k")
			end,
			{ nowait = true, desc = "Move to window above" },
		},
		{
			"l",
			function()
				vim.cmd("wincmd l")
			end,
			{ nowait = true, desc = "Move to right window" },
		},

		-- Window resizing
		{
			"+",
			function()
				vim.cmd("resize +5")
			end,
			{ nowait = true, desc = "Increase height" },
		},
		{
			"-",
			function()
				vim.cmd("resize -5")
			end,
			{ nowait = true, desc = "Decrease height" },
		},
		{
			"<",
			function()
				vim.cmd("vertical resize -5")
			end,
			{ nowait = true, desc = "Decrease width" },
		},
		{
			">",
			function()
				vim.cmd("vertical resize +5")
			end,
			{ nowait = true, desc = "Increase width" },
		},

		-- Split management
		{
			"s",
			function()
				vim.cmd("split")
			end,
			{ nowait = true, desc = "Split horizontally" },
		},
		{
			"v",
			function()
				vim.cmd("vsplit")
			end,
			{ nowait = true, desc = "Split vertically" },
		},
		{
			"q",
			function()
				vim.cmd("close")
			end,
			{ nowait = true, desc = "Close current window" },
		},

		-- Tab management
		{
			"t",
			function()
				vim.cmd("tabnew")
			end,
			{ nowait = true, exit = true, desc = "New tab" },
		},
		{
			"T",
			function()
				vim.cmd("tabclose")
			end,
			{ nowait = true, exit = true, desc = "Close current tab" },
		},
		-- barbar.nvim keymaps
		{
			"n",
			function()
				vim.cmd("BufferPrevious")
			end,
			{ nowait = true, desc = "Next buffer" },
		},
		{
			"p",
			function()
				vim.cmd("BufferNext")
			end,
			{ nowait = true, desc = "Previous buffer" },
		},
	},
})
