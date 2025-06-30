{ config, lib, pkgs, ... }:
let
  cfg = config.my.btop;
in
{
  options.my.btop = {
    enable = lib.mkEnableOption "btop system monitor";
  };

  config = lib.mkIf cfg.enable {
    programs.btop = {
      enable = true;
      settings = {
        color_theme = "${pkgs.btop}/share/btop/themes/gruvbox_dark_v2.theme";
        vim_keys = true;
        update_ms = 100;
        proc_tree = true;
        disks_filter = "exclude=/boot";
        io_mode = true;
        net_download = 1000;
        net_upload = 1000;
        net_auto = false;
      };
    };
  };
}