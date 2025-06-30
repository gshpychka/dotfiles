{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.buildServer;
  nixbuildUser = "nixbuild";
in
{
  options.my.buildServer = {
    enable = lib.mkEnableOption "Nix build server for distributed builds";

    hostName = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Hostname clients should use to connect to this build server";
      example = "reaper";
    };

    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4; # Conservative default, can be overridden
      description = "Maximum number of concurrent build jobs";
      example = 16;
    };

    speedFactor = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Relative speed factor compared to other builders";
      example = 4;
    };

    supportedFeatures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "nixos-test"
        "benchmark"
        "big-parallel"
      ];
      description = "List of features this build server supports";
      example = [
        "nixos-test"
        "benchmark"
        "big-parallel"
        "kvm"
      ];
    };

    mandatoryFeatures = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of features that must be supported by clients";
      example = [ ];
    };

    systems = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ pkgs.system ];
      description = "List of systems this build server can build for";
      example = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    };

    clientPublicKeys = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "SSH public keys of clients allowed to submit builds";
      example = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... nixbuild-hoard@hoard" ];
      # ssh-keygen -t ed25519 -f nixbuild-hoard -C "nixbuild-hoard@hoard"
      # mv nixbuild-hoard secrets/hoard/nixbuild-ssh-key && sops --encrypt --output secrets/hoard/nixbuild-ssh-key.pem secrets/hoard/nixbuild-ssh-key
      # Add public key content to modules/common/globals.nix my.nixbuildKeys, reference here via config.my.nixbuildKeys.hoard
    };
  };

  config = lib.mkIf cfg.enable {
    # Create dedicated build user
    users.users.${nixbuildUser} = {
      isSystemUser = true;
      group = nixbuildUser;
      shell = pkgs.bash; # Needed for SSH, but restricted by SSH config
      home = "/var/lib/nixbuild";
      createHome = true;
      description = "Nix distributed build user";
      openssh.authorizedKeys.keys = cfg.clientPublicKeys;
    };

    users.groups.${nixbuildUser} = { };

    # Restrict SSH access for build user - only allow nix-store operations
    services.openssh.extraConfig = ''
      Match User ${nixbuildUser}
        AllowAgentForwarding no
        AllowTcpForwarding no
        PermitTTY no
        X11Forwarding no
        ForceCommand ${pkgs.nix}/bin/nix-store --serve --write
    '';

    # Allow the build user to access the Nix daemon
    nix.settings.allowed-users = [ nixbuildUser ];
    nix.settings.trusted-users = [ nixbuildUser ];

    # Export this server's configuration for clients to import
    # This will be used by the flake to provide server configs to clients
    passthru.buildServerConfig = {
      hostName = cfg.hostName;
      systems = cfg.systems;
      maxJobs = cfg.maxJobs;
      speedFactor = cfg.speedFactor;
      supportedFeatures = cfg.supportedFeatures;
      mandatoryFeatures = cfg.mandatoryFeatures;
      user = nixbuildUser;
    };
  };
}

