{ lib, ... }:
# Baseline SSH/sudo hardening shared by every NixOS machine.
# Everything is mkDefault so individual machines can override;
# services.openssh.enable itself stays per-machine.
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
    sudo.enable = lib.mkDefault true;
    # authenticate sudo via the forwarded SSH agent
    pam = {
      sshAgentAuth.enable = lib.mkDefault true;
      services.sudo.sshAgentAuth = lib.mkDefault true;
    };
  };
}
