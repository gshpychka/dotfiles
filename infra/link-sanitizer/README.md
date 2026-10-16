# link-sanitizer

Telegram bot that replies to messages whose links carry tracking parameters
(`utm_*`, `fbclid`, `si`, …) with the cleaned links. An
[Alchemy](https://alchemy.run) stack on AWS: Telegram posts updates to the
`Receiver` Lambda's function URL, which queues each reply on SQS for the
`Sender` Lambda to deliver through the Bot API.

## Deploy

From this directory, in the infra shell:

```sh
# once: the bot token and an AWS profile
sops ../../secrets/infra/link-sanitizer.env  # TELEGRAM_BOT_TOKEN=<token from @BotFather>
bun alchemy profile edit --add AWS

bun install --frozen-lockfile
bun run deploy
```

A bot has a single webhook, so the scripts deploy one stage, `prod`. They read
the token through `sops exec-env`.

`bun run dev` serves the stack from Alchemy's local AWS emulator in Docker
while the bot's webhook stays on `prod`.

`bun install` regenerates `bun.nix`, the Nix form of `bun.lock` that the flake
check installs from.
