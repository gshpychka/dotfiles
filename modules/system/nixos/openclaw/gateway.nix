# The OpenClaw gateway (https://docs.openclaw.ai): the agent's service on this
# host, its workspace, and its openclaw.json, validated at build time.
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

  # environment.etc keys are relative to /etc
  configEtcPath = lib.removePrefix "/etc/" gw.configPath;
  # the rendered openclaw.json
  configFile = config.environment.etc.${configEtcPath}.source;

  # the gateway refuses to start on a config that fails this validation
  configCheck =
    pkgs.runCommand "openclaw-config-check"
      {
        env =
          gw.environment
          # each secret's variable, so that its ${VAR} references resolve
          // lib.mapAttrs (_: _: "1") cfg.secrets
          // {
            OPENCLAW_CONFIG_PATH = configFile;
          };
      }
      ''
        # a writable home and state directory for the CLI, inside the build's scratch directory
        export HOME=$TMPDIR OPENCLAW_STATE_DIR=$TMPDIR/state
        # the gateway's own validation, as JSON (--json), shown in the build log and kept as the check's output (tee $out)
        ${lib.getExe gw.package} config validate --json | tee $out
        # fails the build (-e) on any warning, such as an unresolved ''${VAR} reference
        ${lib.getExe pkgs.jq} -e '.warnings == []' $out
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
      description = "The agent's workspace (https://docs.openclaw.ai/concepts/agent-workspace).";
    };
  };

  config = lib.mkIf cfg.enable {
    services.openclaw-gateway = {
      enable = true;
      package = pkgs.openclaw;
      # Nix mode (https://docs.openclaw.ai/install/nix): Nix owns openclaw.json and the installed package
      environment.OPENCLAW_NIX_MODE = "1";
      config = {
        # the gateway starts only in local mode
        gateway.mode = "local";
        agents.defaults = {
          inherit (cfg) workspace;
          userTimezone = config.time.timeZone;
          # no recurring heartbeat turns (https://docs.openclaw.ai/gateway/heartbeat)
          heartbeat.every = "0m";
        };
        browser.enabled = false;
      };
    };

    environment.etc.${configEtcPath} = {
      # mkForce: OpenClaw's security audit rates a config others can read as critical
      mode = lib.mkForce "0400";
      inherit (gw) user;
    };

    systemd.services.${gw.unitName} = {
      # the config file sits in /etc, outside the unit definition systemd compares
      restartTriggers = [ configFile ];
      serviceConfig = {
        # mkForce: the module's logPath default is a file nothing rotates
        StandardOutput = lib.mkForce "journal";
        StandardError = lib.mkForce "journal";
        UMask = "0077";
      };
    };

    # OpenClaw runs ffmpeg and ffprobe only from fixed system directories, /run/current-system/sw/bin among them
    environment.systemPackages = [ pkgs.ffmpeg-headless ];

    system.checks = [ configCheck ];
  };
}
