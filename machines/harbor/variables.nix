{lib, ...}: {
  options = {
    shared.harborUsername = lib.mkOption {
      type = lib.types.str;
      default = "pi";
      description = "Username for Harbor";
    };
  };

  config = {};
}
