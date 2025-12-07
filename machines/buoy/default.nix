{
  config,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ./uptime-kuma.nix
    ./cloudflare-tunnel.nix
  ];

  networking.hostName = "buoy";
  nixpkgs.hostPlatform = "x86_64-linux";
  system.stateVersion = "25.11";

  virtualisation.googleComputeImage.efi = true;

  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableGlobalCompInit = false;
    enableLsColors = false;
  };

  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  security = {
    sudo.enable = true;
    pam = {
      sshAgentAuth.enable = true;
      services.sudo.sshAgentAuth = true;
    };
    # handle auth in NixOS, not GCP
    googleOsLogin.enable = lib.mkForce false;
  };

  users = {
    mutableUsers = false;
    users.${config.my.user} = {
      isNormalUser = true;
      extraGroups = [ "wheel" ];
      openssh.authorizedKeys.keys = [
        config.my.sshKeys.main
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  my.terminfo.enable = true;
}
