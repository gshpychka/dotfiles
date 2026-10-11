# Kodi runbook

CoreELEC box, reached as `ssh kodi`. Skin is Bingie (`skin.bingie`), library
comes from Plex on hoard through PlexKodiConnect (PKC). `/storage/.config`
survives CoreELEC updates; `/storage/.config/system.d` holds user systemd
units.

## Customizations

Kodi overwrites an addon's directory on every update, so `kodi-customize.sh`
reapplies these at boot and after each Bingie, Bingie Widgets or PKC update:

- subtitles at a fixed spot in the bottom letterbox bar, the same in every
  display mode (applied at boot only, while Kodi is stopped)
- hides the Bingie profile switcher at the top of the side menu
- installs every file in `skin-overrides/` into the skin, currently a
  Netflix-style PKC skip intro/credits button
- shows the Dolby Vision profile and HDR10+ from Plex in Bingie's HDR badge,
  e.g. "DV P8.1 · HDR10+" (`snippets/`)
- keeps an in-progress item's rating, year, HDR badges and plot on screen, with
  the progress bar under them
- lists files without subtitles in Bingie's widgets, e.g. Continue Watching
  (`snippets/`)

Deploy from eve:

```sh
scripts/kodi/deploy.sh
```

Settings changes land at the next boot (`ssh kodi reboot`). After a PKC patch
change, restart Kodi so PKC loads it (`ssh kodi systemctl restart kodi`).
Library items get new HDR details when PKC next syncs them; to rewrite all of
them, run PKC's repair sync:
`ssh kodi 'kodi-send --action="RunPlugin(plugin://plugin.video.plexkodiconnect/?mode=repair)"'`.

Removing a file from `skin-overrides/` does not remove the installed copy from
the skin; delete it from `skin.bingie/1080i` as well.

If an addon release moves something a patch anchors on, the script logs
`anchor not found` and leaves that file untouched:
`ssh kodi journalctl -t kodi-customize`.

To undo: disable both units, delete them and `/storage/.config/kodi-customize`,
then reinstall Bingie, Bingie Widgets and PKC from their repositories to
restore the original files. The settings stay until changed in Kodi.

## CoreELEC build

The box runs CPM's CoreELEC fork with Kodi 22, built from source. CPM's Kodi
does player-led Dolby Vision: the box runs the Dolby Vision processing and
sends HDR10, which is how the Samsung S95C, a TV without Dolby Vision, shows
profile 7 FEL. CPM publishes no builds.

`cpm/build.sh` pins `cpm-code/CoreELEC`, which in turn pins its Kodi
(`cpm-code/xbmc`) and kernel (`cpm-code/linux-amlogic`), and adds the patches
in `cpm/patches/`, one directory per package:

- `kodi/local-demux-replay-seek.patch` drops the packets the startup probes
  queue when playback seeks, so a resumed movie starts with audio and picture
  in sync
- `kodi/local-window-close-message-flags.patch` reads a cross-thread window
  close's force and sound flags from the field the sender fills, so a forced
  close requested off the main thread completes
- `kodi/local-render-osd-on-main-thread.patch` keeps the OSD and seek bar on
  Kodi's main thread. CPM's overlay worker renders them from a second GL
  context, and Kodi's GUI renderer keeps its shaders, matrices and viewport as
  state both contexts share, so the worker's output comes out invisible or
  mirrored
- `linux/local-dv-hdmi-pkt-cache-reset.patch` clears the Dolby Vision driver's
  record of the HDMI packets it sent when Dolby Vision turns off. The driver
  skips a packet identical to the recorded one, and other drivers set the
  packets while Dolby Vision is off, so each Dolby Vision playback sends its
  HDR10 and BT.2020 signalling
- `linux/local-dv-ll-brightness-reset.patch` clears the Dolby Vision brightness
  adjustment when Dolby Vision turns off. The adjustment sits in the video
  post-processing every output passes through, so HDR10, HDR10+ and SDR
  playback that follows Dolby Vision keeps the source's black level

Build on reaper. The first build takes a few hours; a Kodi-only change takes
minutes:

```sh
scripts/kodi/cpm/build.sh > ~/build/cpm-build.log 2>&1
```

Install from reaper. The script backs the box up to `~/build/kodi-backup-<time>`
first, then reboots it into the update:

```sh
scripts/kodi/cpm/flash.sh ~/build/cpm-coreelec/target/CoreELEC-Amlogic-ng.aarch64-<version>.tar
```

`ssh kodi grep VERSION= /etc/os-release` shows the running build. To roll back
(untested): unpack the backup's `flash.tar` over `/flash` after
`mount -o remount,rw /flash`, and reboot. `storage.tar` holds Kodi's state,
with the databases in `.dbbackup/`.

These live in Kodi's own settings and survive updates:

- Settings > System > CoreELEC > Dolby Vision: mode On demand, type Player-led
  (HDR), VS10 off for every source except Dolby Vision, DV-LL limit "Min PQ 20
  and limit max" with brightness adjustment -1, the combination that clips
  least near black on the S95C (the black-clipping patterns in hoard's
  `test-files` show from code 68 in Dolby Vision and 66 in HDR10)
- the dual-layer priority is Dolby Vision: for files carrying both, the S95C
  shows the box's Dolby Vision output brighter than its own HDR10+ processing
- the injected VSVDB describes the S95C: BT.2020, 0 to 1252 cd/m², payload
  `4903885698A953`; RTINGS measures its peak at about 1,200–1,230 cd/m²
- the injected HDR InfoFrame payload
  `3421AA9B9619FC08488A0839133D4240B0040100CE04EA00` declares BT.2020, mastering
  1200 cd/m², MaxCLL 1230, MaxFALL 234
- Skin Shortcuts is pinned at 2.1.0, the pin Kodi records when an add-on is
  downgraded; 3.x refuses Bingie
- InfoTagger is 0.0.9 from
  [its author](https://github.com/jurialmunkey/script.module.infotagger/tree/c6272475996215648d19fd030dd12b3cadc1bd23),
  unpacked over `addons/script.module.infotagger`. Kodi's repository has 0.0.8,
  which drops every video stream carrying Kodi 22's `hdrdetail` field

The CoreELEC settings pages for Network and Bluetooth fail to load: PyGObject
calls `pkgutil.get_loader`, which Python 3.14 removed.
