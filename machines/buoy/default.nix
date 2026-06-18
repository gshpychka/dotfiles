# Bootstrap (from eve):
# cd infra && nix develop ..#infra   # provides tf (terraform + sops-decrypted TF_VARs), gcloud, sops
# gcloud auth login && gcloud auth application-default login
# ./bootstrap/terraform-backend.sh   # new GCP project only: create tf state bucket
# nix build ..#packages.x86_64-linux.gce-image -o result   # bootstrap image .raw.tar.gz
# tf init && tf apply   # age key → Secret Manager, VM, data disk, static IP, DNS
# tf output -raw sops_age_public_key   # → buoy_host (new on first apply / lost tf state)
# if buoy_host changed (repo root): set .sops.yaml buoy_host
#   nix shell nixpkgs#sops nixpkgs#gnupg -c find secrets -type f -exec sops updatekeys -y {} \;   # YubiKey plugged in
#   git commit -am rekey && git push
# nixos-rebuild switch --flake .#buoy --target-host root@buoy   # first deploy: bootstrap image authorizes root only
# redeploy: nixos-rebuild switch --flake .#buoy --target-host buoy --sudo
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

  # age key from persistent storage, fetched and written by the bootstrap image.
  # The filename must match ageKeySecretName in infra/nixos/configuration.nix.
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
