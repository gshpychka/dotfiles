import * as Alchemy from "alchemy";
import * as AWS from "alchemy/AWS";
import * as Output from "alchemy/Output";
import * as Effect from "effect/Effect";
import * as Layer from "effect/Layer";
import Receiver from "./src/receiver.ts";
import Sender from "./src/sender.ts";
import { BotToken } from "./src/telegram.ts";
import { Webhook, WebhookProvider } from "./src/webhook.ts";
import { WebhookSecret } from "./src/webhook-secret.ts";

export default Alchemy.Stack(
  "LinkSanitizer",
  {
    providers: Layer.mergeAll(AWS.providers(), WebhookProvider()),
    state: AWS.state(),
  },
  Effect.gen(function* () {
    const receiver = yield* Receiver;
    yield* Sender;

    const url = receiver.functionUrl.pipe(
      Output.mapEffect((functionUrl) =>
        functionUrl === undefined
          ? Effect.die("Receiver has no function URL")
          : Effect.succeed(functionUrl),
      ),
    );
    yield* Webhook("Webhook", {
      token: yield* BotToken,
      url,
      secretToken: (yield* WebhookSecret).text,
      allowedUpdates: ["message"],
    });

    return { url };
  }),
);
