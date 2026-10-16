import * as AWS from "alchemy/AWS";
import * as SQS from "alchemy/AWS/SQS";
import * as Effect from "effect/Effect";
import * as Schema from "effect/Schema";
import * as Stream from "effect/Stream";
import { Replies } from "./replies.ts";
import { BotToken, SendMessageParams, sendMessage } from "./telegram.ts";

const decodeReply = Schema.decodeEffect(Schema.fromJsonString(SendMessageParams));

/** Sends the queued replies; SQS redelivers a reply whose send fails. */
export default class Sender extends AWS.Lambda.Function<Sender>()(
  "Sender",
  { main: import.meta.url, functionUrl: false },
  Effect.gen(function* () {
    const token = yield* BotToken;

    // one reply per batch, so a failed send redelivers only that reply
    yield* SQS.consumeQueueMessages(Replies, { batchSize: 1 }, (records) =>
      records.pipe(
        Stream.runForEach((record) =>
          decodeReply(record.body).pipe(Effect.flatMap((reply) => sendMessage(token, reply))),
        ),
        Effect.orDie,
      ),
    );

    return {};
  }).pipe(Effect.provide(AWS.Lambda.QueueEventSource)),
) {}
