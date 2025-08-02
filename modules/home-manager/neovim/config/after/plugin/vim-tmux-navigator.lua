-- Normal mode mappings
vim.keymap.set(
  "n",
  "<C-h>",
  ":<C-U>TmuxNavigateLeft<cr>",
  { noremap = true, silent = true, desc = "Move left with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<C-j>",
  ":<C-U>TmuxNavigateDown<cr>",
  { noremap = true, silent = true, desc = "Move down with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<C-k>",
  ":<C-U>TmuxNavigateUp<cr>",
  { noremap = true, silent = true, desc = "Move up with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<C-l>",
  ":<C-U>TmuxNavigateRight<cr>",
  { noremap = true, silent = true, desc = "Move right with tmux-navigator" }
)

-- Terminal mode mappings
vim.keymap.set(
  "t",
  "<C-h>",
  "<C-\\><C-n>:<C-U>TmuxNavigateLeft<cr>",
  { noremap = true, silent = true, desc = "Move left with tmux-navigator from terminal" }
)
vim.keymap.set(
  "t",
  "<C-j>",
  "<C-\\><C-n>:<C-U>TmuxNavigateDown<cr>",
  { noremap = true, silent = true, desc = "Move down with tmux-navigator from terminal" }
)
vim.keymap.set(
  "t",
  "<C-k>",
  "<C-\\><C-n>:<C-U>TmuxNavigateUp<cr>",
  { noremap = true, silent = true, desc = "Move up with tmux-navigator from terminal" }
)
vim.keymap.set(
  "t",
  "<C-l>",
  "<C-\\><C-n>:<C-U>TmuxNavigateRight<cr>",
  { noremap = true, silent = true, desc = "Move right with tmux-navigator from terminal" }
)
