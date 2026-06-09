{
  config,
  ...
}:
{
  nix.settings = {
    # https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
    # 1000MB
    download-buffer-size = 1048576000;
  };

  my.distributedBuilds = {
    enable = true;
    servers = [ "reaper" ];
    sshKeyPath = config.sops.secrets.nixbuild-ssh-key.path;
    clientSpeedFactor = 10;
  };

  sops.secrets.nixbuild-ssh-key = {
    sopsFile = ../../secrets/hoard/nixbuild-ssh-key.pem;
    format = "binary";
  };
}
