{ lib, ... }:

# Global configuration options.
{
  options.my.domain = lib.mkOption {
    type = lib.types.str;
    default = "glib.sh";
    description = "Public domain name";
  };
}
