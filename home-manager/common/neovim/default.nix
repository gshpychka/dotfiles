{pkgs, ...}:
# gitlab-nvim builds its own binary, which is not supported with nix
let
  # gitlab-nvim = pkgs.vimUtils.buildVimPlugin {
  #   name = "gitlab-nvim";
  #   src = pkgs.fetchFromGitHub {
  #     owner = "harrisoncramer";
  #     repo = "gitlab.nvim";
  #     rev = "v2.6.4";
  #     hash = "sha256-1RI8I0V/QeS1cdXHtERGiZFqX6a9hwZp8L4JYayzWm0=";
  #   };
  # };
in {
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

      # git-related plugins
      vim-fugitive
      gitsigns-nvim
      diffview-nvim
      gitlinker-nvim
      agitator-nvim

      # decorated scrollbar
      satellite-nvim
      hydra-nvim
      barbar-nvim
      lualine-nvim
      vim-tmux-navigator
      nvim-tree-lua
      nvim-web-devicons
      # noice requires nui-nvim and nvim-notify
      nui-nvim
      nvim-notify
      noice-nvim
      inc-rename-nvim
      indent-blankline-nvim
      text-case-nvim
      nvim-lspconfig
      flash-nvim
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
          vimdoc
          yaml
          wing
          markdown
          markdown_inline
        ]))
      neogen
      luasnip
      # nvim-lightbulb
      supermaven-nvim
      lspkind-nvim
      nvim-cmp
      cmp-nvim-lsp
      cmp-nvim-lua
      cmp-buffer
      telescope-nvim
      telescope-fzf-native-nvim
      telescope-ui-select-nvim
      typescript-tools-nvim
      tsc-nvim
    ];
    extraPackages = with pkgs; [
      # LSP servers
      nodePackages_latest.typescript-language-server
      pyright
      nil
      lua-language-server
      zls
      bash-language-server
      yaml-language-server
      vscode-langservers-extracted # eslint, json
      nodePackages_latest.dockerfile-language-server-nodejs

      # Linters and formatters
      yamlfmt
      python311Packages.autopep8
      python311Packages.flake8
      black
      isort
      alejandra
      stylua
      shfmt

      ripgrep
    ];
    #extraPython3Packages = pyPkgs: with pyPkgs; [ ];
  };
  xdg.configFile.nvim = {
    source = ./config;
    recursive = true;
  };
}
