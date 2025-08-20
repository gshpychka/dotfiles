{
  config,
  ...
}:
{
  nix.settings = {
    auto-optimise-store = true;
    # https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
    # 500MB
    download-buffer-size = 524288000;
  };
  nix.gc = {
    dates = "weekly";
    automatic = true;
    options = "--delete-older-than 7d";
  };

  my.distributedBuilds = {
    enable = true;
    servers = [ "reaper" ];
    clientSpeedFactor = 1;
    sshKeyPath = config.sops.secrets.nixbuild-ssh-key.path;
  };

  sops.secrets.nixbuild-ssh-key = {
    sopsFile = ../../secrets/harbor/nixbuild-ssh-key.pem;
    format = "binary";
  };
}
