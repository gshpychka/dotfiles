#!/bin/sh
# Customizations to the Bingie skin on the kodi box. Kodi overwrites the skin
# directory on every Bingie update, so this is idempotent and reruns at boot
# and after each update (kodi-bingie-customize.{service,path}).
# Deployment: scripts/kodi/runbook.md.
set -eu

SKIN=/storage/.kodi/addons/skin.bingie/1080i
OVERRIDES=/storage/.config/kodi-bingie

log() { logger -t kodi-bingie-customize "$1"; echo "$1"; }

[ -d "$SKIN" ] || { log "skin missing, nothing to customize: $SKIN"; exit 0; }
status=0
reload=0

# Hide the profile switcher at the top of the side menu; Bingie has no setting
# for it. It is the group right after the "Logo / user profile button" comment
# in BingieSideBladeMainMenu. Setting its <visible> to false also makes its
# button (id 40000) unfocusable, so the menu's <onup>40000</onup> goes nowhere.
hide_profile() {
  file="$SKIN/IncludesBingie.xml"
  marker='<!-- kodi-bingie-hide-profile -->'
  grep -qF "$marker" "$file" && return 0
  tmp="$file.tmp.$$"
  # Replace the first <visible> within 3 lines after the anchor. Exit status 2
  # means the anchor or the <visible> line moved in a new Bingie release.
  if ! awk -v anchor='<!-- Logo / user profile button -->' -v marker="$marker" '
    index($0, anchor) { armed = 4 }
    armed && !done && /<visible>.*<\/visible>/ {
      sub(/<visible>.*<\/visible>/, "<visible>false</visible>" marker)
      done = 1
    }
    armed { armed-- }
    { print }
    END { exit done ? 0 : 2 }
  ' "$file" > "$tmp"; then
    rm -f "$tmp"
    log "profile switcher anchor not found, skin layout changed; update this script"
    return 1
  fi
  mv "$tmp" "$file"
  log "profile switcher hidden"
  reload=1
}

# Whole-window overrides, e.g. PlexKodiConnect's skip marker dialog. Kodi
# resolves an addon's window XML in the active skin first, but only sees a new
# file in the skin directory after a skin reload.
install_overrides() {
  for src in "$OVERRIDES"/*.xml; do
    [ -f "$src" ] || continue
    dst="$SKIN/$(basename "$src")"
    if [ -f "$dst" ] && [ "$(md5sum < "$src")" = "$(md5sum < "$dst")" ]; then
      continue
    fi
    cp "$src" "$dst"
    log "installed $(basename "$src")"
    reload=1
  done
}

hide_profile || status=1
install_overrides || status=1

if [ "$reload" = 1 ] && systemctl -q is-active kodi.service; then
  kodi-send --action="ReloadSkin()" > /dev/null
fi
exit "$status"
