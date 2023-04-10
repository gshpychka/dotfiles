vim.g.mapleader = " "
vim.keymap.set('n', '<C-J>', '<C-W><C-J>', {noremap = true, desc = "Move to the split below the current one"})
vim.keymap.set('n', '<C-K>', '<C-W><C-K>', {noremap = true, desc = "Move to the split above the current one"})
vim.keymap.set('n', '<C-L>', '<C-W><C-L>', {noremap = true, desc = "Move to the split to the right of the current one"})
vim.keymap.set('n', '<C-H>', '<C-W><C-H>', {noremap = true, desc = "Move to the split to the left of the current one"})

vim.keymap.set('v', 'p', '"_dP', {noremap = true, desc = "Paste without yanking"})
vim.keymap.set({'n', 'v'}, '<leader>y', '"+y', {noremap = true, desc = "Yank into system clipboard"})

vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection up" })
vim.keymap.set("v", "K", ":m '<-1<CR>gv=gv", { desc = "Move selection down" })

vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Move down and keep cursor in the middle" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Move up and keep cursor in the middle" })

vim.keymap.set("n", "n", "nzzzv", { desc = "Next result in the middle of the screen" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Previous result in the middle of the screen" })
