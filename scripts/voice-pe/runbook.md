# Voice PE runbook

The Voice PEs (the hosts with a `voiceArea` in `modules/common/hosts.nix`) run
one firmware, `voice-pe.yaml`: the stock Home
Assistant Voice firmware with one addition, a **Voice backend** select. "Home Assistant" is the stock Assist path, still switched between
pipelines by the Assistant selects. "Live" hands the conversation to the
realtime-voice broker on hoard (`machines/hoard/realtime-voice.nix`), which
runs it on GPT-Live. GPT-Live listens while it speaks and decides itself when
to answer, yield or keep going. Home control goes through a delegated
Responses model.

Live reaches the home through Home Assistant's Assist API, the same entities and
intents a stock Assist satellite gets. A request that names no place is about
the PE's `voiceArea`.

While a broker conversation runs, the wake word or a press of the center
button ends it.
A Home Assistant announcement that arrives mid-conversation shares the
speaker with it.

## One-time setup

1. In Home Assistant, add the **Model Context Protocol Server** integration
   with the Assist API. It controls the entities exposed to Assist
   (Settings → Voice assistants → Expose).
2. Create a long-lived access token for it (Profile → Security).
3. Fill the placeholders in the broker's secrets. The device token is already
   generated:

   ```sh
   nix develop -c sops secrets/hoard/realtime-voice.yaml
   ```

   - `openai-api-key`: an OpenAI API key with Live access
   - `ha-token`: the token from step 2

4. Deploy harbor (static lease) and hoard (broker):

   ```sh
   nixos-rebuild switch --flake .#harbor --target-host harbor --sudo
   nixos-rebuild switch --flake .#hoard --target-host hoard --sudo
   ```

   Restart each Voice PE from Home Assistant so it picks up its static lease;
   the broker only accepts those addresses. Home Assistant finds them again
   through zeroconf.

## Flashing

Over the air, one build for every PE, or only the ones named:

```sh
nix run .#flash-voice-pe [pe...]
```

`flash.sh` does it with the flake's ESPHome and sops. It needs to decrypt the
secrets file, so run it where a sops key is available.

Wi-Fi credentials and the Home Assistant API key live in the device's flash
and survive the reflash, so the device stays adopted. The first build
downloads the ESP-IDF toolchain into `.esphome/` and takes a while.

This build has no firmware update entity, so Home Assistant no longer offers
upstream releases for the devices. To pick one up, bump `ref` in
`voice-pe.yaml` and reflash.

## Using it

Set **Voice backend** to Live on the device page. Watch the broker with
`ssh hoard journalctl -fu realtime-voice`.

## Recording conversations

To check the echo cancellation against what happened in the room:

1. Set `recordings.enable = true` in `machines/hoard/realtime-voice.nix` and
   deploy hoard.
2. Have a few conversations: talk over replies, and also let replies play out
   while the room is noisy (music, dishes).
3. Each conversation leaves `<stamp>-<pe>.wav` in
   `/var/lib/private/realtime-voice/recordings/`: 16 kHz with three channels,
   the raw mic, what the speaker played (aligned to the mic), and the
   echo-cancelled mic.
4. Set `recordings.enable = false`, delete the recordings, deploy.

## Undo

Set **Voice backend** to Home Assistant. To go back to the stock firmware,
flash it from https://esphome.github.io/home-assistant-voice-pe/ over USB.
