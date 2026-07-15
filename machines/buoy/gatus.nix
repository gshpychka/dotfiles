{
  config,
  ...
}:
let
  # Alerts post directly to the Telegram Bot API through Gatus's custom provider,
  # so the message body is entirely ours. Each endpoint carries its own
  # triggered/resolved copy via the [ALERT_TRIGGERED_OR_RESOLVED] placeholder,
  # which Gatus substitutes into the body as a raw string. Each message is
  # toJSON-encoded (quotes included) and placed unquoted in the body, so any
  # quotes or newlines in the copy stay valid JSON.
  #
  # os.ExpandEnv runs over the whole config, so a literal "$" in a message must be
  # written as "$$".
  mkTelegramAlert =
    { triggered, resolved }:
    {
      type = "custom";
      send-on-resolved = true;
      provider-override.placeholders.ALERT_TRIGGERED_OR_RESOLVED = {
        TRIGGERED = builtins.toJSON triggered;
        RESOLVED = builtins.toJSON resolved;
      };
    };

  # ntfy runs alongside Telegram (see the alerting.ntfy provider below). Unlike
  # the custom Telegram provider, the native ntfy provider builds the message
  # itself and appends TRIGGERED/RESOLVED, so each alert only supplies a short
  # description for context.
  mkNtfyAlert = description: {
    type = "ntfy";
    inherit description;
    send-on-resolved = true;
  };
in
{
  services.gatus = {
    enable = true;
    environmentFile = config.sops.secrets.gatus-env.path;
    settings = {
      ui.custom-css = builtins.readFile ./gatus-gruvbox.css;
      web.address = "127.0.0.1";
      storage = {
        type = "sqlite";
        path = "/var/lib/gatus/data.db";
      };
      # Self-hosted ntfy on this same host (see ntfy.nix). The server is
      # deny-all, so Gatus publishes with a write-only token. Gatus runs
      # os.ExpandEnv over the whole config, so ${NTFY_TOKEN} (from the sops
      # gatus.env) is substituted at load time, matching the Telegram token.
      alerting.ntfy = {
        url = "https://ntfy.${config.my.domain}";
        topic = "buoy-status";
        token = "\${NTFY_TOKEN}";
        priority = 4;
      };
      alerting.custom = {
        url = "https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/sendMessage";
        method = "POST";
        headers."Content-Type" = "application/json";
        # message_thread_id is numeric; chat_id is quoted to accept numeric or @username ids.
        # text is unquoted because the placeholder expands to a toJSON-encoded string.
        body = ''{"chat_id":"''${TELEGRAM_CHAT_ID}","message_thread_id":''${TELEGRAM_TOPIC_ID},"text":[ALERT_TRIGGERED_OR_RESOLVED]}'';
        # Fallback copy for any alert that omits its own messages.
        placeholders.ALERT_TRIGGERED_OR_RESOLVED = {
          TRIGGERED = builtins.toJSON "⚠️ A monitored service is having problems.";
          RESOLVED = builtins.toJSON "✅ A monitored service has recovered.";
        };
      };
      endpoints = [
        {
          name = "Internet";
          url = "icmp://wan.${config.my.domain}";
          interval = "30s";
          ui.hide-hostname = true;
          conditions = [ "[CONNECTED] == true" ];
          alerts = [
            (mkTelegramAlert {
              triggered = "🔴 Інтернет зник.";
              resolved = "🟢 Інтернет знову є.";
            })
            (mkNtfyAlert "Інтернет")
          ];
        }
        {
          name = "Overseerr";
          url = "https://overseerr.${config.my.domain}";
          interval = "30s";
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 5000"
          ];
          alerts = [
            (mkTelegramAlert {
              triggered = "🔴 Overseerr недоступний.";
              resolved = "🟢 Overseerr знову доступний.";
            })
            (mkNtfyAlert "Overseerr")
          ];
        }
        {
          name = "Plex";
          url = "http://\${PLEX_HOST}:\${PLEX_PORT}/web/index.html";
          interval = "30s";
          ui = {
            hide-hostname = true;
            hide-errors = true;
          };
          conditions = [
            "[STATUS] == 200"
            "[RESPONSE_TIME] < 10000"
          ];
          alerts = [
            (mkTelegramAlert {
              triggered = "🔴 Plex недоступний.";
              resolved = "🟢 Plex знову доступний.";
            })
            (mkNtfyAlert "Plex")
          ];
        }
      ];
    };
  };

  sops.secrets.gatus-env = {
    sopsFile = ../../secrets/buoy/gatus.env;
    format = "dotenv";
  };
}
