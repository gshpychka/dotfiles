{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.nh;
in
{
  options.my.nh = {
    enable = lib.mkEnableOption "nh - nix helper";
    enableZshIntegration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable zsh integration with 'ns' alias";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.nh = {
      enable = true;
      flake = "${config.home.homeDirectory}/dotfiles";
    };

    programs.zsh.shellAliases = lib.mkIf cfg.enableZshIntegration (
      lib.mkMerge [
        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          ns = "${lib.getExe pkgs.nh} os switch";
        })
        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          ns = "${lib.getExe pkgs.nh} darwin switch";
        })
      ]
    );
  };
}
