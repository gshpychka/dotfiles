{ lib, ... }:

{
  options = {
    shared.harborUsername = lib.mkOption {
      type = lib.types.str;
      default = "pi";
      description = "Username for Harbor";
    };

    shared.harborSshPort = lib.mkOption {
      type = lib.types.int;
      default = 420;
      description = "Port for Harbor SSH";
    };

    shared.harborHost = lib.mkOption {
      type = lib.types.str;
      default = "harbor";
      description = "Host name for Harbor";
    };

    shared.localDomain = lib.mkOption {
      type = lib.types.str;
      default = "lan";
      description = "Local domain for LAN";
    };
  };

  config = { };
}



