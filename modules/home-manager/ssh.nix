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

        settings = {

          # order matters for SSH, since the first value wins (no overrides later)
          # The order of the attrs specified here has no effect on the resulting file
          # because HM orders these as a DAG, so we need to specify the dependencies ourselves
          # Short attr names are used (rather than literal `Match ...` keys) so the DAG
          # references stay stable and readable.

          iso = lib.hm.dag.entryBefore [ "local" ] {
            header = "Match final host iso.${domain}";
            User = "nixos";
          };

          harbor = lib.hm.dag.entryBefore [ "local" ] {
            header = "Match final host harbor.${domain}";
            User = "pi";
          };

          reaper = lib.hm.dag.entryBefore [ "local" ] {
            header = "Match final host reaper.${domain}";
          };

          hoard = lib.hm.dag.entryBefore [ "local" ] {
            header = "Match final host hoard.${domain}";
          };

          kodi = lib.hm.dag.entryBefore [ "local" ] {
            header = "Match final host kodi.${domain}";
            User = "root";
            ForwardAgent = false;
            SetEnv = {
              TERM = "xterm-256color";
            };
          };

          local = {
            header = "Match final host *.${domain}";
            User = osConfig.my.user;
            ForwardAgent = true;
          };

          remote = {
            # do not match before canonicalization, if any
            # we can't just use `host` because it would match on the first pass
            # (i.e. before canonicalization)
            # N.B. we need to use `final` as opposed to `canonical`,
            # since the latter will not match if no canonicalization happens
            header = "Match final host !*.${domain}";
            ForwardAgent = false;
            SetEnv = {
              # avoid compatibility issues with Ghostty
              TERM = "xterm-256color";
            };
          };
          "*" = {
            AddKeysToAgent = "no";
            Compression = false;
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";
          };
        };
      };
    };
  };
}
