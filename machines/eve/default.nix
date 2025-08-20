# printf 'run\tprivate/var/run\n' | sudo tee -a /etc/synthetic.conf
# /System/Library/Filesystems/apfs.fs/Contents/Resources/apfs.util -t
# nix --experimental-features "nix-command flakes" build ".#darwinConfigurations.eve.system"
# ./result/sw/bin/darwin-rebuild switch --flake ".#eve"

{
  config,
  pkgs,
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
    ./secrets.nix
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
    # yubikey
    enable = true;
  };

  my.distributedBuilds = {
    enable = true;
    servers = [ "reaper" ];
    clientSpeedFactor = 50;
    sshKeyPath = config.sops.secrets.nixbuild-ssh-key.path;
  };
  system.stateVersion = 4;
}
