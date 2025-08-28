{
  config,
  lib,
  osConfig,
  ...
}:
let
  cfg = config.my.ssh;
  domain = osConfig.my.domain;
in
{
  options.my.ssh = {
    enable = lib.mkEnableOption "SSH client configuration";
  };

  config = lib.mkIf cfg.enable {
    programs = {
      ssh = {
        enable = true;
        enableDefaultConfig = false;
        extraConfig = ''
          CanonicalizeHostname yes
          # only canonicalize hosts with no dots
          CanonicalizeMaxDots 0
          CanonicalDomains ${domain}
        '';

        matchBlocks = {
          "*" = {
            # this is needed because otherwise (if we leave the default value of `false`),
            # our override will not be applied if domain canonicalization happens -
            # since the value will be set on the first pass and first one wins
            # we will set it to false on the second pass
            # TODO: investigate
            # forwardAgent = true;

            # preserve default config after https://github.com/nix-community/home-manager/pull/7655
            compression = false;
            addKeysToAgent = "no";
            hashKnownHosts = false;
            serverAliveInterval = 0;
            serverAliveCountMax = 3;
            userKnownHostsFile = "${config.home.homeDirectory}/.ssh/known_hosts";
            controlPath = "${config.home.homeDirectory}/.ssh/master-%r@%h:%p";
            controlMaster = "no";
            controlPersist = "no";
          };

          # orders matters for SSH, since the first value wins (no overrides later)
          # The order of the attrs specified here has no effect on the resulting file
          # because HM orders these as a DAG, so we need to specify the dependencies ourselves

          harbor = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host harbor.${domain}";
            user = "pi";
          };

          # these two are for future use - no custom config for now
          reaper = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host reaper.${domain}";
          };
          hoard = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host hoard.${domain}";
          };

          kodi = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host kodi.${domain}";
            user = "root";
            forwardAgent = false;
            setEnv = {
              TERM = "xterm-256color";
            };
          };

          local = {
            match = "final host *.${domain}";
            user = osConfig.my.user;
            forwardAgent = true;
          };

          remote = {
            # do not match before canonicalization, if any
            # we can't just use `host` because it would match on the first pass
            # (i.e. before canonicalization)
            # N.B. we need to use `final` as opposed to `canonical`,
            # since the latter will not match if no canonicalization happens
            match = "final host !*.${domain}";
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
  };
}
