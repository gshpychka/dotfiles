local snacks = require("snacks")

-- TODO: enable more features, replace redundant plugins

snacks.setup({
  bigfile = { enabled = true },
  dashboard = { enabled = false }, -- requires lazy.nvim
  indent = {
    enabled = true,
    animate = {
      enabled = false,
    },
    scope = {
      hl = "CursorLineNr",
    },
  },
  input = { enabled = false },    -- using noice.nvim for input dialogs
  notifier = { enabled = false }, -- using noice.nvim for notifications
  quickfile = { enabled = false },
  rename = { enabled = true },
  scroll = { enabled = false },
  statuscolumn = { enabled = false }, -- gitsigns
  words = { enabled = false },
  terminal = {
    enabled = true,
  },
})

-- https://github.com/folke/snacks.nvim/blob/main/docs/rename.md
-- Keybinding for file renaming
vim.keymap.set("n", "<leader>cR", function()
  require("snacks").rename.rename_file()
end, { desc = "Rename File" })

-- nvim-tree integration for rename events
local prev = { new_name = "", old_name = "" } -- Prevents duplicate events
vim.api.nvim_create_autocmd("User", {
  pattern = "NvimTreeSetup",
  callback = function()
    local events = require("nvim-tree.api").events
    events.subscribe(events.Event.NodeRenamed, function(data)
      if prev.new_name ~= data.new_name or prev.old_name ~= data.old_name then
        prev = data
        require("snacks").rename.on_rename_file(data.old_name, data.new_name)
      end
    end)
  end,
})
