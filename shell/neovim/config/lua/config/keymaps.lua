vim.g.mapleader = " "
vim.keymap.set('n', '<C-J>', '<C-W><C-J>', {noremap = true, desc = "Move to the split below the current one"})
vim.keymap.set('n', '<C-K>', '<C-W><C-K>', {noremap = true, desc = "Move to the split above the current one"})
vim.keymap.set('n', '<C-L>', '<C-W><C-L>', {noremap = true, desc = "Move to the split to the right of the current one"})
vim.keymap.set('n', '<C-H>', '<C-W><C-H>', {noremap = true, desc = "Move to the split to the left of the current one"})

vim.keymap.set('v', 'p', '"_dPd', {noremap = true, desc = "Paste without yanking"})
