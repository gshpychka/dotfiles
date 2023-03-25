let g:vista_sidebar_width=20
let g:vista_echo_cursor_strategy = 'floating_win'
let g:vista_default_executive = 'nvim_lsp'
let g:vista#renderer#ctags = 'line'
" autocmd bufenter * if (winnr("$") == 1 && exists("b:NERDTree") && b:NERDTree.isTabTree()) | q | endif

let g:minimap_block_filetypes = ['fugitive', 'vista_kind']

" black fixer
" let g:black_virtualenv = '~/.local/pipx/venvs/black'

" TODO: configure
let g:lightline = {
      \ 'colorscheme': 'gruvbox',
      \ }

let g:tpipeline_focuslost = 0
let g:tpipeline_split = 1
" if has('termguicolors') "true colors
" 	let &t_8f = '\<Esc>[38;2;%lu;%lu;%lum'
" 	let &t_8b = '\<Esc>[48;2;%lu;%lu;%lum'
" 	set termguicolors
" endif

" exec 'luafile' expand(g:config_path . 'lua/nvim-compe.conf.lua')

exec 'luafile' expand(g:config_path . 'lua/nvim-lspconfig.conf.lua')

exec 'luafile' expand(g:config_path . 'lua/nvim-treesitter.conf.lua')
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()

exec 'luafile' expand(g:config_path . 'lua/neoscroll.conf.lua')
exec 'luafile' expand(g:config_path . 'lua/nvim-tree.conf.lua')
exec 'luafile' expand(g:config_path . 'lua/telescope.conf.lua')

" let g:copilot_node_command = "~/.nvm/versions/node/v17.9.1/bin/node"

" lua require'nvim-rooter'.setup()
