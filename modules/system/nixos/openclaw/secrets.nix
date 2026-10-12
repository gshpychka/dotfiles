# The gateway's secrets: sops keys handed to its process as environment
# variables, which openclaw.json carries only references to.
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
      description = "SOPS file holding, as flat keys, every secret the agent is configured with.";
    };

    secrets = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        OPENAI_API_KEY = "openai-api-key";
      };
      description = ''
        Environment variables of the gateway's process, each set from the
        named sopsFile key. openclaw.json refers to one as ''${NAME} inside a
        string, or through secretRefs in a credential field.
      '';
    };

    secretRefs = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
      readOnly = true;
      default = lib.mapAttrs (name: _: {
        source = "env";
        provider = "default";
        id = name;
      }) cfg.secrets;
      description = "Each secret as the env SecretRef a credential field of openclaw.json takes, by variable name.";
    };

    secretFiles = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      default = lib.mapAttrs (_: key: config.sops.secrets.${sopsName key}.path) cfg.secrets;
      description = "Each secret's file, readable by root, by variable name.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops = {
      secrets = lib.mapAttrs' (
        _: key:
        lib.nameValuePair (sopsName key) {
          inherit (cfg) sopsFile;
          inherit key;
        }
      ) cfg.secrets;
      templates.${envFile} = {
        content = lib.concatStrings (
          lib.mapAttrsToList (var: key: "${var}=${config.sops.placeholder.${sopsName key}}\n") cfg.secrets
        );
        # the gateway user reads it directly
        owner = gw.user;
        restartUnits = [ "${gw.unitName}.service" ];
      };
    };

    services.openclaw-gateway.environmentFiles = [ config.sops.templates.${envFile}.path ];
  };
}
