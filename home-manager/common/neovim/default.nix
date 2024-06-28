{pkgs, ...}:
# gitlab-nvim builds its own binary, which is not supported with nix
# let
# gitlab-nvim = pkgs.vimUtils.buildVimPlugin {
#   name = "gitlab-nvim";
#   src = pkgs.fetchFromGitHub {
#     owner = "harrisoncramer";
#     repo = "gitlab.nvim";
#     rev = "v2.6.4";
#     hash = "sha256-1RI8I0V/QeS1cdXHtERGiZFqX6a9hwZp8L4JYayzWm0=";
#   };
# };
# in
{
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

      nvim-tree-lua
      nvim-web-devicons

      neoscroll-nvim

      # noice requires nui-nvim and nvim-notify
      nui-nvim
      nvim-notify
      noice-nvim

      inc-rename-nvim
      indent-blankline-nvim
      text-case-nvim

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
          vimdoc
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
      vscode-langservers-extracted # eslint
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
