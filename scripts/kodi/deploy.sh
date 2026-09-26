#!/usr/bin/env bash
# Pushes kodi-customize to the kodi box and runs it. Run from eve:
#   scripts/kodi/deploy.sh [host]
# Settings in kodi_settings only apply at the next boot, when Kodi is stopped.
set -euo pipefail

HOST=${1:-kodi}
HERE=$(cd "$(dirname "$0")" && pwd)
REMOTE=/storage/.config/kodi-customize
UNITS=(kodi-customize.service kodi-customize.path)

tar -C "$HERE" -cf - kodi-customize.sh skin-overrides snippets |
  ssh "$HOST" "rm -rf $REMOTE && mkdir $REMOTE && tar -C $REMOTE -xf -"
for unit in "${UNITS[@]}"; do
  ssh "$HOST" "cat > /storage/.config/system.d/$unit" < "$HERE/$unit"
done
ssh "$HOST" "systemctl daemon-reload &&
  systemctl enable ${UNITS[*]} &&
  systemctl start kodi-customize.path &&
  systemctl start kodi-customize.service &&
  journalctl -t kodi-customize --no-pager -n 5"
