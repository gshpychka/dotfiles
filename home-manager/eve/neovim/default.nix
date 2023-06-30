# TODO:
# - [ ] Configure nvim-tree
# - [ ] Single statusbar
# - [ ] Configure statusbar contents
# - [ ] Top bar with buffers, tabs, etc
{
  config,
  pkgs,
  lib,
  ...
}: let
  # flash-nvim = pkgs.vimUtils.buildVimPluginFrom2Nix {
  #   name = "flash-nvim";
  #   src = pkgs.fetchFromGitHub {
  #     owner = "folke";
  #     repo = "flash.nvim";
  #     rev = "v1.3.0";
  #     hash = "sha256-JQIvB3il5UT4P8XTJ3da9uywDwkd4l7rTKGFq43KpEg=";
  #   };
  # };
  eyeliner-nvim = pkgs.vimUtils.buildVimPluginFrom2Nix {
    name = "eyeliner-nvim";
    src = pkgs.fetchFromGitHub {
      owner = "jinh0";
      repo = "eyeliner.nvim";
      rev = "fa3a0986cb072fe2ab29ef79e022514d2533f0db";
      hash = "sha256-W1BoT5sUFWvAAZIHSLtQJ6G8rk2v6Xv5E+drMOy1WBw=";
    };
  };
in {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins;
      [
        # vim-sensible
        # vim-surround
        comment-nvim
        vim-signify
        undotree
        gruvbox-nvim
        plenary-nvim
        harpoon
        vim-fugitive
        gitsigns-nvim
        which-key-nvim

        lualine-nvim
        vim-tpipeline
        vim-tmux-navigator

        # vista-vim

        # vim-tpipeline

        nvim-tree-lua
        nvim-web-devicons
        vim-devicons

        # vim-lion
        neoscroll-nvim

        # minimap-vim

        nvim-lspconfig
        (nvim-treesitter.withPlugins (p:
          with p; [
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
          ]))
        luasnip
        nvim-lightbulb

        # copilot-lua
        # copilot-cmp
        nvim-cmp
        cmp-nvim-lsp
        cmp-nvim-lua
        cmp-buffer

        null-ls-nvim
        nvim-lsp-ts-utils

        telescope-nvim
        telescope-fzf-native-nvim
        telescope-ui-select-nvim
      ]
      ++ [
        # flash-nvim
        eyeliner-nvim
      ];
    extraPackages = with pkgs; [
      # LSP servers
      nodePackages_latest.pyright
      nodePackages_latest.typescript-language-server
      nil
      sumneko-lua-language-server

      # Linters and formatters
      nodePackages_latest.prettier
      nodePackages_latest.eslint_d
      nodePackages_latest.jsonlint
      yamlfmt
      autoflake
      python311Packages.autopep8
      python311Packages.flake8
      black
      isort
      statix
      alejandra
      stylua

      # fzf
      ripgrep
    ];
    #extraPython3Packages = pyPkgs: with pyPkgs; [ ];
  };
  xdg.configFile.nvim = {
    source = ./config;
    recursive = true;
  };
}
