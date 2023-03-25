" Key mapping
nnoremap <silent> <C-f> :NvimTreeToggle<CR>
" nnoremap <silent> <C-b> :TagbarToggle<CR>
nnoremap <silent> <C-b> :Vista!!<CR>
" clear search highlighting
nnoremap <silent> <esc> :noh<CR><esc>

" move between splits
nnoremap <C-J> <C-W><C-J>
nnoremap <C-K> <C-W><C-K>
nnoremap <C-L> <C-W><C-L>
nnoremap <C-H> <C-W><C-H>

" paste-replace without yanking
vnoremap p "_dPd
