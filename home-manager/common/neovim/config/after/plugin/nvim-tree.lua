require("nvim-tree").setup({
  hijack_netrw = true,
  hijack_cursor = true,
  sort_by = "case_sensitive",
  view = {
    width = 50,
  },
  diagnostics = {
    enable = true,
    show_on_dirs = true,
    show_on_open_dirs = false,
    severity = {
      min = vim.diagnostic.severity.ERROR,
    },
  },
  renderer = {
    group_empty = true,
    icons = {
      glyphs = {
        git = {
          unstaged = "󱇨", -- ✗ 󰷈 󰩌 󱪘 󱇧 󰩋
          staged = "󰸩", -- ✓ 󰩎 󱧇 󱪙 󰩍 󰈖
          unmerged = "", -- 󰢪 󱀶
          renamed = "󱀱", -- ➜ 󰬳 󱀹 󰪹
          untracked = "󰻭", -- 󰝒 󱪝 󱪞
          deleted = "󱀷", -- 󱪟 󱪛 󱪢 󱪠 󱪜 󰮘
          ignored = "󰘓", -- ◌ 󰷇 󰷆
        },
      },
    },
  },
  sync_root_with_cwd = true,
  reload_on_bufenter = true,
  update_focused_file = {
    enable = true,
  },
  filters = {
    dotfiles = false,
    custom = {
      "^.git$",
    },
  },
})

local api = require("nvim-tree.api")
vim.keymap.set("n", "<C-f>", api.tree.toggle, { desc = "nvim-tree toggle" })
