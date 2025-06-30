# printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
# /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
# nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
# ./result/sw/bin/darwin-rebuild switch --flake ".#eve"

{
  config,
  pkgs,
  lib,
  ...
}:
{
  imports = [
    ./system.nix
    ./window-management.nix
    ./homebrew.nix
    ./nix.nix
    ./1password.nix
    ./home.nix
  ];

  networking = {
    hostName = "eve";
    computerName = "Eve";
  };

  users.users.${config.my.user} = {
    home = "/Users/${config.my.user}";
    shell = pkgs.zsh;
  };

  programs.gnupg.agent = {
    # yubkikey
    enable = true;
  };

  sops = {
    age.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys
    gnupg.sshKeyPaths = lib.mkForce [ ]; # Override default Darwin SSH keys for GPG
    gnupg.home = "/Users/${config.my.user}/.gnupg";
    secrets.nixbuild-ssh-key = {
      sopsFile = ../../secrets/eve/nixbuild-ssh-key.pem;
      format = "binary";
    };
  };

  my.distributedBuilds = {
    enable = true;
    servers = [ "reaper" ];
    sshKeyPath = config.sops.secrets.nixbuild-ssh-key.path;
  };

  system.stateVersion = 4;
}
