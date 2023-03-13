# TODO:
# - [ ] Configure nvim-tree
# - [ ] Single statusbar
# - [ ] Configure statusbar contents
# - [ ] fzf file opening
# - [ ] fzf buffer switching
# - [ ] fzf ripgrep
# - [ ] Top bar with buffers, tabs, etc
# - [ ] Smooth scrolling for jk

{ config, pkgs, lib, ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins; [
      vim-sensible
      vim-surround
      vim-commentary
      vim-signify
      gruvbox-nvim
      plenary-nvim

      lightline-vim

      vista-vim

      vim-tpipeline

      nvim-tree-lua
      nvim-web-devicons
      vim-devicons

      vim-lion
      neoscroll-nvim

      minimap-vim

      nvim-lspconfig
      # nvim-treesitter.withAllGrammars
      (nvim-treesitter.withPlugins (p: with p; [
        bash
        comment
        dockerfile
        html
        javascript
        json
        lua
        nix
        python
        regex
        rust
        sql
        toml
        typescript
        vim
        yaml
        ]
      ))
      cmp-nvim-lsp
      cmp-buffer
      nvim-cmp
      null-ls-nvim
      nvim-lsp-ts-utils
    ];
    extraPackages = with pkgs; [
      # LSP servers
      nodePackages_latest.pyright
      nodePackages_latest.typescript-language-server
      rnix-lsp

      # Linters and formatters
      nodePackages_latest.prettier
      nodePackages_latest.eslint
      black

      fzf
      ripgrep
      
    ];
    #extraPython3Packages = pyPkgs: with pyPkgs; [ ];
    extraConfig = ''
" Disable netrw
let g:loaded_netrw = 1
let g:loaded_netrwPlugin = 1

let g:config_path = '~/.config/nvim/'

func LoadConfig(filename)
    exec 'source' g:config_path . a:filename
endfunc

if !exists('g:vscode')
    call LoadConfig('plugin-settings.vim')
    call LoadConfig('keymaps.vim')
endif

set completeopt=menu,menuone,noselect
set updatetime=10
set number relativenumber
set expandtab           " Use spaces instead of tabs
set tabstop=4           " Tab indents by 4 spaces
set shiftwidth=4        " >> indents by 4 spaces
set shiftround          " Round the number of spaces
set autoindent          " Keep indentation
set hidden              " Switch between buffers without having to save first
set display=lastline    " Show as much as possible of the last line
set ttyfast             " Faster redrawing
set lazyredraw          " Only redraw when necessary
set wrapscan            " Searches wrap around EOF
set cmdheight=1
set foldlevelstart=9
set scrolloff=15
set colorcolumn=88
set smartcase
set nosmd               " Do not show mode in command line
syntax enable

" Colorscheme
" let g:gruvbox_termcolors=256
let g:gruvbox_contrast_dark='hard'
let g:gruvbox_bold=0
" set t_Co=256
set termguicolors
set background=dark
colorscheme gruvbox

hi link DiagnosticError GruvboxRedSign
hi link DiagnosticInformation GruvboxYellowSign
hi link DiagnosticWarning GruvboxOrangeSign
hi link DiagnosticHint GruvboxBlueSign

hi! link LspDiagnosticsDefaultError DiagnosticError
hi! link LspDiagnosticsDefaultInformation DiagnosticInformation
hi! link LspDiagnosticsDefaultWarning DiagnosticWarning
hi! link LspDiagnosticsDefaultHint DiagnosticHint

hi LspReferenceRead guibg='#665c54' guifg=none
hi LspReferenceText guibg='#665c54' guifg=none
hi LspReferenceWrite guibg='#665c54' guifg=none

" undercurl not supported in alacritty
hi LspDiagnosticsUnderlineError cterm=undercurl gui=undercurl guisp=#fb4934

" Allow `//` comments in json
autocmd FileType json syntax match Comment +\/\/.\+$+

set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --follow

" Fix matching parenthesis highlighting
" hi MatchParen ctermfg=208 ctermbg=bg
  '';
  };
  xdg.configFile.nvim = {
    source = ./config;
    recursive = true;
  };
}
