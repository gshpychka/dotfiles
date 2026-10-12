#!/usr/bin/env bash
# Build-only compatibility entrypoint. Never compiles locally or flashes.
set -euo pipefail
repo=$(git rev-parse --show-toplevel)
exec sudo -n nix build "path:$repo#voice-pe-firmware" \
  --max-jobs 0 --cores 8 --no-link --print-out-paths -L
