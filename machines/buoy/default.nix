{
  config,
  modulesPath,
  lib,
  ...
}:
{
  imports = [
    "${modulesPath}/virtualisation/google-compute-image.nix"
    ./filesystems.nix
    ./gatus.nix
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

  # age key from persistent storage (fetched and written by the bootstrap image)
  sops.age.keyFile = "${config.fileSystems.data.mountPoint}/sops-age-key.txt";

  # handle auth in NixOS, not GCP
  security.googleOsLogin.enable = lib.mkForce false;

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

  services.openssh.enable = true;

  my.terminfo.enable = true;
}
