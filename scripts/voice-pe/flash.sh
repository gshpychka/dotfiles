#!/usr/bin/env bash
# Builds voice-pe.yaml once and flashes it over the air to every Voice PE
# (hosts with a voiceArea in modules/common/hosts.nix), or to the ones named:
#   nix run .#flash-voice-pe [pe...]
set -euo pipefail

repo=$(git rev-parse --show-toplevel)
cd "$repo/scripts/voice-pe"

flake="$repo#nixosConfigurations.hoard.config.my"
domain=$(nix eval --raw "$flake.domain")
if (($# > 0)); then
  pes=("$@")
else
  # shellcheck disable=SC2016 # a Nix expression, not shell
  mapfile -t pes < <(nix eval --raw "$flake.hosts" --apply \
    'hosts: builtins.concatStringsSep "\n" (builtins.filter (name: hosts.${name}.voiceArea != null) (builtins.attrNames hosts))')
fi

# The device token is baked into the firmware; it exists on disk only for the build.
trap 'rm -f secrets.yaml' EXIT
(
  umask 077
  sops -d --extract '["device-token"]' "$repo/secrets/hoard/realtime-voice.yaml" |
    sed 's/^/realtime_voice_token: /' >secrets.yaml
)

esphome compile voice-pe.yaml
for pe in "${pes[@]}"; do
  echo "flashing $pe"
  esphome upload voice-pe.yaml --device "$pe.$domain"
done
