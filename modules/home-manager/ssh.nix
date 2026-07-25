{
  config,
  lib,
  pkgs,
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
    opkssh.enable = lib.mkEnableOption "opkssh client, for SSH login with a Google identity";
  };

  config = lib.mkIf cfg.enable {
    # Client half of modules/system/nixos/opkssh.nix. `opkssh login` authenticates
    # to Google in a browser and writes a short-lived key to ~/.ssh/id_ecdsa - one
    # of OpenSSH's default identity paths, so no ssh_config entry is needed for it
    # to be offered. If a host ever rejects it, the cause is likely MaxAuthTries
    # (default 6) being exhausted by agent keys first; fix with an explicit
    # `IdentitiesOnly yes` + `IdentityFile ~/.ssh/id_ecdsa` for that host.
    home.packages = lib.optional cfg.opkssh.enable pkgs.opkssh;

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

        settings =
          let
            # Per-host Match blocks come from the fleet registry (modules/common/hosts.nix).
            # Hosts with no ssh-specific data need no block of their own - the
            # generic "local" match below covers them.
            fleetHosts = lib.filterAttrs (_: h: h.sshUser != null || h.sshSettings != { }) osConfig.my.hosts;
            fleetBlocks = lib.mapAttrs (
              name: h:
              lib.hm.dag.entryBefore [ "local" ] (
                {
                  header = "Match final host ${name}.${domain}";
                }
                // lib.optionalAttrs (h.sshUser != null) { User = h.sshUser; }
                // h.sshSettings
              )
            ) fleetHosts;
          in
          # order matters for SSH, since the first value wins (no overrides later)
          # The order of the attrs specified here has no effect on the resulting file
          # because HM orders these as a DAG, so we need to specify the dependencies ourselves
          # Short attr names are used (rather than literal `Match ...` keys) so the DAG
          # references stay stable and readable.
          fleetBlocks
          // {

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
              Compression = true;
              # detect dead connections in ~45s and keep NAT mappings alive
              ServerAliveInterval = 15;
              ServerAliveCountMax = 3;
              # keystroke-timing chaff costs ~20ms per keypress and extra packets
              ObscureKeystrokeTiming = false;
              HashKnownHosts = false;
              UserKnownHostsFile = "~/.ssh/known_hosts";
              # share one connection per destination; new sessions skip the
              # TCP + key exchange + auth round trips
              ControlMaster = "auto";
              ControlPath = "~/.ssh/master-%C"; # %C = hash of user/host/port
              ControlPersist = "10m";
            };
          };
      };
    };
  };
}
