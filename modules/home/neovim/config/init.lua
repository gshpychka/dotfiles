vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1

vim.loader.enable()

vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.signcolumn = "yes"
vim.opt.numberwidth = 3
vim.opt.statuscolumn = "%=%{v:virtnum < 1 ? (v:relnum ? v:relnum : v:lnum < 10 ? v:lnum . '  ' : v:lnum) : ''}%=%s"

vim.opt.expandtab = true
vim.opt.tabstop = 2
-- stylua uses tabs
-- black uses 4 spaces
vim.api.nvim_exec(
  [[
  autocmd FileType python setlocal tabstop=4
]],
  false
)

-- make Tab characters visible
vim.opt.list = true

-- softtabstop and shiftwidth follow tabstop
vim.opt.softtabstop = 0
vim.opt.shiftwidth = 0

vim.opt.shiftround = true

vim.opt.smartindent = true

vim.opt.wrap = false

vim.opt.undodir = os.getenv("HOME") .. "/.nvim/undodir"
vim.opt.undofile = true

vim.opt.swapfile = false

vim.opt.hlsearch = false
vim.opt.incsearch = true
vim.opt.wrapscan = true

vim.opt.updatetime = 8
vim.opt.ttyfast = true

vim.opt.hidden = true
vim.opt.display = "lastline"
vim.opt.cmdheight = 0
vim.opt.foldenable = false
vim.opt.scrolloff = 15
vim.opt.colorcolumn = "120"
vim.opt.smartcase = true
vim.opt.showmode = false
vim.o.foldenable = false
vim.o.splitright = true
vim.o.splitbelow = true

vim.filetype.add({
  extension = {
    w = "wing",
  },
})
require("config")
