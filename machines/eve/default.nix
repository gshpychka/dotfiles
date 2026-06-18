# Bootstrap:
# 1. Create user account
# 2. Sign into the App Store.
# 3. xcode-select --install
# 4. sh <(curl -L https://nixos.org/nix/install)
# 5. git clone https://github.com/gshpychka/dotfiles.git ~/dotfiles && cd ~/dotfiles
# 6. nix --experimental-features "nix-command flakes" build .#darwinConfigurations.eve.system
#    ./result/sw/bin/darwin-rebuild switch --flake .#eve <-- fill fail (expected)
# 7. Set .sops.yaml eve_host to the recipient in /var/log/sops-keygen.log.
# 8. nix shell nixpkgs#sops nixpkgs#gnupg -c find secrets -type f -exec sops updatekeys -y {} \;
# 9. ./result/sw/bin/darwin-rebuild switch --flake .
# 10. 1Password > Developer: enable SSH agent + CLI;

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

  nixpkgs.hostPlatform = "aarch64-darwin";

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

  my.terminfo.enable = true;
  system.stateVersion = 4;
}
