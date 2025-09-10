{
  lib,
  pkgs,
  inputs,
  config,
  ...
}:

let
  # Access nixified-ai models if available
  aiModels = inputs.nixified-ai.packages.${pkgs.system}.models or { };
in
{
  imports = [
    inputs.nixified-ai.nixosModules.comfyui
  ];

  nix.settings = {
    # nixified-ai's binary cache
    extra-substituters = [ "https://ai.cachix.org" ];
    extra-trusted-public-keys = [ "ai.cachix.org-1:N9dzRK+alWwoKXQlnn0H6aUx0lU/mspIoz8hMvGvbbc=" ];
  };

  services.comfyui = {
    enable = true;
    port = 7860;
    host = "127.0.0.1";
    openFirewall = false;
    acceleration = "cuda";

    # Add Flux models for image generation
    models =
      with aiModels;
      lib.optionals (aiModels != { }) [
        # Core Flux models
        flux1-dev-q4_0 # Main GGUF model (~6GB, quantized for better performance)
        flux-ae # VAE autoencoder
        flux-text-encoder-1 # CLIP text encoder
      ];

    # Custom nodes can be added here if needed
    customNodes = [ ];
  };
  services.nginx.virtualHosts."comfyui" = {
    serverName = "comfyui.${config.networking.fqdn}";
    useACMEHost = config.networking.fqdn;
    onlySSL = true;
    locations."/" = {
      proxyPass = "http://${config.services.comfyui.host}:${toString config.services.comfyui.port}/";
      recommendedProxySettings = true;
      proxyWebsockets = true;
    };
  };
}
