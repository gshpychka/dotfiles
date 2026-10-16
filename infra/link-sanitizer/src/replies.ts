import * as SQS from "alchemy/AWS/SQS";

/** Replies to send, each a `SendMessageParams` as JSON. */
export const Replies = SQS.Queue("Replies");
