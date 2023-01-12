" Key mapping
nnoremap <silent> <C-f> :NvimTreeToggle<CR>
" nnoremap <silent> <C-b> :TagbarToggle<CR>
nnoremap <silent> <C-b> :Vista!!<CR>
" switch buffer if focused on NERDTree and bring up FZF
" nnoremap <silent> <expr> <C-t> (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":FZF\<cr>"
" nnoremap <silent> <expr> <C-r> (expand('%') =~ 'NERD_tree' ? "\<c-w>\<c-w>" : '').":Rg\<cr>"
" clear search highlighting
nnoremap <silent> <esc> :noh<CR><esc>

" inoremap <silent><expr> <C-Space> compe#complete()
" inoremap <silent><expr> <CR>      compe#confirm('<CR>')
" inoremap <silent><expr> <C-e>     compe#close('<C-e>')
" inoremap <silent><expr> <C-f>     compe#scroll({ 'delta': +4 })
" inoremap <silent><expr> <C-d>     compe#scroll({ 'delta': -4 })

" move between splits
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" paste-replace without yanking
vnoremap p "_dP