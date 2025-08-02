local snacks = require("snacks")

-- TODO: enable more features, replace redundant plugins

snacks.setup({
  bigfile = { enabled = true },
  dashboard = { enabled = false }, -- requires lazy.nvim
  indent = { enabled = true },
  input = { enabled = false },     -- using noice.nvim for input dialogs
  notifier = { enabled = false },  -- using noice.nvim for notifications
  quickfile = { enabled = false },
  scroll = { enabled = false },
  statuscolumn = { enabled = false }, -- gitsigns
  words = { enabled = false },
  terminal = {
    enabled = true,
  },
})

