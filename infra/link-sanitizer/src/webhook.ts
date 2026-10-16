import { Resource } from "alchemy";
import * as ProviderLayer from "alchemy/Local/ProviderLayer";
import * as Provider from "alchemy/Provider";
import * as Effect from "effect/Effect";
import * as Redacted from "effect/Redacted";
import { deleteWebhook, setWebhook } from "./telegram.ts";

export interface WebhookProps {
  /** Token of the bot that receives the updates. */
  token: Redacted.Redacted<string>;
  /** HTTPS endpoint Telegram posts updates to. */
  url: string;
  /** Value Telegram sends in the secret token header of every update. */
  secretToken: Redacted.Redacted<string>;
  /** Update types Telegram delivers. */
  allowedUpdates: readonly string[];
}

export interface WebhookAttributes {
  url: string;
}

/** A bot's webhook: Telegram posts the bot's updates to its URL. */
export type Webhook = Resource<"Telegram.Webhook", WebhookProps, WebhookAttributes>;
export const Webhook = Resource<Webhook>("Telegram.Webhook");

export const WebhookProvider = () =>
  ProviderLayer.dual(Webhook, {
    // a bot has a single webhook, which setWebhook overwrites in place
    live: () =>
      Provider.succeed(Webhook, {
        reconcile: ({ news }) =>
          setWebhook(news.token, {
            url: news.url,
            secret_token: Redacted.value(news.secretToken),
            allowed_updates: news.allowedUpdates,
          }).pipe(Effect.as({ url: news.url })),
        delete: ({ olds }) => deleteWebhook(olds.token),
      }),
    // Telegram only delivers to public HTTPS endpoints, so the bot's webhook
    // stays as deployed while `alchemy dev` serves the receiver locally
    local: () =>
      Provider.succeed(Webhook, {
        reconcile: ({ news }) => Effect.succeed({ url: news.url }),
        delete: () => Effect.void,
      }),
  });
