{
  nix.settings = {
    # https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
    # 2000MB
    download-buffer-size = 2097152000;
  };

  # Reap stale `result` symlinks and per-project `.direnv` dev-shell roots.
  services.angrr = {
    enable = true;
    settings.temporary-root-policies = {
      result = {
        path-regex = "/result[^/]*$";
        period = "3d";
      };
      direnv = {
        path-regex = "/\\.direnv/";
        period = "14d";
      };
    };
  };
}
