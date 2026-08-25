#!/usr/bin/env bash
# Installs a custom wallpaper on the GL.iNet Mudi's touchscreen. Run from eve.
#
# gl_screen reads its images from /etc/gl_screen/image at runtime, so replacing
# the files and restarting it is the whole mechanism.
#
# The panel is 240x320 (fb0 virtual_size). wallpaper.png is 1x and
# wallpaper_home_style_default.png is the 2x asset, so both sizes are needed;
# each must be 8-bit RGBA to match what ships.
#
# Originals are kept as *.orig on the device and are never overwritten by a
# rerun, so reverting is a copy back plus a restart.
#
# /etc/gl_screen belongs to gl-sdk4-screen-large and is outside the sysupgrade
# keep list, so the four paths are registered in /etc/sysupgrade.conf.

set -euo pipefail

SMALL=${1:?usage: mudi-wallpaper.sh <240x320.png> <480x640.png> [host]}
LARGE=${2:?usage: mudi-wallpaper.sh <240x320.png> <480x640.png> [host]}
HOST=${3:-192.168.8.1}

IMG=/etc/gl_screen/image

for f in "$SMALL" "$LARGE"; do
    [ -f "$f" ] || { echo "no such file: $f" >&2; exit 1; }
done

# the router has no sftp-server, so scp is out
ssh "root@$HOST" "cd $IMG && for f in wallpaper.png wallpaper_home_style_default.png; do
    [ -f \"\$f.orig\" ] || cp \"\$f\" \"\$f.orig\"
done"

ssh "root@$HOST" "cat > $IMG/wallpaper.png" < "$SMALL"
ssh "root@$HOST" "cat > $IMG/wallpaper_home_style_default.png" < "$LARGE"

ssh "root@$HOST" "
for p in $IMG/wallpaper.png $IMG/wallpaper_home_style_default.png \
         $IMG/wallpaper.png.orig $IMG/wallpaper_home_style_default.png.orig; do
    grep -qxF \"\$p\" /etc/sysupgrade.conf || echo \"\$p\" >> /etc/sysupgrade.conf
done
/etc/init.d/gl_screen restart
"

echo "installed; wake the screen to see it"
echo "revert: ssh root@$HOST 'cd $IMG && cp wallpaper.png.orig wallpaper.png &&"
echo "        cp wallpaper_home_style_default.png.orig wallpaper_home_style_default.png &&"
echo "        /etc/init.d/gl_screen restart'"
