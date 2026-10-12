# OpenClaw personal-assistant gateway (https://docs.openclaw.ai), built on the
# nix-openclaw NixOS module (services.openclaw-gateway).
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;

  configEtcPath = lib.removePrefix "/etc/" gw.configPath;
  configFile = config.environment.etc.${configEtcPath}.source;

  # The gateway refuses to start on unknown or legacy keys in a read-only
  # config, and reports unresolved ${VAR} references only as warnings.
  configCheck =
    pkgs.runCommand "openclaw-config-check"
      {
        env = lib.mapAttrs (_: _: "1") cfg.secrets // {
          OPENCLAW_NIX_MODE = "1";
          OPENCLAW_CONFIG_PATH = configFile;
        };
      }
      ''
        export HOME=$TMPDIR OPENCLAW_STATE_DIR=$TMPDIR/state
        ${lib.getExe' gw.package "openclaw"} config validate --json | tee $out
        ${lib.getExe pkgs.jq} -e '.valid and (.warnings | length == 0)' $out > /dev/null
      '';
in
{
  imports = [ inputs.nix-openclaw.nixosModules.openclaw-gateway ];

  options.my.openclaw = {
    enable = lib.mkEnableOption "the OpenClaw gateway";

    workspace = lib.mkOption {
      type = lib.types.str;
      default = "${gw.stateDir}/workspace";
      readOnly = true;
      description = "The agent's workspace: its home, and the working directory its tools start in.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway = {
      enable = true;
      # OpenClaw treats its config as read-only and leaves updates to Nix
      environment.OPENCLAW_NIX_MODE = "1";
      config = {
        agents.defaults = {
          inherit (cfg) workspace;
          userTimezone = config.time.timeZone;
          heartbeat.every = "0m";
        };
        browser.enabled = false;
        commands.restart = true;
      };
    };

    environment.etc.${configEtcPath} = {
      # only the gateway user reads its config
      mode = lib.mkForce "0400";
      inherit (gw) user;
    };

    # for tmpfiles rules inside it: tmpfiles creates a missing parent as root
    systemd.tmpfiles.rules = [ "d ${cfg.workspace} 0700 ${gw.user} ${gw.group} - -" ];

    systemd.services.${gw.unitName} = {
      # config changes land in /etc without touching the unit
      restartTriggers = [ configFile ];
      serviceConfig = {
        StandardOutput = lib.mkForce "journal";
        StandardError = lib.mkForce "journal";
        UMask = "0077";
        MemoryMax = "6G";
        TasksMax = 1024;
      };
    };

    system.checks = [ configCheck ];
  };
}
