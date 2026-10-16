import { Random } from "alchemy";

/** Secret token that authenticates Telegram's webhook requests. */
export const WebhookSecret = Random("WebhookSecret");
