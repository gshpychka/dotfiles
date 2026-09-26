#!/bin/sh
# Customizations to Kodi settings, the Bingie skin and PlexKodiConnect on the
# kodi box. Kodi overwrites an addon's directory on every update, so this is
# idempotent and reruns at boot and after each update
# (kodi-customize.{service,path}). Deployment: scripts/kodi/runbook.md.
set -eu

HERE=$(dirname "$(readlink -f "$0")")
ADDONS=/storage/.kodi/addons
SKIN=$ADDONS/skin.bingie/1080i
PKC_MEDIA=$ADDONS/plugin.video.plexkodiconnect/resources/lib/plex_api/media.py
GUISETTINGS=/storage/.kodi/userdata/guisettings.xml

# Subtitles sit at a fixed spot near the bottom of the screen. Almost every
# film in the library has its letterbox bars baked into a 16:9 frame, so Kodi's
# "bottom of video, outside" places them over the picture. Kodi keeps the
# position per display mode; every mode whose GUI is 1080 lines tall gets the
# same one, low enough for two lines to fit in a 2.39:1 bar.
SUBTITLES_ALIGN_MANUAL=0
SUBTITLES_POSITION_1080=1080

log() { logger -t kodi-customize "$1"; echo "$1"; }

status=0
reload_skin=0

