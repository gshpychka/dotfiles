local builtin = require("telescope.builtin")
vim.keymap.set(
	"n",
	"<leader>ff",
	builtin.find_files,
	{ desc = "Telescope find files" }
)
vim.keymap.set(
	"n",
	"<leader>fgg",
	builtin.live_grep,
	{ desc = "Telescope live grep" }
)
vim.keymap.set(
	"n",
	"<leader>fb",
	builtin.buffers,
	{ desc = "Telescope buffers" }
)
vim.keymap.set(
	"n",
	"<leader>fr",
	builtin.lsp_references,
	{ desc = "Telescope LSP references" }
)
vim.keymap.set(
	"n",
	"<leader>fht",
	builtin.help_tags,
	{ desc = "Telescope help tags" }
)
vim.keymap.set(
	"n",
	"<leader>fts",
	builtin.treesitter,
	{ desc = "Telescope Treesitter" }
)

-- Neovim helpers
vim.keymap.set(
	"n",
	"<leader>fnc",
	builtin.commands,
	{ desc = "Telescope commands" }
)
vim.keymap.set(
	"n",
	"<leader>fhl",
	builtin.highlights,
	{ desc = "Telescope highlights" }
)
vim.keymap.set(
	"n",
	"<leader>fkm",
	builtin.keymaps,
	{ desc = "Telescope keymaps" }
)

local action_state = require("telescope.actions.state")

local git_commits_config = {
	mappings = {
		i = {
			["<C-M-d>"] = function()
				-- Open in diffview
				local selected_entry = action_state.get_selected_entry()
				local value = selected_entry.value
				-- close Telescope window properly prior to switching windows
				vim.api.nvim_win_close(0, true)
				vim.cmd("stopinsert")
				vim.schedule(function()
					vim.cmd(("DiffviewOpen %s^!"):format(value))
				end)
			end,
		},
	},
}
require("telescope").setup({
	defaults = {
		layout_config = {
			vertical = { width = 0.85 },
			horizontal = { width = 0.85 },
		},
		file_ignore_patterns = { "%.lock" },
	},
	extensions = {
		fzf = {
			fuzzy = true,
			case_mode = "smart_case",
		},
		["ui-select"] = {
			require("telescope.themes").get_dropdown({}),
		},
	},
	pickers = {
		find_files = {
			theme = "dropdown",
		},
		buffers = {
			theme = "dropdown",
		},
		git_commits = git_commits_config,
		git_bcommits = git_commits_config,
		git_bcommits_range = git_commits_config,
	},
})

require("telescope").load_extension("ui-select")
require("telescope").load_extension("fzf")
