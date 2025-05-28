{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.my.ollama;
in
{
  options.my.ollama = {
    enable = lib.mkEnableOption "Ollama server + model loader + nginx proxy";

    loadModels = lib.mkOption {
      default = [ ];
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption {
              type = lib.types.str;
              description = "Model identifier – e.g. \"llama3\" or \"phi3:mini\".";
            };
            loadIntoVram = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Keep the model resident with keep_alive = -1.";
            };
          };
        }
      );
      description = ''
        Models to download on every boot; those with
        `loadIntoVram = true` are additionally pre-loaded into VRAM/CPU-RAM.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    services.ollama = {
      enable = true;
      acceleration = "cuda";

      loadModels = lib.mkBefore (map (m: m.name) cfg.loadModels);
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = lib.mkForce false; # Ollama chokes otherwise

      virtualHosts."default".locations."/ollama/" = {
        proxyPass = "http://${config.services.ollama.host}:${toString config.services.ollama.port}/";
        proxyWebsockets = true;
      };
    };

    systemd.services.ollama-preload = lib.mkIf (lib.any (m: m.loadIntoVram) cfg.loadModels) {
      description = "Warm selected Ollama models into VRAM";
      partOf = [ "ollama.service" ];
      wantedBy = [ "ollama.service" ];
      after = [
        "ollama.service"
        "ollama-model-loader.service"
      ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "ollama-preload" ''
          set -euo pipefail
          api="http://${config.services.ollama.host}:${toString config.services.ollama.port}/api/generate"
          ${lib.concatMapStringsSep "\n" (
            m:
            lib.optionalString m.loadIntoVram ''
              echo "Pre-loading ${m.name}"
              ${pkgs.curl}/bin/curl --silent --show-error \
                --header 'Content-Type: application/json' \
                --data '{"model":"${m.name}","keep_alive":-1}' \
                "$api" >/dev/null
            ''
          ) cfg.loadModels}
        '';
      };
    };
  };
}
