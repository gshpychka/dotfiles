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

      vim-airline
      vim-airline-themes

      vim-tpipeline

      nvim-tree-lua
      nvim-web-devicons
      vim-devicons

      vim-lion
      neoscroll-nvim

      minimap-vim

      nvim-lspconfig
      nvim-treesitter
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
  };
}
