{ lib, ... }:
{
  # mkOverride 900: wins over upstream modules' own mkDefault values (e.g. the
  # GCE image module sets PermitRootLogin = mkDefault "prohibit-password"),
  # while still losing to any explicit per-machine setting.
  services.openssh.settings = {
    PasswordAuthentication = lib.mkOverride 900 false;
    KbdInteractiveAuthentication = lib.mkOverride 900 false;
    PermitRootLogin = lib.mkOverride 900 "no";
  };

  security = {
    sudo = {
      enable = lib.mkDefault true;
      # let `sudo -n` authenticate via PAM instead of failing outright
      # when no timestamp is cached
      extraConfig = "Defaults noninteractive_auth";
    };
    pam = {
      sshAgentAuth.enable = lib.mkDefault true;
      services.sudo.sshAgentAuth = lib.mkDefault true;
    };
  };
}
