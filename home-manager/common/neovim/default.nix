{pkgs, ...}: {
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    vimAlias = true;
    withNodeJs = true;
    withPython3 = true;
    plugins = with pkgs.vimPlugins; [
      # vim-sensible
      # vim-surround
      undotree
      gruvbox-nvim
      plenary-nvim

      vim-fugitive
      gitsigns-nvim
      diffview-nvim
      gitlinker-nvim

      # decorated scrollbar
      satellite-nvim

      # which-key-nvim
      hydra-nvim

      barbar-nvim
      lualine-nvim
      vim-tmux-navigator

      # nvim-bqf

      # vista-vim

      nvim-tree-lua
      nvim-web-devicons

      # vim-lion
      neoscroll-nvim

      # noice requires nui-nvim and nvim-notify
      # nui-nvim
      # nvim-notify
      # noice-nvim

      inc-rename-nvim
      # leap-nvim
      # peek-nvim
      indent-blankline-nvim

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
          wing
          markdown
          markdown_inline
        ]))
      neogen
      luasnip
      # nvim-lightbulb

      copilot-lua
      copilot-cmp
      lspkind-nvim
      nvim-cmp
      cmp-nvim-lsp
      cmp-nvim-lua
      cmp-buffer

      null-ls-nvim
      # nvim-lsp-ts-utils

      telescope-nvim
      telescope-fzf-native-nvim
      telescope-ui-select-nvim
      typescript-tools-nvim
    ];
    extraPackages = with pkgs; [
      # LSP servers
      nodePackages_latest.typescript-language-server
      pyright
      nil
      lua-language-server
      zls

      # Linters and formatters
      vscode-langservers-extracted
      nodePackages_latest.prettier
      nodePackages_latest.jsonlint
      nodePackages_latest.fixjson
      yamlfmt
      autoflake
      python311Packages.autopep8
      python311Packages.flake8
      black
      isort
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