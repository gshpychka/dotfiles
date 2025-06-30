{ config, lib, pkgs, ... }:

let
  cfg = config.my.distributedBuilds;
  
  # Convert server config to Nix build machine format
  serverToBuildMachine = serverName: 
    let serverConfig = config.my.buildServers.${serverName};
    in {
      hostName = serverConfig.hostName;
      systems = serverConfig.systems;
      maxJobs = serverConfig.maxJobs;
      speedFactor = serverConfig.speedFactor;
      supportedFeatures = serverConfig.supportedFeatures;
      mandatoryFeatures = serverConfig.mandatoryFeatures;
      sshUser = serverConfig.sshUser;
      sshKey = cfg.sshKeyPath;
    };
  
  buildMachines = map serverToBuildMachine cfg.servers;
in
{
  options.my.distributedBuilds = {
    enable = lib.mkEnableOption "distributed Nix builds as a client";
    
    servers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of build server names to use";
      example = [ "reaper" ];
    };
    
    sshKeyPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to SSH private key for connecting to build servers";
      example = "/run/secrets/nixbuild-ssh-key";
    };
    
    fallbackToBuildLocally = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to build locally if remote builders are unavailable";
    };
  };

  config = lib.mkIf cfg.enable {
    nix.distributedBuilds = true;
    nix.buildMachines = buildMachines;
    
    # Settings for better distributed build experience
    nix.settings = {
      # Fallback to local builds if remote builders fail
      builders-use-substitutes = true;
      # Try to use substitutes before building
      substitute = true;
      # Don't build locally by default when remote builders are available
      max-jobs = if cfg.fallbackToBuildLocally then lib.mkDefault 1 else 0;
    };
    
    # Configure SSH for connecting to build servers
    # This assumes Tailscale or similar networking is already configured
    programs.ssh.extraConfig = lib.mkIf (buildMachines != [ ]) (
      lib.concatMapStringsSep "\n" (machine: ''
        Host ${machine.hostName}
          StrictHostKeyChecking accept-new
          UserKnownHostsFile /dev/null
          LogLevel ERROR
      '') buildMachines
    );
  };
}