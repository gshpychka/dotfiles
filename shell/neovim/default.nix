# TODO:
# - [ ] Configure nvim-tree
# - [ ] Single statusbar
# - [ ] Configure statusbar contents
# - [ ] Top bar with buffers, tabs, etc

{ config, pkgs, lib, ... }: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins; [
      /* vim-sensible */
      /* vim-surround */
      vim-commentary
      vim-signify
      undotree
      gruvbox-nvim
      plenary-nvim
      harpoon
      vim-fugitive

      lualine-nvim

      /* vista-vim */

      /* vim-tpipeline */

      nvim-tree-lua
      nvim-web-devicons
      vim-devicons

      /* vim-lion */
      neoscroll-nvim

      /* minimap-vim */

      nvim-lspconfig
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

      telescope-nvim
      telescope-fzf-native-nvim
    ];
    extraPackages = with pkgs; [
      # LSP servers
      nodePackages_latest.pyright
      nodePackages_latest.typescript-language-server
      rnix-lsp
      sumneko-lua-language-server


      # Linters and formatters
      nodePackages_latest.prettier
      nodePackages_latest.eslint
      black

      /* fzf */
      ripgrep
      
    ];
    #extraPython3Packages = pyPkgs: with pyPkgs; [ ];
  };
  xdg.configFile.nvim = {
    source = ./config;
    recursive = true;
  };
}
