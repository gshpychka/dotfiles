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
