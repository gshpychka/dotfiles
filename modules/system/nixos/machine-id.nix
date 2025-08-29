{
  config,
  lib,
  ...
}:
with lib;
let
  cfg = config.my.generic-machine-id;
  # https://madaidans-insecurities.github.io/guides/linux-hardening.html#machine-id
  machine-id = "b08dfa6083e7567a1921a715000001fb";
in
{
  options.my.generic-machine-id = {
    enable = mkEnableOption "Set the machine-id to the Whonix ID";
  };

  config = mkIf cfg.enable {
    # https://www.man7.org/linux/man-pages/man5/machine-id.5.html
    boot.kernelParams = [ "systemd.machine_id=${machine-id}" ];
    # kernel param takes precedence over /etc/machine-id, but we set both
    environment.etc."machine-id".text = machine-id;
  };
}
