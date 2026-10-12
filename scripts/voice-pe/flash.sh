#!/usr/bin/env bash
# Upload an already-built OTA image to one explicitly named device. No compile.
set -euo pipefail
if [[ $# != 3 || $1 != --confirm-flash ]]; then
  echo "Usage: flash-voice-pe --confirm-flash FIRMWARE_OUTPUT DEVICE_HOST" >&2
  exit 2
fi
firmware=$(realpath "$2")
[[ -f "$firmware/firmware.bin" && -f "$firmware/SHA256SUMS" ]]
(cd "$firmware"; sha256sum -c SHA256SUMS)
exec voice-pe-upload "$firmware/firmware.bin" "$3"
