# Voice PE runbook

The kitchen Voice PE (`kitchen-assistant` in `modules/common/hosts.nix`) runs
the stock Home Assistant Voice firmware with one addition: a **Voice backend**
select. "Home Assistant" is the stock Assist path, still switched between
pipelines by the Assistant selects. "Realtime" hands the conversation to the
realtime-voice broker on reaper (`machines/reaper/realtime-voice.nix`),
which talks to the OpenAI Realtime API and lets you interrupt the reply by
just talking.

While a Realtime conversation runs, the wake word ends it. The center button
keeps its stock behavior (it starts Assist), so use the wake word instead.
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
   nix run nixpkgs#sops -- secrets/reaper/realtime-voice.yaml
   ```

   - `openai-api-key`: an OpenAI API key with Realtime access
   - `ha-token`: the token from step 2
   - `ha-mcp-url`: the ha-mcp add-on's full URL, secret path included
     (`http://homeassistant.glib.sh:9583/private_…`)

4. Deploy harbor (static lease) and reaper (broker):

   ```sh
   nixos-rebuild switch --flake .#harbor --target-host harbor --sudo
   nixos-rebuild switch --flake .#reaper --target-host reaper --sudo
   ```

   Restart the Voice PE from Home Assistant so it picks up 192.168.1.53; the
   broker's firewall only accepts that address. Home Assistant finds it again
   through zeroconf.

## Flashing

From `scripts/voice-pe/`, over the air:

```sh
nix run nixpkgs#sops -- -d --extract '["device-token"]' ../../secrets/reaper/realtime-voice.yaml \
  | sed 's/^/realtime_voice_token: /' > secrets.yaml
nix run nixpkgs#esphome -- run kitchen-assistant.yaml --device kitchen-assistant.glib.sh
rm secrets.yaml
```

Wi-Fi credentials and the Home Assistant API key live in the device's flash
and survive the reflash, so the device stays adopted. The first build
downloads the ESP-IDF toolchain into `.esphome/` and takes a while.

This build has no firmware update entity, so Home Assistant no longer offers
upstream releases for the device. To pick one up, bump `ref` in
`kitchen-assistant.yaml` and reflash.

## Using it

Set **Voice backend** to Realtime on the device page. Watch the broker with
`ssh reaper journalctl -fu realtime-voice`.

## Tuning barge-in

Interruptions are decided on reaper from echo-cancelled mic audio, with the
thresholds in `barge_in` in `machines/reaper/realtime-voice.nix`. To tune them:

1. Set `record = true` there and deploy reaper.
2. Have a few conversations: talk over replies, and also let replies play out
   while the room is noisy (music, dishes).
3. Each conversation leaves `<stamp>.wav` and `<stamp>.jsonl` in
   `/var/lib/private/realtime-voice/recordings/`. The WAV is 16 kHz with three
   channels: the raw mic, what the speaker played (aligned to the mic), and the
   echo-cancelled mic. The JSONL has every barge-in with its level, VAD
   probability and AEC statistics.
4. False interruptions: raise `min_level_dbfs` or `min_speech_ms`. Missed
   ones: lower them. `vad_threshold` is Silero's speech probability.
5. Set `record = false`, delete the recordings, deploy.

If the echo-cancelled channel still carries clear speaker audio, check the
AEC `delay_ms` statistic in the JSONL. A reference that isn't lined up
shows as a large or wandering delay.

## Undo

Set **Voice backend** to Home Assistant. To go back to the stock firmware,
flash it from https://esphome.github.io/home-assistant-voice-pe/ over USB.
