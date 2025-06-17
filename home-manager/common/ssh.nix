{
  config,
  lib,
  ...
}:
{
  imports = [
    ../../modules/globals.nix
  ];
  programs = {
    ssh = {
      enable = true;
      extraConfig = ''
        CanonicalizeHostname yes
        CanonicalDomains ${config.my.domain}

        # only canonicalize hosts with no dots
        CanonicalizeMaxDots 0
      '';

      # this is needed because otherwise (if we leave the default value of `false`),
      # our override will not be applied if domain canonicalization happens -
      # since the value will be set on the first pass and first one wins
      # we will set it to false on the second pass
      forwardAgent = true;

      matchBlocks = {

        # orders matters for SSH, since the first value wins (no overrides later)
        # The order of the attrs specified here has no effect on the resulting file
        # because HM orders these as a DAG, so we need to specify the dependencies ourselves

        harbor = lib.hm.dag.entryBefore [ "local" ] {
          match = "final host harbor.${config.my.domain}";
          user = "pi";
        };

        reaper = lib.hm.dag.entryBefore [ "local" ] {
          match = "final host reaper.${config.my.domain}";
          user = "gshpychka";
        };

        hoard = lib.hm.dag.entryBefore [ "local" ] {
          match = "final host hoard.${config.my.domain}";
          user = "gshpychka";
        };

        kodi = lib.hm.dag.entryBefore [ "local" ] {
          match = "final host kodi.${config.my.domain}";
          user = "root";
          forwardAgent = false;
          setEnv = {
            TERM = "xterm-256color";
          };
        };

        local = {
          match = "final host *.${config.my.domain}";
          forwardAgent = true;
        };

        remote = {
          # do not match before canonicalization, if any
          # we can't just use `host` because it would match on the first pass
          # (i.e. before canonicalization)
          # N.B. we need to use `final` as opposed to `canonical`,
          # since the latter will not match if no canonicalization happens
          match = "final host !*.${config.my.domain}";
          # restore the safe default
          forwardAgent = false;
          setEnv = {
            # avoid compatibility issues with Ghostty
            TERM = "xterm-256color";
          };
        };
      };
    };
  };
}
