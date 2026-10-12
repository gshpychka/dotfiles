# The Telegram channel: DMs from the owner, who is also the gateway's owner
# for chat commands.
{ config, lib, ... }:
let
  cfg = config.my.openclaw;
  owner = "\${TELEGRAM_OWNER_ID}";
in
{
  options.my.openclaw.telegram.enable = lib.mkEnableOption ''
    the Telegram channel: the bot of sopsFile's telegram-bot-token, answering
    DMs from the numeric user id in telegram-owner-id only'';

  config = lib.mkIf (cfg.enable && cfg.telegram.enable) {
    my.openclaw.secrets = {
      TELEGRAM_BOT_TOKEN = "telegram-bot-token";
      TELEGRAM_OWNER_ID = "telegram-owner-id";
    };

    services.openclaw-gateway.config = {
      plugins.entries.telegram.enabled = true;
      channels.telegram = {
        enabled = true;
        botToken = cfg.secretRefs.TELEGRAM_BOT_TOKEN;
        dmPolicy = "allowlist";
        allowFrom = [ owner ];
        groupPolicy = "disabled";
        capabilities.inlineButtons = "dm";
      };
      commands.ownerAllowFrom = [ "telegram:${owner}" ];
      # senders whose `! <command>` runs on this host
      tools.elevated.allowFrom.telegram = [ owner ];
    };
  };
}
