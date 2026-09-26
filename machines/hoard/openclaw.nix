# Adding a secret gated by one of the flags below (YubiKey or the op age key):
#   sops set secrets/hoard/openclaw.yaml '["telegram-bot-token"]' '"<token from @BotFather>"'
#   sops set secrets/hoard/openclaw.yaml '["telegram-owner-id"]' '"<numeric id, e.g. from @userinfobot>"'
#   sops set secrets/hoard/openclaw.yaml '["anthropic-api-key"]' '"<key>"'
#   sops set secrets/hoard/openclaw.yaml '["home-assistant-token"]' '"<long-lived token of a dedicated HA user>"'
{ config, ... }:
{
  my.openclaw = {
    enable = true;
    sopsFile = ../../secrets/hoard/openclaw.yaml;
    publicHost = config.services.nginx.virtualHosts.openclaw.serverName;
    trustedProxy = {
      inherit (config.my.webGateway.sso) enable;
      userHeader = config.my.webGateway.sso.identityHeader;
      users = [ config.my.user ];
    };
    telegram.enable = false;
    anthropic.enable = false;
    # HA's MCP Server integration: the Assist API over the entities exposed
    # to it, as a dedicated HA user
    mcpServers.home-assistant = {
      enable = false;
      settings = {
        url = "http://homeassistant.${config.my.domain}:8123/api/mcp";
        transport = "streamable-http";
        headers.Authorization = "Bearer \${HOME_ASSISTANT_TOKEN}";
      };
      secrets.HOME_ASSISTANT_TOKEN = "home-assistant-token";
    };
    ollama = {
      baseUrl = config.my.ollama.nativeUrl;
      models = [
        "qwen3.8:27b-mtp-q4_K_M"
        "qwen3.5:9b-q8_0"
      ];
    };
    # Kokoro-FastAPI behind reaper's nginx (machines/reaper/kokoro.nix)
    speech.tts = {
      baseUrl = "https://${config.my.ollama.host}.${config.my.domain}/kokoro/v1";
      model = "kokoro";
      voice = "af_heart";
    };
  };
}
