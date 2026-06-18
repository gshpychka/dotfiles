{
  nix.settings = {
    # https://github.com/NixOS/nix/issues/11728#issuecomment-2725297584
    # 2000MB
    download-buffer-size = 2097152000;
  };
}
