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
	"<leader>fnk",
	builtin.keymaps,
	{ desc = "Telescope keymaps" }
)

-- Git
vim.keymap.set(
	"n",
	"<leader>fgcc",
	builtin.git_commits,
	{ desc = "Telescope Git commits" }
)
vim.keymap.set(
	"n",
	"<leader>fgcb",
	builtin.git_bcommits,
	{ desc = "Telescope Git buffer commits" }
)
vim.keymap.set(
	"v",
	"<leader>fgcb",
	builtin.git_bcommits_range,
	{ desc = "Telescope Git commits for range" }
)
vim.keymap.set(
	"n",
	"<leader>fgb",
	builtin.git_branches,
	{ desc = "Telescope Git branches" }
)
vim.keymap.set(
	"n",
	"<leader>fgs",
	builtin.git_status,
	{ desc = "Telescope Git status" }
)

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
		-- live_grep = {
		-- 	glob_patern = "!*.lock",
		-- },
	},
})

require("telescope").load_extension("ui-select")
require("telescope").load_extension("fzf")
