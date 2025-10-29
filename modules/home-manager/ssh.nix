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
        extraConfig = ''
          CanonicalizeHostname yes
          CanonicalDomains ${domain}

          # only canonicalize hosts with no dots
          CanonicalizeMaxDots 0
        '';
        enableDefaultConfig = false;

        matchBlocks = {

          # order matters for SSH, since the first value wins (no overrides later)
          # The order of the attrs specified here has no effect on the resulting file
          # because HM orders these as a DAG, so we need to specify the dependencies ourselves

          iso = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host iso.${domain}";
            user = "nixos";
          };

          harbor = lib.hm.dag.entryBefore [ "local" ] {
            match = "final host harbor.${domain}";
            user = "pi";
          };

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
            forwardAgent = false;
            setEnv = {
              # avoid compatibility issues with Ghostty
              TERM = "xterm-256color";
            };
          };
          "*" = {
            addKeysToAgent = "no";
            compression = false;
            serverAliveInterval = 0;
            serverAliveCountMax = 3;
            hashKnownHosts = false;
            userKnownHostsFile = "~/.ssh/known_hosts";
            controlMaster = "no";
            controlPath = "~/.ssh/master-%r@%n:%p";
            controlPersist = "no";
          };
        };
      };
    };
  };
}
