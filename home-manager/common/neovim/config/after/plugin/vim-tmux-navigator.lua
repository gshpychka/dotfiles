vim.keymap.set(
  "n",
  "<m-h>",
  ":<C-U>TmuxNavigateLeft<cr>",
  { noremap = true, silent = true, desc = "Move left with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<m-j>",
  ":<C-U>TmuxNavigateDown<cr>",
  { noremap = true, silent = true, desc = "Move down with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<m-k>",
  ":<C-U>TmuxNavigateUp<cr>",
  { noremap = true, silent = true, desc = "Move up with tmux-navigator" }
)
vim.keymap.set(
  "n",
  "<m-l>",
  ":<C-U>TmuxNavigateRight<cr>",
  { noremap = true, silent = true, desc = "Move right with tmux-navigator" }
)
