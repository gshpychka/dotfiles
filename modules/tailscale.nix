{ config, lib, ... }:

let
  cfg = config.my.tailscale;
in
{
  options.my.tailscale = {
    enable = lib.mkEnableOption "Tailscale integration";
    ssh = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable Tailscale SSH support";
    };
  };

  config = lib.mkIf cfg.enable {
    # Secret containing an auth key for this machine
    sops.secrets."tailscale-auth-key" = {
      sopsFile = ../secrets/common/tailscale.yaml;
      key = "tailscale-auth-key";
      restartUnits = [ config.systemd.services.tailscaled-autoconnect.name ];
    };

    services.tailscale = {
      enable = true;
      extraUpFlags = lib.mkIf cfg.ssh [ "--ssh" ];
      authKeyFile = config.sops.secrets."tailscale-auth-key".path;
    };

    networking.firewall.interfaces.${config.services.tailscale.interfaceName}.allowedTCPPorts =
      # just the tailscale interface
      lib.mkIf cfg.ssh [ 22 ];
  };
}
