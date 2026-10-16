# Prepared playback metadata probe — NOT activated

Base: canonical commit 7c8ebd0. Approved Live instructions and marin are unchanged.

The added broker logger accepts only integer frame counts and DAC timestamps.
It logs one aggregate per approximately one second of continuous reports, with
sent input frames, reported input frames, inferred input-frame rate, discarded
long-gap count, and a contamination warning when played counts exceed sent.
It does not accept or persist PCM, speech text, user instructions, or credentials.
Existing broker transcript logging is unchanged; this patch does not enable recordings.

## Counter units

The firmware's PLAYED callback is attached to announcement_resampling_speaker.
ESPHome resampler converts downstream 48 kHz DAC callback counts back to its
DECLARED INPUT rate, preserving fractional-frame remainder. Therefore PLAYED
is not a raw 48 kHz DAC frame count. With the intended 24 kHz input, 960 DAC
frames correspond to 480 reported input frames. A stale 16 kHz input should
report approximately 16,000 input frames per DAC second, despite the wire PCM
being 24 kHz. Callback timing is approximate; use a sustained interval, not a
single report. Concurrent HA announcements can contaminate this shared callback.
The total-reported > total-sent warning catches some, but not all, contamination;
ensure no other announcement runs during the diagnostic session.

The firmware-only addition logs first feed state and declared input format,
then the declared input format at the first successful write, once each per
conversation. It deliberately does not correct or restart the speaker.

## Local tests

- Six Python cases: correct 24k, stale 16k, DAC/input counter conversion,
  long/backwards gaps, shared-path contamination, first-report anchoring.
- Four compiled C++ cases extract the ACTUAL feed_speaker_ method and mock I/O:
  stopped16k becomes24k; running16k retains16k; running24k remains24k; a
  zero-byte write does not produce a first-write event. These are host tests,
  not an ESP32 hardware integration test or proof the real fault happened.

## Authority gate and minimum disruption

No build activation, OTA flash, playback, or paid generation has been performed.

Option A: broker-only logger. Build the package remotely and inspect the NixOS
activation plan before applying. Installing a changed voice-broker package
requires restarting voice-broker.service; existing conversations would end.
No Room flash is needed. A Gateway restart is not inherently required, but
must be excluded by the actual dry-activation plan before any approved switch.
This provides measured PLAYED rates, but not first-write firmware state.

Option B: complete probe. In addition to Option A, build Voice PE firmware on
reaper (zero local build jobs), validate artifacts, and OTA-flash ONLY Room.
This reboots Room, briefly stopping both its Assist and GPT-Live functionality.
Its existing encrypted ESPHome API INFO log subscription is required to collect
first-feed/first-write metadata; do not persist other device log content.
No HA Core or Gateway restart is needed for the Room OTA step.

Only after activation approval and readiness verification should a short direct
session be run. Compare recorded metadata against 24k expected / 16k suspect.
Remove the temporary logger after diagnosis through the same managed paths.
