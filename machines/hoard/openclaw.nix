# Adding a secret named below (YubiKey or the op age key):
#   sops set secrets/hoard/openclaw.yaml '["openai-api-key"]' '"<key>"'
#   sops set secrets/hoard/openclaw.yaml '["elevenlabs-api-key"]' '"<key>"'
#   sops set secrets/hoard/openclaw.yaml '["telegram-bot-token"]' '"<token from @BotFather>"'
#   sops set secrets/hoard/openclaw.yaml '["telegram-owner-id"]' '"<numeric id, e.g. from @userinfobot>"'
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
    telegram.enable = true;

    model.primary = "openai/gpt-5.6-sol";
    providerKeys = {
      OPENAI_API_KEY = "openai-api-key";
      ELEVENLABS_API_KEY = "elevenlabs-api-key";
    };
    # spoken replies to voice notes
    tts = {
      provider = "elevenlabs";
      auto = "inbound";
      providers.elevenlabs.modelId = "eleven_v3";
    };
    transcription = [
      {
        provider = "elevenlabs";
        model = "scribe_v2";
        capabilities = [ "audio" ];
      }
    ];

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
  };
}
