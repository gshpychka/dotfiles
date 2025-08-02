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

