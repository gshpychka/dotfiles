{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.sops;
  keyCommands = {
    host-key = "sudo ${lib.getExe pkgs.ssh-to-age} -private-key -i /etc/ssh/ssh_host_ed25519_key";
    "1password" = "op read --account my.1password.com op://dev/sops-age-glib-op/credential";
  };
in
{
  options.my.sops = {
    enable = lib.mkEnableOption "the sops CLI";
    ageIdentity = lib.mkOption {
      type = lib.types.nullOr (lib.types.enum (lib.attrNames keyCommands));
      default = null;
      description = "Where the sops CLI gets its age identity at runtime; null leaves it to sops' own key lookup.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.sops ];
    home.sessionVariables = lib.mkIf (cfg.ageIdentity != null) {
      SOPS_AGE_KEY_CMD = keyCommands.${cfg.ageIdentity};
    };
  };
}
