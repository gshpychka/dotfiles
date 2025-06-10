{ config, lib, pkgs, ... }:

with lib;

let
  languageModules = {
    bash = ./languages/bash.nix;
    docker = ./languages/docker.nix;
    json = ./languages/json.nix;
    lua = ./languages/lua.nix;
    nix = ./languages/nix.nix;
    python = ./languages/python.nix;
    typescript = ./languages/typescript.nix;
    yaml = ./languages/yaml.nix;
    zig = ./languages/zig.nix;
  };

  cfg = config.my.neovim;

  treeSitterPlugin = pkgs.vimPlugins.nvim-treesitter.withPlugins (
    p: map (lang: builtins.getAttr lang p) cfg.treeSitterLanguages
  );

  basePlugins = with pkgs.vimPlugins; [
    undotree
    gruvbox-nvim
    plenary-nvim
    vim-fugitive
    gitsigns-nvim
    diffview-nvim
    gitlinker-nvim
    agitator-nvim
    satellite-nvim
    hydra-nvim
    barbar-nvim
    lualine-nvim
    vim-tmux-navigator
    nvim-tree-lua
    nvim-web-devicons
    nui-nvim
    nvim-notify
    noice-nvim
    inc-rename-nvim
    indent-blankline-nvim
    text-case-nvim
    nvim-lspconfig
    flash-nvim
    treeSitterPlugin
    neogen
    luasnip
    supermaven-nvim
    lspkind-nvim
    nvim-cmp
    cmp-nvim-lsp
    cmp-nvim-lua
    cmp-buffer
    telescope-nvim
    telescope-fzf-native-nvim
    telescope-ui-select-nvim
  ];

in {
  imports = builtins.attrValues languageModules;

  options.my.neovim = {
    enable = mkEnableOption "Neovim configuration";

    languages = mkOption {
      type = types.listOf (types.enum (builtins.attrNames languageModules));
      default = [];
      description = "Languages to enable LSP support for.";
      example = [ "nix" "lua" "typescript" ];
    };

    treeSitterLanguages = mkOption {
      type = types.listOf types.str;
      default = [];
      internal = true;
    };

    languagePackages = mkOption {
      type = types.listOf types.package;
      default = [];
      internal = true;
    };

    extraPlugins = mkOption {
      type = types.listOf types.package;
      default = [];
      internal = true;
    };
  };

  config = mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      vimAlias = true;
      withNodeJs = true;
      withPython3 = true;
      plugins = basePlugins ++ cfg.extraPlugins;
      extraPackages = with pkgs; [
        ripgrep
        nixfmt-rfc-style
      ] ++ cfg.languagePackages;
    };

    xdg.configFile.nvim = {
      source = ../../common/neovim/config;
      recursive = true;
    };

    xdg.configFile."nvim/lua/lsp/languages.lua".text =
      "return { " + (lib.concatMapStringsSep ", " (l: "\"${l}\"") cfg.languages) + " }";
  };
}
