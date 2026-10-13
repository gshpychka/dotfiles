# The gateway's secrets: sopsFile values set as environment variables of its
# process, which openclaw.json references by name.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  gw = config.services.openclaw-gateway;
  # sops-nix secret names are host-global, so each carries the service name
  sopsName = key: "openclaw/${key}";
  envFile = "openclaw.env";
in
{
  options.my.openclaw = {
    sopsFile = lib.mkOption {
      type = lib.types.path;
      description = "SOPS file holding the gateway's secrets.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.nonEmptyStr;
      default = { };
      example = {
        OPENAI_API_KEY = "openai-api-key";
      };
      description = "Environment variables of the gateway's process, each set from the named sopsFile key: a token free of whitespace, quotes and backslashes.";
    };

    secretVars = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (var: _: "\${${var}}") cfg.secrets;
      description = "Each secret as the \${NAME} substitution a string of openclaw.json takes (https://docs.openclaw.ai/gateway/config-secrets-env), keyed by variable name.";
    };

    secretRefs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = lib.mapAttrs (var: _: {
        source = "env";
        provider = "default";
        id = var;
      }) cfg.secrets;
      description = "Each secret as the env SecretRef (https://docs.openclaw.ai/gateway/secrets/secretref-contract) a credential field of openclaw.json takes, keyed by variable name.";
    };

    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (_: key: config.sops.secrets.${sopsName key}.path) cfg.secrets;
      description = "Each secret's file, readable by root only, keyed by variable name.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = lib.mapAttrsToList (var: _: {
      assertion = builtins.match "[A-Z][A-Z0-9_]{0,127}" var != null;
      message = "my.openclaw.secrets.${var}: OpenClaw reads only variable names matching [A-Z][A-Z0-9_]{0,127}.";
    }) cfg.secrets;

    sops = {
      secrets = lib.mapAttrs' (
        _: key:
        lib.nameValuePair (sopsName key) {
          inherit (cfg) sopsFile;
          inherit key;
        }
      ) cfg.secrets;
      templates.${envFile} = {
        content = lib.concatLines (
          lib.mapAttrsToList (var: key: "${var}=${config.sops.placeholder.${sopsName key}}") cfg.secrets
        );
        # the gateway user reads it directly
        owner = gw.user;
        restartUnits = [ config.systemd.services.${gw.unitName}.name ];
      };
    };

    services.openclaw-gateway.environmentFiles = [ config.sops.templates.${envFile}.path ];
  };
}