# Inserts SNIPPET before the single line of FILE containing ANCHOR, indented
# like that line. A snippet starts with a unique marker line and ends with a
# line containing "kodi-customize: end". If FILE already has the block, this
# does nothing when it matches SNIPPET and replaces it otherwise. Returns 0
# only when it changed FILE.
insert_before() {
  file=$1 anchor=$2 snippet=$3
  marker=$(head -n 1 "$snippet")
  if grep -qF "$marker" "$file"; then
    current=$(awk -v marker="$marker" '
      index($0, marker) { inblock = 1 }
      inblock { sub(/^[ \t]*/, ""); print }
      inblock && /kodi-customize: end/ { exit }
    ' "$file")
    [ "$current" = "$(sed 's/^[ \t]*//' "$snippet")" ] && return 1
    if ! awk -v marker="$marker" '
      index($0, marker) { inblock = 1 }
      inblock { if (/kodi-customize: end/) inblock = 0; next }
      { print }
      END { exit inblock ? 2 : 0 }
    ' "$file" > "$file.tmp.$$"; then
      rm -f "$file.tmp.$$"
      log "block in $file has no end marker, left untouched; restore the addon's file"
      status=1
      return 1
    fi
    mv "$file.tmp.$$" "$file"
  fi
  if [ "$(grep -cF "$anchor" "$file")" != 1 ]; then
    log "anchor not unique or missing in $file, addon changed; update this script: $anchor"
    status=1
    return 1
  fi
  awk -v anchor="$anchor" -v snippet="$snippet" '
    index($0, anchor) {
      match($0, /^[ \t]*/)
      indent = substr($0, 1, RLENGTH)
      while ((getline line < snippet) > 0) print (line == "" ? "" : indent line)
    }
    { print }
  ' "$file" > "$file.tmp.$$"
  mv "$file.tmp.$$" "$file"
}

# Hide the profile switcher at the top of the side menu; Bingie has no setting
# for it. It is the group right after the "Logo / user profile button" comment
# in BingieSideBladeMainMenu. Setting its <visible> to false also makes its
# button (id 40000) unfocusable, so the menu's <onup>40000</onup> goes nowhere.
hide_profile() {
  file="$SKIN/IncludesBingie.xml"
  marker='<!-- kodi-bingie-hide-profile -->'
  grep -qF "$marker" "$file" && return 0
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
  ' "$file" > "$file.tmp.$$"; then
    rm -f "$file.tmp.$$"
    log "profile switcher anchor not found, skin layout changed; update this script"
    status=1
    return 0
  fi
  mv "$file.tmp.$$" "$file"
  log "profile switcher hidden"
  reload_skin=1
}

# PKC records only whether Dolby Vision is present. Plex also reports the DV
# profile and HDR10+; snippets/pkc-hdr.py adds them to the HDR type that PKC
# writes into Kodi's library. A running PKC keeps the old code until Kodi
# restarts, and existing items only change on a PKC "repair" sync.
pkc_hdr() {
  [ -f "$PKC_MEDIA" ] || return 0
  cp "$PKC_MEDIA" "$PKC_MEDIA.orig.$$"
  if insert_before "$PKC_MEDIA" "videotracks.append(track)" "$HERE/snippets/pkc-hdr.py"; then
    if python3 -m py_compile "$PKC_MEDIA" 2> /dev/null; then
      log "PKC HDR details patched; restart Kodi to load it"
    else
      mv "$PKC_MEDIA.orig.$$" "$PKC_MEDIA"
      log "PKC HDR patch does not compile, reverted; update this script"
      status=1
    fi
  fi
  rm -f "$PKC_MEDIA.orig.$$"
}

# Bingie compares the HDR type to exactly hdr10, dolbyvision and hlg. Prefix
# matches accept the values from pkc_hdr too, and the HDR row and flag read the
# variables in snippets/bingie-hdr-variables.xml. VideoPlayer.HdrType comes from
# the playing stream, which never has these values, so it stays as is.
bingie_hdr() {
  if insert_before "$SKIN/IncludesVariables.xml" '<variable name="VideoHDRVar">' \
    "$HERE/snippets/bingie-hdr-variables.xml"; then
    log "Bingie HDR variables added"
    reload_skin=1
  fi
  for file in "$SKIN/IncludesBingie.xml" "$SKIN/IncludesMediaFlags.xml"; do
    grep -qE 'String\.IsEqual\(List[iI]tem\.HdrType,(dolbyvision|hdr10)\)|\$INFO\[List[iI]tem\.HdrType,/video/,\.png\]|\$VAR\[VideoHDRVar\]' "$file" || continue
    sed -i \
      -e 's/String\.IsEqual(List[iI]tem\.HdrType,dolbyvision)/String.StartsWith(ListItem.HdrType,dolbyvision)/g' \
      -e 's/String\.IsEqual(List[iI]tem\.HdrType,hdr10)/String.StartsWith(ListItem.HdrType,hdr10)/g' \
      -e 's#\$INFO\[List[iI]tem\.HdrType,/video/,\.png\]#/video/$VAR[KodiCustomizeHdrFlag].png#g' \
      -e 's/\$VAR\[VideoHDRVar\]/$VAR[KodiCustomizeHdrLabel]/g' \
      "$file"
    log "Bingie HDR conditions patched in $(basename "$file")"
    reload_skin=1
  done
  # The HDR badge sizes to its label but caps the text at 160px, which cuts
  # off "DV P8.1 · HDR10+".
  file="$SKIN/IncludesBingie.xml"
  range='/<include name="HDR_Details_Row">/,/<\/control>/'
  if sed -n "$range p" "$file" | grep -q '<textwidth>160</textwidth>'; then
    sed -i "$range s#<textwidth>160</textwidth>#<textwidth>320</textwidth>#" "$file"
    log "Bingie HDR badge widened"
    reload_skin=1
  fi
}

# Kodi rewrites guisettings.xml from memory when it exits, so this only runs
# while Kodi is stopped, i.e. at boot before kodi.service.
kodi_settings() {
  awk -v align="$SUBTITLES_ALIGN_MANUAL" -v pos="$SUBTITLES_POSITION_1080" '
    /<setting id="subtitles.align"/ {
      sub(/<setting id="subtitles.align"[^>]*>[0-9]+</, "<setting id=\"subtitles.align\">" align "<")
    }
    /<resolution>/ { inres = 1; buf = "" }
    inres {
      buf = buf $0 "\n"
      if (/<\/resolution>/) {
        if (buf ~ /<bottom>1080<\/bottom>/)
          gsub(/<subtitles>[0-9]+<\/subtitles>/, "<subtitles>" pos "</subtitles>", buf)
        printf "%s", buf
        inres = 0
      }
      next
    }
    { print }
  ' "$GUISETTINGS" > "$GUISETTINGS.tmp.$$"
  if [ "$(md5sum < "$GUISETTINGS.tmp.$$")" = "$(md5sum < "$GUISETTINGS")" ]; then
    rm -f "$GUISETTINGS.tmp.$$"
    return 0
  fi
  mv "$GUISETTINGS.tmp.$$" "$GUISETTINGS"
  log "subtitle position settings applied"
}

# Whole-window overrides, e.g. PlexKodiConnect's skip marker dialog. Kodi
# resolves an addon's window XML in the active skin first, but only sees a new
# file in the skin directory after a skin reload.
install_overrides() {
  for src in "$HERE"/skin-overrides/*.xml; do
    [ -f "$src" ] || continue
    dst="$SKIN/$(basename "$src")"
    if [ -f "$dst" ] && [ "$(md5sum < "$src")" = "$(md5sum < "$dst")" ]; then
      continue
    fi
    cp "$src" "$dst"
    log "installed $(basename "$src")"
    reload_skin=1
  done
}

pkc_hdr
if [ -f "$GUISETTINGS" ] && ! systemctl -q is-active kodi.service; then
  kodi_settings
fi
if [ -d "$SKIN" ]; then
  hide_profile
  bingie_hdr
  install_overrides
fi

if [ "$reload_skin" = 1 ] && systemctl -q is-active kodi.service; then
  kodi-send --action="ReloadSkin()" > /dev/null
fi
exit "$status"
