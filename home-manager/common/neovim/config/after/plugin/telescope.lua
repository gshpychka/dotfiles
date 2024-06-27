local builtin = require("telescope.builtin")
local actions = require("telescope.actions")
local utils = require("telescope.utils")
local Path = require("plenary.path")

vim.keymap.set("n", "<leader>ff", function()
	builtin.git_files({ show_untracked = true })
end, { desc = "Telescope find files" })
vim.keymap.set(
	"n",
	"<leader>fgg",
	builtin.live_grep,
	{ desc = "Telescope live grep" }
)
vim.keymap.set("n", "<leader>fgr", function()
	-- Select a folder to search from, and then search text down from it

	-- The default selection will be the current buffer's folder
	-- relative to the cwd

	local relative_path = Path:new(utils.buffer_dir()):normalize()
	-- Set relative_path to empty if it's just the current directory
	if relative_path == "." then
		relative_path = ""
	end

	builtin.find_files({
		find_command = { "fd", "--type", "d", "--strip-cwd-prefix" },
		prompt_title = "Choose directory to search from",
		default_text = relative_path,
		previewer = false,
		hidden = true,
		attach_mappings = function(prompt_bufnr, map)
			actions.select_default:replace(function()
				-- actions.close(prompt_bufnr)
				local selection =
					require("telescope.actions.state").get_selected_entry()
				-- Open live_grep with the cwd set to the selected directory
				builtin.live_grep({
					cwd = selection.value,
					prompt_title = "Search in " .. selection.value,
				})
			end)
			return true
		end,
	})
end, { desc = "Telescope live grep relative to a directory" })

vim.keymap.set(
	"n",
	"<leader>fb",
	builtin.buffers,
	{ desc = "Telescope buffers" }
)
vim.keymap.set("n", "<leader>fr", function()
	builtin.lsp_references({ include_declaration = false, reuse_win = true })
end, { desc = "Telescope LSP references" })
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
		lsp_references = {},
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
