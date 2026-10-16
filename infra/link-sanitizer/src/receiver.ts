import * as AWS from "alchemy/AWS";
import * as SQS from "alchemy/AWS/SQS";
import * as Effect from "effect/Effect";
import * as HttpServerRequest from "effect/http/HttpServerRequest";
import * as HttpServerResponse from "effect/http/HttpServerResponse";
import * as Redacted from "effect/Redacted";
import * as Schema from "effect/Schema";
import { cleanLinks, replyText } from "./links.ts";
import { Replies } from "./replies.ts";
import { SendMessageParams, secretTokenHeader, Update } from "./telegram.ts";
import { WebhookSecret } from "./webhook-secret.ts";

const encodeReply = Schema.encodeEffect(Schema.fromJsonString(SendMessageParams));

/** The bot's webhook: queues a reply to every message with tracked links. */
export default class Receiver extends AWS.Lambda.Function<Receiver>()(
  "Receiver",
  { main: import.meta.url, functionUrl: true },
  Effect.gen(function* () {
    const secret = yield* (yield* WebhookSecret).text;
    const queueReply = yield* SQS.SendMessage(yield* Replies);

    return {
      fetch: Effect.gen(function* () {
        const request = yield* HttpServerRequest.HttpServerRequest;
        if (request.headers[secretTokenHeader] !== Redacted.value(yield* secret)) {
          return HttpServerResponse.empty({ status: 401 });
        }

        const { message } = yield* HttpServerRequest.schemaBodyJson(Update);
        if (message?.text === undefined) return HttpServerResponse.empty();

        const links = cleanLinks(message.text, message.entities ?? []);
        if (links.length === 0) return HttpServerResponse.empty();

        const reply = yield* encodeReply({
          chat_id: message.chat.id,
          text: replyText(links),
          reply_parameters: { message_id: message.message_id },
        });
        yield* queueReply({ MessageBody: reply });
        return HttpServerResponse.empty();
      }).pipe(Effect.orDie),
    };
  }).pipe(Effect.provide(SQS.SendMessageHttp)),
) {}
