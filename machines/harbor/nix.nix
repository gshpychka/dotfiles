{
  config,
  ...
}:
{
  nix.settings = {
    auto-optimise-store = true;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };

  my.distributedBuilds = {
    enable = true;
    servers = [ "reaper" ];
    sshKeyPath = config.sops.secrets.nixbuild-ssh-key.path;
  };

  sops.secrets.nixbuild-ssh-key = {
    sopsFile = ../../secrets/harbor/nixbuild-ssh-key.pem;
    format = "binary";
  };
}

