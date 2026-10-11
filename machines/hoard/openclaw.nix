# Adding a secret named below (YubiKey or the op age key):
#   sops set secrets/hoard/openclaw.yaml '["openai-api-key"]' '"<key>"'
#   sops set secrets/hoard/openclaw.yaml '["elevenlabs-api-key"]' '"<key>"'
#   sops set secrets/hoard/openclaw.yaml '["telegram-bot-token"]' '"<token from @BotFather>"'
#   sops set secrets/hoard/openclaw.yaml '["telegram-owner-id"]' '"<numeric id, e.g. from @userinfobot>"'
#   sops set secrets/hoard/openclaw.yaml '["home-assistant-token"]' '"<long-lived token of a dedicated HA user>"'
#   sops set secrets/hoard/openclaw.yaml '["home-assistant-admin-mcp-path"]' '"<private_... path from the ha-mcp app log>"'
#   sops set secrets/hoard/openclaw.yaml '["github-app-private-key"]' ... (see modules/system/nixos/openclaw/github.nix)
#
# Then the agent's GitHub App, once created (github.nix has the steps):
#   my.openclaw.github = { appId = ...; slug = "..."; installationId = ...; botUserId = ...; };
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
    # The ha-mcp app (https://homeassistant-ai.github.io/ha-mcp/): HA
    # administration (automations, scripts, dashboards, config). Its URL path
    # is its only credential, so the path lives in sops.
    mcpServers.home-assistant-admin = {
      enable = false;
      settings = {
        url = "http://homeassistant.${config.my.domain}:9583/\${HOME_ASSISTANT_ADMIN_MCP_PATH}";
        transport = "streamable-http";
      };
      secrets.HOME_ASSISTANT_ADMIN_MCP_PATH = "home-assistant-admin-mcp-path";
    };

    claudeCode.enable = true;
    rebuild.enable = true;
  };
}
