#!/usr/bin/env bash
# Backs up the kodi box, then installs a CoreELEC update tar and reboots into
# it. Run from reaper:
#   scripts/kodi/cpm/flash.sh <update.tar> [host]
# The box applies /storage/.update/*.tar while booting and keeps /storage.
set -euo pipefail

TAR=$1
HOST=${2:-kodi}
BACKUP=$HOME/build/kodi-backup-$(date +%Y%m%d-%H%M)

(cd "$(dirname "$TAR")" && sha256sum -c --quiet "$(basename "$TAR").sha256")

# Kodi answers JSON-RPC on localhost:9090; the reboot ends any playback.
players=$(ssh "$HOST" 'printf %s "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"Player.GetActivePlayers\"}" |
  nc -w 3 127.0.0.1 9090')
if [[ $players != *'"result":[]'* ]]; then
  echo "something is playing on $HOST: $players" >&2
  exit 1
fi

# sqlite's online backup copies each database consistently while Kodi runs.
mkdir -p "$BACKUP"
ssh "$HOST" 'rm -rf /storage/.dbbackup && mkdir /storage/.dbbackup &&
  cd /storage/.kodi/userdata/Database &&
  for db in *.db; do sqlite3 "$db" ".backup /storage/.dbbackup/$db"; done'
ssh "$HOST" 'tar -C /storage -cf - --exclude=".kodi/userdata/Database/*.db*" \
  --exclude=.kodi/temp .kodi .config .cache .dbbackup' >"$BACKUP/storage.tar"
ssh "$HOST" 'tar -C /flash -cf - .' >"$BACKUP/flash.tar"
ssh "$HOST" 'rm -rf /storage/.dbbackup'
(cd "$BACKUP" && sha256sum storage.tar flash.tar >SHA256SUMS)
echo "backup: $BACKUP"

scp -q "$TAR" "$TAR.sha256" "$HOST:/storage/.update/"
# shellcheck disable=SC2029 # the tar's name comes from this side
ssh "$HOST" "cd /storage/.update && sha256sum -c $(basename "$TAR").sha256 && systemctl reboot"
