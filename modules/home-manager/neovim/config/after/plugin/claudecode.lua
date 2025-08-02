-- https://github.com/coder/claudecode.nvim/
require("claudecode").setup({
  -- Auto start Claude Code when opening Neovim
  auto_start = true,

  -- Terminal configuration
  terminal = {
    split_side = "right",
    split_width_percentage = 0.45,
    provider = "snacks",
    snacks_win_opts = {
      -- TODO: disable title
    },
    auto_close = true
  },
  -- Diff configuration
  diff_opts = {
    auto_close_on_accept = true,
    vertical_split = true
  }
})

-- Key mappings
vim.keymap.set("n", "<leader>cc", "<cmd>ClaudeCode<cr>", { desc = "Toggle Claude" })
vim.keymap.set("n", "<leader>cf", "<cmd>ClaudeCodeFocus<cr>", { desc = "Focus Claude" })
vim.keymap.set("n", "<leader>cs", "<cmd>ClaudeCodeSend<cr>", { desc = "Send to Claude" })
vim.keymap.set("v", "<leader>cs", "<cmd>ClaudeCodeSend<cr>", { desc = "Send selection to Claude" })
